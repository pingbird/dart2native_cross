#!/usr/bin/env dart
// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:args/args.dart';
import 'package:dart2native_cross/dart2native_cross.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;

final String executableSuffix = Platform.isWindows ? '.exe' : '';
final String scriptDir = path.canonicalize(path.join(path.dirname(
    Platform.script.toFilePath()), '..'));
final String toolsDir = path.join(scriptDir, 'tools');
final String artifactsDir = path.join(scriptDir, 'artifacts');
final String dartPath = Platform.resolvedExecutable;
final String binDir = path.dirname(dartPath);
final String sdkDir = path.canonicalize(path.join(binDir, '..'));
final String snapshotsDir = path.join(binDir, 'snapshots');
final String genKernel = path.join(snapshotsDir, 'gen_kernel.dart.snapshot');
final platformDill =
    path.join(sdkDir, 'lib', '_internal', 'vm_platform_strong.dill');

String targetExtensionOf(String os) => os == 'windows' ||
    (os == 'host' && Platform.isWindows) ? '.exe' : '';

Future<void> generateNative({
    OutputKind kind = OutputKind.exe,
    String os = 'host',
    String arch = 'host',
    @required String sourceFile,
    @required String outputFile,
    String packages,
    List<String> defines = const [],
    bool enableAsserts = false,
    bool verbose = false}) async {
  final Directory tempDir = Directory.systemTemp.createTempSync();
  try {
    final hostOS = Platform.operatingSystem;
    final hostArch = RegExp(r'on ".+?_(.+?)"$')
        .firstMatch(Platform.version).group(1);

    if (os == 'host') {
      os = hostOS;
    }

    if (arch == 'host') {
      arch = hostArch;
    }

    final targetArtifactsDir = path.join(artifactsDir, os + '-' + arch);

    if (!File(platformDill).existsSync()) {
      stderr.writeln('Error: Could not find "$platformDill"');
      exit(1);
    }

    final genSnapshot = path.join(toolsDir, hostOS + '-' + hostArch,
        os + '-' + arch, 'gen_snapshot$executableSuffix');

    if (!File(genSnapshot).existsSync()) {
      stderr.writeln('Error: Could not find "$genSnapshot"');
      exit(1);
    }

    final targetExtension = targetExtensionOf(os);
    final dartaotruntime =
        path.join(targetArtifactsDir, 'dartaotruntime$targetExtension');

    if (!File(dartaotruntime).existsSync()) {
      stderr.writeln('Error: Could not find "$dartaotruntime"');
      exit(1);
    }

    final kernelFile = path.join(tempDir.path, 'kernel.dill');

    final snapshotFile = (kind == OutputKind.aot
        ? outputFile
        : path.join(tempDir.path, 'snapshot.aot'));

    if (verbose) {
      print('Generating AOT kernel dill.');
    }
    final kernelResult = await generateAotKernel(
        dartPath, genKernel, platformDill,
        sourceFile, kernelFile, packages, defines);
    if (kernelResult.exitCode != 0) {
      stderr.writeln(kernelResult.stdout);
      stderr.writeln(kernelResult.stderr);
      await stderr.flush();
      throw 'Generating AOT kernel dill failed!';
    }

    if (verbose) {
      print('Generating AOT snapshot.');
    }
    final snapshotResult = await generateAotSnapshot(
        genSnapshot, kernelFile, snapshotFile, enableAsserts);
    if (snapshotResult.exitCode != 0) {
      stderr.writeln(snapshotResult.stdout);
      stderr.writeln(snapshotResult.stderr);
      await stderr.flush();
      throw 'Generating AOT snapshot failed!';
    }

    if (kind == OutputKind.exe) {
      if (verbose) {
        print('Generating executable.');
      }
      await writeAppendedExecutable(dartaotruntime, snapshotFile, outputFile);

      if (Platform.isLinux || Platform.isMacOS) {
        if (verbose) {
          print('Marking binary executable.');
        }
        await markExecutable(outputFile);
      }
    }

    print('Generated: ${outputFile}');
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}

void printUsage(final ArgParser parser) {
  print('''
Usage: dart2native_cross <main-dart-file> [<options>]

Generates an executable or an AOT snapshot from <main-dart-file>.
''');
  print(parser.usage);
}

Future<void> main(List<String> args) async {
  // If we're outputting to a terminal, wrap usage text to that width.
  int outputLineWidth = null;
  try {
    outputLineWidth = stdout.terminalColumns;
  } catch (_) {/* Ignore. */}

  final ArgParser parser = ArgParser(usageLineLength: outputLineWidth)
    ..addMultiOption('define', abbr: 'D', valueHelp: 'key=value', help: '''
Set values of environment variables. To specify multiple variables, use multiple options or use commas to separate key-value pairs.
E.g.: dart2native_cross -Da=1,b=2 main.dart''')
    ..addFlag('enable-asserts',
        negatable: false, help: 'Enable assert statements.')
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Display this help message.')
    ..addOption(
      'output-kind',
      abbr: 'k',
      allowed: ['aot', 'exe'],
      allowedHelp: {
        'aot': 'Generate an AOT snapshot.',
        'exe': 'Generate a standalone executable.',
      },
      defaultsTo: 'exe',
      valueHelp: 'aot|exe',
    )
    ..addOption(
      'os',
      abbr: 't',
      allowed: ['host', 'windows', 'linux', 'macos', 'android'],
      defaultsTo: 'host',
      valueHelp: 'host|windows|linux|macos|android',
    )
    ..addOption(
      'arch',
      abbr: 'a',
      allowed: ['host', 'arm', 'arm64', 'ia32', 'x64'],
      defaultsTo: 'host',
      valueHelp: 'host|arm|arm64|ia32|x64',
    )
    ..addOption('output', abbr: 'o', valueHelp: 'path', help: '''
Set the output filename. <path> can be relative or absolute.
E.g.: dart2native_cross main.dart -o ../bin/my_app.exe
''')
    ..addOption('packages', abbr: 'p', valueHelp: 'path', help: '''
Get package locations from the specified file instead of .packages. <path> can be relative or absolute.
E.g.: dart2native_cross --packages=/tmp/pkgs main.dart
''')
    ..addFlag('verbose',
        abbr: 'v', negatable: false, help: 'Show verbose output.');

  ArgResults parsedArgs;
  try {
    parsedArgs = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('Error: ${e.message}');
    await stderr.flush();
    printUsage(parser);
    exit(1);
  }

  if (parsedArgs['help']) {
    printUsage(parser);
    exit(0);
  }

  if (parsedArgs.rest.length != 1) {
    printUsage(parser);
    exit(1);
  }

  final OutputKind kind = {
    'aot': OutputKind.aot,
    'exe': OutputKind.exe,
  }[parsedArgs['output-kind']];

  final targetExtension = targetExtensionOf(parsedArgs['os']);

  final sourcePath = path.canonicalize(path.normalize(parsedArgs.rest[0]));
  final sourceWithoutDart = sourcePath.replaceFirst(new RegExp(r'\.dart$'), '');
  final outputPath =
      path.canonicalize(path.normalize(parsedArgs['output'] != null
          ? parsedArgs['output']
          : {
              OutputKind.aot: '${sourceWithoutDart}.aot',
              OutputKind.exe: '${sourceWithoutDart}${targetExtension}',
            }[kind]));

  if (!FileSystemEntity.isFileSync(sourcePath)) {
    stderr.writeln(
        '"${sourcePath}" is not a file. See \'--help\' for more information.');
    await stderr.flush();
    exit(1);
  }

  try {
    await generateNative(
        kind: kind,
        os: parsedArgs['os'],
        arch: parsedArgs['arch'],
        sourceFile: sourcePath,
        outputFile: outputPath,
        packages: parsedArgs['packages'],
        defines: parsedArgs['define'],
        enableAsserts: parsedArgs['enable-asserts'],
        verbose: parsedArgs['verbose']);
  } catch (e) {
    stderr.writeln('Failed to generate native files:');
    stderr.writeln(e);
    await stderr.flush();
    exit(1);
  }
}
