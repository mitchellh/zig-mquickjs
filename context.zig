const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const c = @import("mquickjs_c");

extern const test_js_stdlib: c.JSSTDLibraryDef;

/// C: JSContext
pub const Context = opaque {
    /// Create a new context with the given standard library.
    ///
    /// The standard library must be created beforehand as a ROM using
    /// the `stdlibGen` build function.
    ///
    /// C: JS_NewContext
    ///
    /// Warning: if you provide a memory buffer that is too small, this
    /// will simply segfault. I don't know if this should be considered
    /// a mquickjs bug or not. The memory initially just needs to fit the
    /// stdlib. After that, all allocation failures throw JS exceptions.
    pub fn new(
        memory: []u8,
        stdlib: *const c.JSSTDLibraryDef,
    ) Allocator.Error!*Context {
        return @ptrCast(c.JS_NewContext(
            memory.ptr,
            memory.len,
            stdlib,
        ) orelse return error.OutOfMemory);
    }

    /// Create a new context using the test stdlib.
    ///
    /// Only available in tests.
    pub fn newTest(memory: []u8) Allocator.Error!*Context {
        comptime assert(@import("builtin").is_test);
        return try new(memory, &test_js_stdlib);
    }

    /// C: JS_FreeContext
    pub fn free(self: *Context) void {
        c.JS_FreeContext(@ptrCast(self));
    }

    /// Set opaque user data on the context.
    ///
    /// This data is passed to callbacks like the interrupt handler.
    ///
    /// C: JS_SetContextOpaque
    pub fn setOpaque(self: *Context, data: ?*anyopaque) void {
        c.JS_SetContextOpaque(@ptrCast(self), data);
    }

    /// Set an interrupt handler that is called periodically during JS execution.
    ///
    /// The handler receives the opaque pointer set via `setOpaque`.
    /// Return non-zero from the handler to interrupt execution.
    ///
    /// C: JS_SetInterruptHandler
    pub fn setInterruptHandler(self: *Context, handler: c.JSInterruptHandler) void {
        c.JS_SetInterruptHandler(@ptrCast(self), handler);
    }

    /// Set the random seed for Math.random().
    ///
    /// Useful for deterministic tests and reproducible bytecode.
    ///
    /// C: JS_SetRandomSeed
    pub fn setRandomSeed(self: *Context, seed: u64) void {
        c.JS_SetRandomSeed(@ptrCast(self), seed);
    }

    /// Set a custom log function for debug output.
    ///
    /// The write function receives the opaque pointer set via `setOpaque`.
    ///
    /// C: JS_SetLogFunc
    pub fn setLogFunc(self: *Context, write_func: c.JSWriteFunc) void {
        c.JS_SetLogFunc(@ptrCast(self), write_func);
    }

    /// Dump memory usage information.
    ///
    /// If is_long is true, displays detailed information.
    ///
    /// C: JS_DumpMemory
    pub fn dumpMemory(self: *Context, is_long: bool) void {
        c.JS_DumpMemory(@ptrCast(self), @intFromBool(is_long));
    }
};

test {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.new(
        &buf,
        &test_js_stdlib,
    );
    ctx.free();
}
