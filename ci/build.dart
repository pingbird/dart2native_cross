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

  Future<void> build(String platform, String targets) async {
    var args = [
      "-C", path.join("out", platform),
      "-v", ...targets.split(" "),
    ];

    print("ninja ${args.join(" ")}");

    var proc = await Process.start("ninja", args, workingDirectory: sdkDir);

    proc.stderr.transform(Utf8Decoder()).listen(stderr.write);
    proc.stdout.transform(Utf8Decoder()).listen(stdout.write);

    var exitCode = await proc.exitCode;
    if (exitCode != 0) {
      print("ninja failed with exit code $exitCode");
      exit(1);
    }
  }

  var hostOS = Platform.operatingSystem;
  var hostArch = RegExp(r'on ".+?_(.+?)"$')
      .firstMatch(Platform.version).group(1);
  var host = "$hostOS-$hostArch";

  await build("ProductX64", "gen_snapshot copy_dartaotruntime");
  await build("ProductSIMARM", "gen_snapshot");
  await build("ProductSIMARM64", "gen_snapshot");

  if (!Platform.isWindows) {
    await build("ProductXARM", "copy_dartaotruntime");
    await build("ProductXARM64", "copy_dartaotruntime");
  }

  var outDir = path.join(sdkDir, "out");
  var scriptDir = path.canonicalize(path.join(
    path.dirname(Platform.script.toFilePath()), ".."
  ));

  print("Script path: ${Platform.script.toFilePath()}");
  print("Output dir: $outDir");
  print("Script dir: $scriptDir");

  try {
    await Directory(path.join(scriptDir, "tools")).delete(recursive: true);
    await Directory(path.join(scriptDir, "artifacts")).delete(recursive: true);
  } on FileSystemException catch (e) {}

  Future<void> copy(List<String> from, List<String> to) async {
    var fPath = path.joinAll([outDir, ...from]);
    var tPath = path.joinAll([scriptDir, ...to, from.last]);
    print("Copying '$fPath' to '$tPath'");
    await Directory(path.dirname(tPath)).create(recursive: true);
    await File(fPath).copy(tPath);
  }

  var ext = Platform.isWindows ? ".exe" : "";
  var gensnapshot = "gen_snapshot$ext";
  var aotruntime = ["dart-sdk", "bin", "dartaotruntime"];

  await Future.wait([
    copy(["ProductX64", ...aotruntime], ["artifacts", host]),
    copy(["ProductX64", gensnapshot], ["tools", host, host]),

    if (!Platform.isWindows)
      copy(["ProductXARM", ...aotruntime], ["artifacts", "linux-arm"]),
    copy(["ProductSIMARM", gensnapshot], ["tools", host, "linux-arm"]),

    if (!Platform.isWindows)
      copy(["ProductXARM64", ...aotruntime], ["artifacts", "linux-arm64"]),
    copy(["ProductSIMARM64", gensnapshot], ["tools", host, "linux-arm64"]),
  ]);
}