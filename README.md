# Starpatch

Simple file patcher made in [Zig](https://ziglang.org/) using [raylib](https://raylib.com)

It is the last tool from a set created for ROM hacking (any file in reality). The other two are:

- [Stardust](https://github.com/SultansOfCode/Stardust): a simple hexadecimal editor with extra features like symbols' table and relative search
- [Startile](https://github.com/SultansOfCode/Startile): a simple tile editor

Raylib was not entirely needed in this project, but I wanted to use its helper functionalities

All these projects were developed to better learn Zig and raylib

## Building

Simply clone/download this repository and run:

```
$ zig build
```

## Using

### Create a patch

To create a patch file, run:

```
$ Starpatch create <original file> <patched file> <patch file>
```

It will create the `patch file` with all patches needed to make `original file` become the `patched file`. This file can later be applied with the other commands

### Patch a file

To patch a file, run:

```
$ Starpatch patch <original file> <patch file> <patched file>
```

It will create the `patched file` with all patches contained in `patch file` applied to the `original file`

### Unpatch a file

To unpatch a file, run:

```
$ Starpatch unpatch <patched file> <patch file> <original file>
```

It will create the `original file` with all patches contained in `patch file` unapplied to the `patched file`

## Examples

You can check the [`run.bat`](https://github.com/SultansOfCode/Starpatch/blob/main/run.bat), [`resources/bigger.txt`](https://github.com/SultansOfCode/Starpatch/blob/main/resources/bigger.txt) and [`resources/smaller.txt`](https://github.com/SultansOfCode/Starpatch/blob/main/resources/smaller.txt) to see how it works and in action

### Thanks

People from [Twitch](https://twitch.tv/SultansOfCode) for watching me and supporting me while developing it

All of my [LivePix](https://livepix.gg/sultansofcode) donators

---

### Sources and licenses

raylib - [Source](https://github.com/raysan5/raylib) - [Zlib license](https://github.com/raysan5/raylib?tab=Zlib-1-ov-file)

Zig - [Source](https://github.com/ziglang/zig) - [MIT license](https://github.com/ziglang/zig?tab=MIT-1-ov-file)
