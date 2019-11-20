import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;

void main() async {
  var env = Platform.environment;

  if (!env.containsKey("DART_SDK")) {
    stderr.writeln("Error: DART_SDK not set.");
    exit(1);
  }

  var sdkDir = env["DART_SDK"];

  Future<void> build(String arch, String targets) async {
    var proc = await Process.start("python", [
      path.join(sdkDir, "tools", "build.py"),
      "-m", "product", "-a", arch, ...targets.split(" "),
    ], workingDirectory: sdkDir);

    proc.stderr.transform(Utf8Decoder()).listen(stderr.write);
    proc.stdout.transform(Utf8Decoder()).listen(stdout.write);

    if (await proc.exitCode != 0) {
      exit(1);
    }
  }

  var hostOS = Platform.operatingSystem;
  var hostArch = RegExp(r'on ".+?_(.+?)"$')
      .firstMatch(Platform.version).group(1);
  var host = "$hostOS-$hostArch";

  await build("x64", "gen_snapshot copy_dartaotruntime");
  await build("simarm", "gen_snapshot");
  await build("simarm64", "gen_snapshot");
  await build("arm", "copy_dartaotruntime");
  await build("arm64", "copy_dartaotruntime");

  var outDir = path.join(sdkDir, "out");
  var scriptDir = path.canonicalize(path.join(
    path.dirname(Platform.script.path), ".."
  ));

  try {
    await Directory(path.join(scriptDir, "tools")).delete(recursive: true);
    await Directory(path.join(scriptDir, "artifacts")).delete(recursive: true);
  } on FileSystemException catch (e) {}

  Future<void> copy(List<String> from, List<String> to) async {
    var fPath = path.joinAll([outDir, ...from]);
    var tPath = path.joinAll([scriptDir, ...to, from.last]);
    await Directory(path.dirname(tPath)).create(recursive: true);
    await File(fPath).copy(tPath);
  }

  var ext = Platform.isWindows ? ".exe" : "";

  await Future.wait([
    copy(["ProductX64/exe.stripped", "dartaotruntime$ext"], ["artifacts", host]),
    copy(["ProductX64/exe.stripped", "gen_snapshot$ext"], ["tools", host, host]),

    if (!Platform.isWindows)
      copy(["ProductXARM/exe.stripped", "dartaotruntime"], ["artifacts/linux-arm"]),
    copy(["ProductSIMARM/exe.stripped", "gen_snapshot$ext"], ["tools", host, "linux-arm"]),

    if (!Platform.isWindows)
      copy(["ProductXARM64/exe.stripped", "dartaotruntime"], ["artifacts/linux-arm64"]),
    copy(["ProductSIMARM64/exe.stripped", "gen_snapshot$ext"], ["tools", host, "linux-arm64"]),
  ]);
}