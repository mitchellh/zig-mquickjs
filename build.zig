const std = @import("std");
const Module = std.Build.Module;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_step = b.step("test", "Run tests");

    const upstream = b.dependency("mquickjs", .{});

    // mquickjs_c module for C APIs
    const mquickjs_c: *Module = c: {
        // Translate header and add it to our module.
        const translate = b.addTranslateC(.{
            .root_source_file = upstream.path("mquickjs.h"),
            .target = target,
            .optimize = optimize,
        });

        // mquickjs.h doesn't include the C standard header it needs
        // to define size_t, so we define it here using the target
        // pointer size.
        translate.defineCMacro("size_t", switch (target.result.ptrBitWidth()) {
            32 => "uint32_t",
            64 => "uint64_t",
            else => @panic("unsupported pointer size"),
        });

        // Publish the module!
        break :c translate.addModule("c");
    };

    // mquickjs Zig module
    const mod = module: {
        const mod = b.addModule("mquickjs", .{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        });

        // Depends on the C headers
        mod.addImport("mquickjs_c", mquickjs_c);

        break :module mod;
    };

    // Test
    {
        const test_mod = b.addTest(.{
            .name = "test",
            .root_module = mod,
        });
        const tests_run = b.addRunArtifact(test_mod);
        test_step.dependOn(&tests_run.step);

        // Tests depend on the mquickjs library
        test_mod.linkLibrary(try library(
            b,
            target,
            optimize,
            try stdlibGen(b, .{
                .file = b.path("test_stdlib.c"),
                .flags = stdlib_gen_flags,
            }),
        ));
    }
}

/// Returns the step to compile the static library for mquickjs. This
/// returns the step so you can continue to add more source files
/// as necessary for things like stdlib ROM data.
pub fn library(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    stdlib_gen: ?*std.Build.Step.Compile,
) !*std.Build.Step.Compile {
    const upstream = b.dependency("mquickjs", .{});

    var flags: std.ArrayList([]const u8) = .empty;
    try flags.appendSlice(b.allocator, &.{
        "-D_GNU_SOURCE",
        "-fno-math-errno",
        "-fno-trapping-math",
        "-fno-omit-frame-pointer",
        "-fno-sanitize=undefined",
        "-fno-sanitize-trap=undefined",
    });

    const lib = b.addLibrary(.{
        .name = "mquickjs",
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    // Default stdlib generator
    const mqjs_stdlib = try stdlibGen(b, .{
        .file = upstream.path("mqjs_stdlib.c"),
        .flags = stdlib_gen_flags,
    });

    // Generate the standard atoms list.
    const mquickjs_atom_h = atoms: {
        const gen_atoms = b.addRunArtifact(mqjs_stdlib);
        gen_atoms.addArg("-a");

        // Write stdout to a file named mquickjs_atom.h
        const wf = b.addWriteFiles();
        break :atoms wf.addCopyFile(
            gen_atoms.captureStdOut(),
            "mquickjs_atom.h",
        );
    };

    // Add our standard library if needed.
    if (stdlib_gen) |gen| {
        const js_stdlib_h = header: {
            const run = b.addRunArtifact(gen);
            const wf = b.addWriteFiles();
            break :header wf.addCopyFile(
                run.captureStdOut(),
                "js_stdlib.h",
            );
        };
        const stdlib_wrapper = wrapper: {
            const wf = b.addWriteFiles();
            break :wrapper wf.add("js_stdlib_wrapper.c",
                \\#include <stddef.h>
                \\#include "js_stdlib.h"
            );
        };
        lib.addIncludePath(js_stdlib_h.dirname());
        lib.addCSourceFile(.{
            .file = stdlib_wrapper,
            .flags = flags.items,
        });
    }

    // Include paths
    lib.addIncludePath(mquickjs_atom_h.dirname());
    lib.addIncludePath(upstream.path(""));
    lib.installHeader(
        upstream.path("mquickjs.h"),
        "mquickjs.h",
    );

    // C build
    lib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{
            "mquickjs.c",
            "cutils.c",
            "dtoa.c",
            "libm.c",
        },
        .flags = flags.items,
    });

    return lib;
}

/// Returns a compile step that produces the executable to generate a
/// stdlib ROM for mquickjs. You must add your C file that has all the
/// necessary calls similar to mquickjs_stdlib.c.
pub fn stdlibGen(
    b: *std.Build,
    def: ?Module.CSourceFile,
) !*std.Build.Step.Compile {
    const upstream = b.dependency("mquickjs", .{});

    const stdlib = b.addExecutable(.{
        .name = "mqjs_stdlib",
        .root_module = b.createModule(.{
            .target = b.graph.host,
            .optimize = .Debug,
        }),
    });
    stdlib.linkLibC();
    stdlib.addIncludePath(upstream.path(""));
    stdlib.addCSourceFiles(.{
        .root = upstream.path(""),
        .files = &.{"mquickjs_build.c"},
        .flags = stdlib_gen_flags,
    });
    if (def) |v| stdlib.addCSourceFile(v);

    return stdlib;
}

/// These are the flags to use for C files with stdlibGen (at a minimum).
/// This ensures compatibility with how mquickjs is intended to be built.
pub const stdlib_gen_flags: []const []const u8 = &.{
    "-D_GNU_SOURCE",
    "-fno-math-errno",
    "-fno-trapping-math",
    "-Werror",
    "-fno-omit-frame-pointer",
    "-fno-sanitize=undefined",
    "-fno-sanitize-trap=undefined",
};
