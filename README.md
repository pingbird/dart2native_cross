# dart2native_cross

This is a fork of Dart 2.7.0's dart2native which allows cross-compilation.

## Usage

dart2native_cross has the same command line args as the built-in dart2native but has two extra parameters:

```
-t, --os=<host|windows|linux|macos|android>    [host (default), windows, linux, macos, android]
-a, --arch=<host|arm|arm64|ia32|x64>           [host (default), arm, arm64, ia32, x64]
```

To cross-compile from windows to ARM you would do:
```
dart2native_cross -t linux -a arm bin/main.dart -o program
```

In order to compile for a specific target you must have the following files in the dart2native_cross package directory:
```
artifacts/<target>/dartaotruntime
tools/<host>/<target>/gen_snapshot[.exe]
```
On a windows host the example above would require the following binaries:
```
artifacts/linux-arm/dartaotruntime
tools/windows-x64/linux-arm/gen_snapshot.exe
```

## Install

Requires Dart 2.7.0.

Either follow the build instructions below or use a prebuilt one from [releases](https://github.com/PixelToast/dart2native_cross/releases).

And then run the following to install it:

```
pub get
pub global activate --source path .
```

## Build

First [download](https://github.com/dart-lang/sdk/wiki/Building) the Dart SDK.

In order to compile for a specific target platform you need two things:
1. A `gen_snapshot` tool for your host  that can compile AOT snapshots for your target
2. A `dartaotruntime` for your target

For some targets (from Windows to Linux) you will need to compile the `dartaotruntime` on the target operating system.

At the moment the big limitation is that gen_snapshot can only cross compile to Linux/Android ARM/ARM64,
if you are looking for x64 Linux to Windows or vise versa you are out of luck for now.

For ARM Linux targets on an x64 host run the following commands: 
```
# ARMv7 / A32
tools/build.py -a simarm -m product dart-sdk/bin/gen_snapshot
# ARMv8 / A64
tools/build.py -a simarm64 -m product dart-sdk/bin/gen_snapshot
```
If you are on a Windows host you have to install the Dart SDK separately on a Linux machine in order to build dartaotruntime. (it can be done by your ARM target machine)
```
# ARMv7 / A32
tools/build.py -a arm -m product dart-sdk/bin/dartaotruntime
# ARMv8 / A64
tools/build.py -a arm64 -m product dart-sdk/bin/dartaotruntime
```

Then copy the output binaries to dart2native_cross:
```
# From windows host
sdk/out/ProductSIMARM/dart-sdk/bin/gen_snapshot.exe -> dart2native_cross/tools/windows-x64/arm-linux/gen_snapshot.exe
sdk/out/ProductSIMARM64/dart-sdk/bin/gen_snapshot.exe -> dart2native_cross/tools/windows-x64/arm-linux64/gen_snapshot.exe
# From linux host
sdk/out/ProductSIMARM/dart-sdk/bin/gen_snapshot -> dart2native_cross/tools/linux-x64/arm-linux/gen_snapshot
sdk/out/ProductSIMARM64/dart-sdk/bin/gen_snapshot -> dart2native_cross/tools/linux-x64/arm-linux64/gen_snapshot
# From linux host or target
sdk/out/ProductARM/dart-sdk/bin/dartaotruntime -> dart2native_cross/artifacts/arm-linux/dartaotruntime
sdk/out/ProductARM64/dart-sdk/bin/dartaotruntime -> dart2native_cross/artifacts/arm-linux64/dartaotruntime
```
Where `<host>` is your host `windows-x64`/`linux-x64`/`macos-x64`

If done correctly you should now be able to cross-compile to linux-arm and linux-arm64.
