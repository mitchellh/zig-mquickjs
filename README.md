# zig-mquickjs

Zig build and bindings for [Micro QuickJS](https://github.com/nicklaros/mquickjs).

## Example

```zig
const mquickjs = @import("mquickjs");

pub fn main() !void {
    var buf: [1024 * 64]u8 align(8) = undefined;
    const ctx = try mquickjs.Context.new(&buf, &your_stdlib);
    defer ctx.free();

    // Evaluate JavaScript
    const result = mquickjs.Value.eval(ctx,
        \\(function() { return 40 + 2; })()
    , "<main>", .{ .retval = true });
  assert(!result.isException());

  const value = result.toInt32(ctx);
  assert(value == 42);
}
```

## Usage

Integrating zig-mquickjs into your Zig project is slightly different
than a standard Zig dependency because mquickjs works by building a ROM
for your JS stdlib. It isn't much harder though! You have to import the
`mquickjs` dependency and call `library` and `stdlibGen` functions to
setup the lib for you.

**Zig version: zig-mquickjs only works with the released version of Zig specified
in the `build.zig.zon` file.** We don't support
nightly versions because the Zig compiler is still changing too much.

### Add Dependency

Add this to your `build.zig.zon`:

```zig
.{
    .name = "my-project",
    .version = "0.0.0",
    .dependencies = .{
        .mquickjs = .{
            .url = "https://github.com/mitchellh/zig-mquickjs/archive/<git-ref-here>.tar.gz",
            .hash = "...",
        },
    },
}
```

### Configure build.zig

In your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "my-app",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Get the mquickjs dependency
    const mquickjs = @import("mquickjs");
    const dep = b.dependency("mquickjs", .{
        .target = target,
        .optimize = optimize,
    });

    // Add the Zig module
    exe.root_module.addImport("mquickjs", dep.module("mquickjs"));

    // Build and link the C library with your stdlib
    const lib = try mquickjs.library(
        dep.builder,
        target,
        optimize,
        try mquickjs.stdlibGen(dep.builder, .{
            .file = b.path("src/stdlib.c"),
            .flags = mquickjs.stdlib_gen_flags,
        }),
    );
    exe.linkLibrary(lib);

    b.installArtifact(exe);
}
```

## Documentation

Read the source code and header files - they are well commented.
