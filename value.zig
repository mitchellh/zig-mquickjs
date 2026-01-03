const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const c = @import("mquickjs_c");
const Context = @import("context.zig").Context;

/// C: JSValue
pub const Value = enum(usize) {
    _,

    /// Special values
    pub const @"null": Value = .initC(c.JS_NULL);
    pub const @"undefined": Value = .initC(c.JS_UNDEFINED);
    pub const @"false": Value = .initC(c.JS_FALSE);
    pub const @"true": Value = .initC(c.JS_TRUE);
    pub const exception: Value = .initC(c.JS_EXCEPTION);

    // Type predicate constants (from mquickjs.h)
    const JS_TAG_INT: c.JSWord = 0;
    const JS_TAG_PTR: c.JSWord = 1;

    /// Initialize a value from a Zig type. If the value is already a JS
    /// Value then it is returned directly. Otherwise, this function
    /// will attempt to convert the value to a JS Value. If it fails,
    /// an exception Value is returned.
    pub fn init(ctx: *Context, val: anytype) Value {
        return switch (@TypeOf(val)) {
            Value => val,
            bool => .newBool(val),
            void => .null,

            else => |T| switch (@typeInfo(T)) {
                .null => .null,
                .optional => if (val) |v| .init(ctx, v) else .null,

                .int => |info| if (info.bits <= 32) switch (info.signedness) {
                    .signed => .newInt32(ctx, @intCast(val)),
                    .unsigned => .newUint32(ctx, @intCast(val)),
                } else if (info.bits <= 63 or
                    (val >= std.math.minInt(i63) and
                        val <= std.math.maxInt(i63)))
                    .newInt64(ctx, @intCast(val))
                else if (info.bits == 64)
                    .newFloat64(ctx, @floatFromInt(val))
                else
                    .initError(ctx),

                .comptime_int => .newInt64(ctx, val),

                .float => |info| if (info.bits <= 64)
                    .newFloat64(ctx, @floatCast(val))
                else
                    .initError(ctx),
                .comptime_float => .newFloat64(ctx, val),

                .pointer => |ptr| switch (ptr.size) {
                    .slice => if (ptr.child == u8)
                        .newStringLen(ctx, val)
                    else
                        .initError(ctx),

                    .one => if (@typeInfo(ptr.child) == .array and
                        @typeInfo(ptr.child).array.child == u8)
                        .newStringLen(ctx, val)
                    else
                        .initError(ctx),

                    else => .initError(ctx),
                },

                else => .initError(ctx),
            },
        };
    }

    fn initError(ctx: *Context) Value {
        const str: Value = .newStringLen(ctx, "failed to convert to JS Value");
        return .throw(ctx, str);
    }

    /// Initialize a Value from a C JSValue. This is free.
    pub inline fn initC(val: c.JSValue) Value {
        return @enumFromInt(val);
    }

    /// Create a new integer value from a 32-bit signed integer.
    /// C: JS_NewInt32
    pub fn newInt32(ctx: *Context, val: i32) Value {
        return .initC(c.JS_NewInt32(@ptrCast(ctx), val));
    }

    /// Create a new integer value from a 32-bit unsigned integer.
    /// C: JS_NewUint32
    pub fn newUint32(ctx: *Context, val: u32) Value {
        return .initC(c.JS_NewUint32(@ptrCast(ctx), val));
    }

    /// Create a new integer value from a 64-bit signed integer.
    /// C: JS_NewInt64
    pub fn newInt64(ctx: *Context, val: i64) Value {
        return .initC(c.JS_NewInt64(@ptrCast(ctx), val));
    }

    /// Create a new floating-point value from a 64-bit float.
    /// C: JS_NewFloat64
    pub fn newFloat64(ctx: *Context, val: f64) Value {
        return .initC(c.JS_NewFloat64(@ptrCast(ctx), val));
    }

    /// Create a new boolean value.
    /// C: JS_NewBool (implemented inline as the C version is a macro)
    pub fn newBool(val: bool) Value {
        // JS_NewBool is a C macro: JS_VALUE_MAKE_SPECIAL(JS_TAG_BOOL, (val != 0))
        // JS_TAG_BOOL = 3, JS_TAG_SPECIAL_BITS = 5
        const JS_TAG_BOOL: c.JSValue = 3;
        const JS_TAG_SPECIAL_BITS: u5 = 5;
        return @enumFromInt(JS_TAG_BOOL | (@as(c.JSValue, @intFromBool(val)) << JS_TAG_SPECIAL_BITS));
    }

    /// Create a new empty object.
    /// C: JS_NewObject
    pub fn newObject(ctx: *Context) Value {
        return .initC(c.JS_NewObject(@ptrCast(ctx)));
    }

    /// Create a new array with the specified initial length.
    /// C: JS_NewArray
    pub fn newArray(ctx: *Context, initial_len: c_int) Value {
        return .initC(c.JS_NewArray(@ptrCast(ctx), initial_len));
    }

    /// Create a new object with a user-defined class ID.
    ///
    /// The class_id must be a valid user class (>= JS_CLASS_USER) that was
    /// defined in the stdlib. This is used for host integrations that need
    /// opaque objects with specific class types.
    ///
    /// C: JS_NewObjectClassUser
    pub fn newObjectClassUser(ctx: *Context, class_id: c_int) Value {
        return .initC(c.JS_NewObjectClassUser(@ptrCast(ctx), class_id));
    }

    /// Create a C function with an object parameter (closure).
    ///
    /// The func_idx indexes into the c_function_table in JSSTDLibraryDef.
    /// The params value is a closure/parameter object for that C function.
    ///
    /// C: JS_NewCFunctionParams
    pub fn newCFunctionParams(ctx: *Context, func_idx: c_int, params: Value) Value {
        return .initC(c.JS_NewCFunctionParams(@ptrCast(ctx), func_idx, params.cval()));
    }

    /// Create a new string value from a null-terminated string.
    /// C: JS_NewString
    pub fn newString(ctx: *Context, s: [:0]const u8) Value {
        return .initC(c.JS_NewString(@ptrCast(ctx), s.ptr));
    }

    /// Create a new string value from a string slice with explicit length.
    /// C: JS_NewStringLen
    pub fn newStringLen(ctx: *Context, s: []const u8) Value {
        return .initC(c.JS_NewStringLen(@ptrCast(ctx), s.ptr, s.len));
    }

    // -----------------------------------------------------------------------
    // Type Predicates
    // -----------------------------------------------------------------------

    /// Check if value is null.
    /// C: JS_IsNull
    pub fn isNull(self: Value) bool {
        return c.JS_IsNull(self.cval()) != 0;
    }

    /// Check if value is undefined.
    /// C: JS_IsUndefined
    pub fn isUndefined(self: Value) bool {
        return c.JS_IsUndefined(self.cval()) != 0;
    }

    /// Check if value is a boolean.
    /// C: JS_IsBool
    pub fn isBool(self: Value) bool {
        return c.JS_IsBool(self.cval()) != 0;
    }

    /// Check if value is an integer (uses tag bits, no context required).
    pub fn isInt(self: Value) bool {
        return (self.cval() & 1) == JS_TAG_INT;
    }

    /// Check if value is a pointer to an object (uses tag bits, no context required).
    pub fn isPtr(self: Value) bool {
        return (self.cval() & (@as(c.JSWord, @sizeOf(c.JSWord)) - 1)) == JS_TAG_PTR;
    }

    /// Check if value is a number (requires context).
    /// C: JS_IsNumber
    pub fn isNumber(self: Value, ctx: *Context) bool {
        return c.JS_IsNumber(@ptrCast(ctx), self.cval()) != 0;
    }

    /// Check if value is a string (requires context).
    /// C: JS_IsString
    pub fn isString(self: Value, ctx: *Context) bool {
        return c.JS_IsString(@ptrCast(ctx), self.cval()) != 0;
    }

    /// Check if value is an exception.
    /// C: JS_IsException
    pub fn isException(self: Value) bool {
        return c.JS_IsException(self.cval()) != 0;
    }

    /// Check if value is an error object (requires context).
    /// C: JS_IsError
    pub fn isError(self: Value, ctx: *Context) bool {
        return c.JS_IsError(@ptrCast(ctx), self.cval()) != 0;
    }

    /// Check if value is a function (requires context).
    /// C: JS_IsFunction
    pub fn isFunction(self: Value, ctx: *Context) bool {
        return c.JS_IsFunction(@ptrCast(ctx), self.cval()) != 0;
    }

    // -----------------------------------------------------------------------
    // Conversions
    // -----------------------------------------------------------------------

    /// Get the underlying C JSValue representation.
    pub inline fn cval(self: Value) c.JSValue {
        return @intFromEnum(self);
    }

    /// Convert value to a 32-bit signed integer.
    /// C: JS_ToInt32
    pub fn toInt32(self: Value, ctx: *Context) i32 {
        var out: i32 = 0;
        _ = c.JS_ToInt32(@ptrCast(ctx), &out, self.cval());
        return out;
    }

    /// Convert value to a 32-bit unsigned integer.
    /// C: JS_ToUint32
    pub fn toUint32(self: Value, ctx: *Context) u32 {
        var out: u32 = 0;
        _ = c.JS_ToUint32(@ptrCast(ctx), &out, self.cval());
        return out;
    }

    /// Convert value to a 32-bit signed integer with saturation.
    /// C: JS_ToInt32Sat
    pub fn toInt32Sat(self: Value, ctx: *Context) i32 {
        var out: i32 = 0;
        _ = c.JS_ToInt32Sat(@ptrCast(ctx), &out, self.cval());
        return out;
    }

    /// Convert value to a 64-bit floating-point number.
    /// C: JS_ToNumber
    pub fn toNumber(self: Value, ctx: *Context) f64 {
        var out: f64 = 0;
        _ = c.JS_ToNumber(@ptrCast(ctx), &out, self.cval());
        return out;
    }

    /// Buffer used for short strings.
    pub const StringBuf = c.JSCStringBuf;

    /// Convert value to a JS string.
    /// C: JS_ToString
    pub fn toString(self: Value, ctx: *Context) Value {
        return .initC(c.JS_ToString(@ptrCast(ctx), self.cval()));
    }

    /// Convert value to a Zig string slice.
    pub fn toZigString(self: Value, ctx: *Context, buf: *StringBuf) ?[:0]const u8 {
        var len: usize = 0;
        const ptr = self.toCStringLen(
            ctx,
            &len,
            buf,
        ) orelse return null;
        return ptr[0..len :0];
    }

    /// Convert value to a C string. The returned pointer is valid until the next GC.
    /// C: JS_ToCString
    pub fn toCString(self: Value, ctx: *Context, buf: *StringBuf) ?[*:0]const u8 {
        return c.JS_ToCString(@ptrCast(ctx), self.cval(), buf);
    }

    /// Convert value to a C string with length. The returned pointer is valid until the next GC.
    /// C: JS_ToCStringLen
    pub fn toCStringLen(self: Value, ctx: *Context, len_out: *usize, buf: *StringBuf) ?[*:0]const u8 {
        var clen: usize = 0;
        const ptr = c.JS_ToCStringLen(@ptrCast(ctx), &clen, self.cval(), buf);
        len_out.* = clen;
        return ptr;
    }

    // -----------------------------------------------------------------------
    // Debug / Logging
    // -----------------------------------------------------------------------

    /// Print this value using the context's log function.
    /// C: JS_PrintValue
    pub fn print(self: Value, ctx: *Context) void {
        c.JS_PrintValue(@ptrCast(ctx), self.cval());
    }

    /// Print this value with flags using the context's log function.
    /// C: JS_PrintValueF
    pub fn printWithFlags(self: Value, ctx: *Context, flags: DumpFlags) void {
        c.JS_PrintValueF(@ptrCast(ctx), self.cval(), @bitCast(flags));
    }

    /// Dump this value with a prefix string using the context's log function.
    /// C: JS_DumpValue
    pub fn dump(self: Value, ctx: *Context, prefix: [*:0]const u8) void {
        c.JS_DumpValue(@ptrCast(ctx), prefix, self.cval());
    }

    /// Dump this value with a prefix string and flags using the context's log function.
    /// C: JS_DumpValueF
    pub fn dumpWithFlags(self: Value, ctx: *Context, prefix: [*:0]const u8, flags: DumpFlags) void {
        c.JS_DumpValueF(@ptrCast(ctx), prefix, self.cval(), @bitCast(flags));
    }

    // -----------------------------------------------------------------------
    // Property Access
    // -----------------------------------------------------------------------

    /// Get a property by name.
    /// C: JS_GetPropertyStr
    pub fn getPropertyStr(self: Value, ctx: *Context, name: [:0]const u8) Value {
        return .initC(c.JS_GetPropertyStr(@ptrCast(ctx), self.cval(), name.ptr));
    }

    /// Get a property by index.
    /// C: JS_GetPropertyUint32
    pub fn getPropertyIndex(self: Value, ctx: *Context, index: u32) Value {
        return .initC(c.JS_GetPropertyUint32(@ptrCast(ctx), self.cval(), index));
    }

    /// Set a property by name.
    /// C: JS_SetPropertyStr
    pub fn setPropertyStr(self: Value, ctx: *Context, name: [:0]const u8, val: Value) Value {
        return .initC(c.JS_SetPropertyStr(@ptrCast(ctx), self.cval(), name.ptr, val.cval()));
    }

    /// Set a property by index.
    /// C: JS_SetPropertyUint32
    pub fn setPropertyIndex(self: Value, ctx: *Context, index: u32, val: Value) Value {
        return .initC(c.JS_SetPropertyUint32(@ptrCast(ctx), self.cval(), index, val.cval()));
    }

    // -----------------------------------------------------------------------
    // Opaque Data
    // -----------------------------------------------------------------------

    /// Get the class ID of an object.
    /// C: JS_GetClassID
    pub fn getClassId(self: Value, ctx: *Context) c_int {
        return c.JS_GetClassID(@ptrCast(ctx), self.cval());
    }

    /// Set opaque data on an object.
    /// C: JS_SetOpaque
    pub fn setOpaque(self: Value, ctx: *Context, data: ?*anyopaque) void {
        c.JS_SetOpaque(@ptrCast(ctx), self.cval(), data);
    }

    /// Get opaque data from an object.
    /// C: JS_GetOpaque
    pub fn getOpaque(self: Value, ctx: *Context) ?*anyopaque {
        return c.JS_GetOpaque(@ptrCast(ctx), self.cval());
    }

    // -----------------------------------------------------------------------
    // Evaluation / Execution
    // -----------------------------------------------------------------------

    /// Parse JavaScript source code into a compiled function.
    ///
    /// C: JS_Parse
    pub fn parse(
        ctx: *Context,
        input: [:0]const u8,
        filename: [:0]const u8,
        flags: EvalFlags,
    ) Value {
        return .initC(c.JS_Parse(
            @ptrCast(ctx),
            input.ptr,
            input.len,
            filename.ptr,
            @bitCast(flags),
        ));
    }

    /// Execute a compiled function.
    ///
    /// C: JS_Run
    pub fn run(self: Value, ctx: *Context) Value {
        return .initC(c.JS_Run(@ptrCast(ctx), self.cval()));
    }

    /// Evaluate JavaScript source code directly.
    /// C: JS_Eval
    pub fn eval(
        ctx: *Context,
        input: [:0]const u8,
        filename: [:0]const u8,
        flags: EvalFlags,
    ) Value {
        return .initC(c.JS_Eval(
            @ptrCast(ctx),
            input.ptr,
            input.len,
            filename.ptr,
            @bitCast(flags),
        ));
    }

    /// Load precompiled bytecode.
    /// C: JS_LoadBytecode
    pub fn loadBytecode(ctx: *Context, buf: []const u8) Value {
        return .initC(c.JS_LoadBytecode(@ptrCast(ctx), buf.ptr));
    }

    // -----------------------------------------------------------------------
    // Bytecode Compilation / Relocation
    // -----------------------------------------------------------------------

    /// Bytecode header structure.
    /// C: JSBytecodeHeader
    pub const BytecodeHeader = c.JSBytecodeHeader;

    /// Bytecode header for 32-bit targets (only available on 64-bit hosts).
    /// C: JSBytecodeHeader32
    pub const BytecodeHeader32 = if (@sizeOf(usize) == 8) c.JSBytecodeHeader32 else void;

    /// Check if a buffer contains valid bytecode.
    /// C: JS_IsBytecode
    pub fn isBytecode(buf: []const u8) bool {
        return c.JS_IsBytecode(buf.ptr, buf.len) != 0;
    }

    /// Prepare bytecode from evaluated code for serialization.
    ///
    /// This is used on the host when compiling to a binary file.
    /// After calling, data_buf and data_len will point to the bytecode data.
    ///
    /// C: JS_PrepareBytecode
    pub fn prepareBytecode(
        ctx: *Context,
        header: *BytecodeHeader,
        data_buf: *[*]const u8,
        data_len: *u32,
        eval_code: Value,
    ) void {
        c.JS_PrepareBytecode(
            @ptrCast(ctx),
            header,
            @ptrCast(data_buf),
            data_len,
            eval_code.cval(),
        );
    }

    /// Relocate bytecode so it can be executed.
    ///
    /// Call this after loading bytecode into memory but before executing it.
    /// Returns 0 on success, non-zero on error.
    ///
    /// C: JS_RelocateBytecode
    pub fn relocateBytecode(ctx: *Context, buf: []u8) c_int {
        return c.JS_RelocateBytecode(@ptrCast(ctx), buf.ptr, @intCast(buf.len));
    }

    /// Relocate bytecode with explicit base address and atom update control.
    ///
    /// This is used on the host when compiling to a binary file.
    /// Returns 0 on success, non-zero on error.
    ///
    /// C: JS_RelocateBytecode2
    pub fn relocateBytecode2(
        ctx: *Context,
        header: *BytecodeHeader,
        buf: []u8,
        new_base_addr: usize,
        update_atoms: bool,
    ) c_int {
        return c.JS_RelocateBytecode2(
            @ptrCast(ctx),
            header,
            buf.ptr,
            @intCast(buf.len),
            new_base_addr,
            @intFromBool(update_atoms),
        );
    }

    /// Prepare bytecode for 32-bit targets from a 64-bit host.
    ///
    /// Only available when compiling on a 64-bit host.
    /// Returns 0 on success, non-zero on error.
    ///
    /// C: JS_PrepareBytecode64to32
    pub fn prepareBytecode64to32(
        ctx: *Context,
        header: *BytecodeHeader32,
        data_buf: *[*]const u8,
        data_len: *u32,
        eval_code: Value,
    ) c_int {
        if (@sizeOf(usize) != 8) {
            @compileError("prepareBytecode64to32 is only available on 64-bit hosts");
        }
        return c.JS_PrepareBytecode64to32(
            @ptrCast(ctx),
            header,
            @ptrCast(data_buf),
            data_len,
            eval_code.cval(),
        );
    }

    // -----------------------------------------------------------------------
    // Function Calls
    //
    // To call a JS function:
    //   1. Push arguments in reverse order (last arg first)
    //   2. Push the function
    //   3. Push the `this` value
    //   4. Call with argc
    //
    // Example:
    //   Value.pushArg(ctx, arg1);  // second param
    //   Value.pushArg(ctx, arg0);  // first param
    //   Value.pushArg(ctx, func);
    //   Value.pushArg(ctx, this_val);
    //   const result = Value.call(ctx, 2);
    // -----------------------------------------------------------------------

    /// Invoke the current value as a function with the given arguments.
    /// This is sugar over calling `pushArg` and `call` directly and lets
    /// you pass some direct Zig types more easily.
    ///
    /// If converting any args to a Value fails, this will return the
    /// exception from that call and the function will not be invoked.
    pub fn invoke(self: Value, ctx: *Context, this: anytype, args: anytype) Value {
        assert(self.isFunction(ctx));

        // Build our arguments.
        const argsInfo = @typeInfo(@TypeOf(args)).@"struct";
        comptime assert(argsInfo.is_tuple);
        var js_args: [argsInfo.fields.len]Value = undefined;
        inline for (argsInfo.fields, 0..) |field, i| {
            js_args[i] = .init(ctx, @field(args, field.name));
            if (js_args[i].isException()) return js_args[i];
        }

        // Convert our this value
        const js_this: Value = .init(ctx, this);
        if (js_this.isException()) return js_this;

        // Push args in reverse order, then the function, then this.
        inline for (0..argsInfo.fields.len) |i| pushArg(
            ctx,
            js_args[argsInfo.fields.len - 1 - i],
        );
        pushArg(ctx, self);
        pushArg(ctx, js_this);
        return call(ctx, argsInfo.fields.len);
    }

    /// Push an argument for a JS function call. See "Function Calls" section
    /// above for the required push order.
    /// C: JS_PushArg
    pub fn pushArg(ctx: *Context, arg: Value) void {
        c.JS_PushArg(@ptrCast(ctx), arg.cval());
    }

    /// Call a JS function after pushing args, func, and this via `pushArg`.
    /// The `call_flags` parameter is the argument count (argc).
    /// C: JS_Call
    pub fn call(ctx: *Context, call_flags: c_int) Value {
        return .initC(c.JS_Call(@ptrCast(ctx), call_flags));
    }

    // -----------------------------------------------------------------------
    // Exceptions
    // -----------------------------------------------------------------------

    /// Throw an exception.
    /// C: JS_Throw
    pub fn throw(ctx: *Context, obj: Value) Value {
        return .initC(c.JS_Throw(@ptrCast(ctx), obj.cval()));
    }

    /// Get the current pending exception.
    /// C: JS_GetException
    pub fn getException(ctx: *Context) Value {
        return .initC(c.JS_GetException(@ptrCast(ctx)));
    }

    /// Throw an out of memory error.
    /// C: JS_ThrowOutOfMemory
    pub fn throwOutOfMemory(ctx: *Context) Value {
        return .initC(c.JS_ThrowOutOfMemory(@ptrCast(ctx)));
    }

    /// Throw a JavaScript error of the specified class with a message.
    ///
    /// The error_class should be one of the JS_CLASS_*_ERROR values from
    /// JSObjectClassEnum (e.g., JS_CLASS_TYPE_ERROR, JS_CLASS_RANGE_ERROR).
    ///
    /// Note: This wrapper does not support printf-style format arguments.
    /// Pre-format the message string before calling.
    ///
    /// C: JS_ThrowError
    pub fn throwError(ctx: *Context, error_class: c.JSObjectClassEnum, msg: [:0]const u8) Value {
        return .initC(c.JS_ThrowError(@ptrCast(ctx), error_class, msg.ptr));
    }

    // -----------------------------------------------------------------------
    // Global State / Runtime
    // -----------------------------------------------------------------------

    /// Get the global object.
    /// C: JS_GetGlobalObject
    pub fn globalObject(ctx: *Context) Value {
        return .initC(c.JS_GetGlobalObject(@ptrCast(ctx)));
    }

    /// Check stack space.
    /// C: JS_StackCheck
    pub fn stackCheck(ctx: *Context, extra: u32) c_int {
        return c.JS_StackCheck(@ptrCast(ctx), extra);
    }

    /// Trigger garbage collection.
    /// C: JS_GC
    pub fn gc(ctx: *Context) void {
        c.JS_GC(@ptrCast(ctx));
    }
};

pub const EvalFlags = packed struct(c_int) {
    /// Return the last value instead of undefined (slower code).
    retval: bool = false,
    /// Implicitly defined global variables in assignments.
    repl: bool = false,
    /// Strip column number debug information (save memory).
    strip_col: bool = false,
    /// Parse as JSON and return the object.
    json: bool = false,
    /// Internal use.
    regexp: bool = false,
    _padding: u27 = 0,

    test "bitcast" {
        const testing = std.testing;

        const cval: c_int = c.JS_EVAL_RETVAL | c.JS_EVAL_JSON;
        const flags = @as(EvalFlags, @bitCast(cval));
        try testing.expect(flags.retval);
        try testing.expect(!flags.repl);
        try testing.expect(!flags.strip_col);
        try testing.expect(flags.json);
        try testing.expect(!flags.regexp);
    }

    test "all flags individually" {
        const testing = std.testing;

        try testing.expectEqual(
            @as(c_int, 0),
            @as(c_int, @bitCast(EvalFlags{})),
        );

        inline for ([_]struct { c_int, []const u8 }{
            .{ c.JS_EVAL_RETVAL, "retval" },
            .{ c.JS_EVAL_REPL, "repl" },
            .{ c.JS_EVAL_STRIP_COL, "strip_col" },
            .{ c.JS_EVAL_JSON, "json" },
            .{ c.JS_EVAL_REGEXP, "regexp" },
        }) |pair| {
            var flags: EvalFlags = .{};
            @field(flags, pair[1]) = true;
            try testing.expectEqual(pair[0], @as(c_int, @bitCast(flags)));
        }
    }
};

/// Flags for Value.printWithFlags and Value.dumpWithFlags.
pub const DumpFlags = packed struct(c_int) {
    /// Display object/array content.
    long: bool = false,
    /// Strings: no quote for identifiers.
    no_quote: bool = false,
    /// For low level dumps: don't dump special properties and use specific
    /// quotes to distinguish string chars, unique strings and normal strings.
    raw: bool = false,
    _padding: u29 = 0,

    test "bitcast" {
        const testing = std.testing;

        const cval: c_int = c.JS_DUMP_LONG | c.JS_DUMP_RAW;
        const flags = @as(DumpFlags, @bitCast(cval));
        try testing.expect(flags.long);
        try testing.expect(!flags.no_quote);
        try testing.expect(flags.raw);
    }

    test "all flags individually" {
        const testing = std.testing;

        try testing.expectEqual(
            @as(c_int, 0),
            @as(c_int, @bitCast(DumpFlags{})),
        );

        inline for ([_]struct { c_int, []const u8 }{
            .{ c.JS_DUMP_LONG, "long" },
            .{ c.JS_DUMP_NOQUOTE, "no_quote" },
            .{ c.JS_DUMP_RAW, "raw" },
        }) |pair| {
            var flags: DumpFlags = .{};
            @field(flags, pair[1]) = true;
            try testing.expectEqual(pair[0], @as(c_int, @bitCast(flags)));
        }
    }
};

test {
    _ = DumpFlags;
    _ = EvalFlags;
}

test "parse and run simple math" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const func = Value.parse(
        ctx,
        "2 + 3",
        "<test>",
        .{ .retval = true },
    );
    var result = func.run(ctx);
    try std.testing.expectEqual(@as(i32, 5), result.toInt32(ctx));
}

test "parse and run multiplication" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const func = Value.parse(
        ctx,
        "7 * 6",
        "<test>",
        .{ .retval = true },
    );
    var result = func.run(ctx);
    try std.testing.expectEqual(@as(i32, 42), result.toInt32(ctx));
}

test "constants" {
    try std.testing.expect(Value.null.isNull());
    try std.testing.expect(Value.undefined.isUndefined());
    try std.testing.expect(Value.false.isBool());
    try std.testing.expect(Value.true.isBool());
    try std.testing.expect(Value.exception.isException());
}

test "newInt32 roundtrip" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const val = Value.newInt32(ctx, 42);
    try std.testing.expectEqual(@as(i32, 42), val.toInt32(ctx));
}

test "newUint32 roundtrip" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const val = Value.newUint32(ctx, 123);
    try std.testing.expectEqual(@as(i32, 123), val.toInt32(ctx));
}

test "newInt64 roundtrip" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const val = Value.newInt64(ctx, 999);
    try std.testing.expectEqual(@as(i32, 999), val.toInt32(ctx));
}

test "newFloat64" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const val = Value.newFloat64(ctx, 3.14);
    try std.testing.expect(val.isNumber(ctx));
}

test "newBool" {
    const true_val = Value.newBool(true);
    const false_val = Value.newBool(false);
    try std.testing.expect(true_val.isBool());
    try std.testing.expect(false_val.isBool());
}

test "newObject" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const obj = Value.newObject(ctx);
    try std.testing.expect(!obj.isNull());
    try std.testing.expect(!obj.isUndefined());
}

test "newArray" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const arr = Value.newArray(ctx, 0);
    try std.testing.expect(!arr.isNull());
    try std.testing.expect(!arr.isUndefined());
}

test "newString" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const str = Value.newString(ctx, "hello");
    try std.testing.expect(!str.isNull());
    try std.testing.expect(!str.isUndefined());
}

test "newStringLen" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const str = Value.newStringLen(ctx, "hello world");
    try std.testing.expect(!str.isNull());
    try std.testing.expect(!str.isUndefined());
}

test "isInt" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const int_val = Value.newInt32(ctx, 42);
    try std.testing.expect(int_val.isInt());

    const float_val = Value.newFloat64(ctx, 3.14);
    try std.testing.expect(!float_val.isInt());
}

test "isPtr" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const obj = Value.newObject(ctx);
    try std.testing.expect(obj.isPtr());

    const int_val = Value.newInt32(ctx, 42);
    try std.testing.expect(!int_val.isPtr());
}

test "isString" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const str = Value.newString(ctx, "hello");
    try std.testing.expect(str.isString(ctx));

    const int_val = Value.newInt32(ctx, 42);
    try std.testing.expect(!int_val.isString(ctx));
}

test "isError" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const obj = Value.newObject(ctx);
    try std.testing.expect(!obj.isError(ctx));
}

test "isFunction" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const obj = Value.newObject(ctx);
    try std.testing.expect(!obj.isFunction(ctx));
}

test "toUint32 roundtrip" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const val = Value.newUint32(ctx, 4294967295);
    try std.testing.expectEqual(@as(u32, 4294967295), val.toUint32(ctx));
}

test "toNumber roundtrip" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const val = Value.newFloat64(ctx, 3.14159);
    try std.testing.expectApproxEqRel(@as(f64, 3.14159), val.toNumber(ctx), 0.0001);
}

test "toString" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const int_val = Value.newInt32(ctx, 42);
    const str_val = int_val.toString(ctx);
    try std.testing.expect(str_val.isString(ctx));
}

test "toCString" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const str = Value.newString(ctx, "hello");
    var cstr_buf: c.JSCStringBuf = undefined;
    const cstr = str.toCString(ctx, &cstr_buf);
    try std.testing.expect(cstr != null);
    try std.testing.expectEqualStrings("hello", std.mem.span(cstr.?));
}

test "getPropertyStr" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const func = Value.parse(
        ctx,
        \\({ "font-size": 42 })
    ,
        "<test>",
        .{ .retval = true },
    );
    const obj = func.run(ctx);
    const val = obj.getPropertyStr(ctx, "font-size");
    try std.testing.expectEqual(@as(i32, 42), val.toInt32(ctx));
}

test "setPropertyStr/getPropertyStr" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const obj = Value.newObject(ctx);
    _ = obj.setPropertyStr(ctx, "foo", Value.newInt32(ctx, 42));
    const val = obj.getPropertyStr(ctx, "foo");
    try std.testing.expectEqual(@as(i32, 42), val.toInt32(ctx));
}

test "setPropertyIndex/getPropertyIndex" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const arr = Value.newArray(ctx, 1);
    _ = arr.setPropertyIndex(ctx, 0, Value.newInt32(ctx, 99));
    const val = arr.getPropertyIndex(ctx, 0);
    try std.testing.expectEqual(@as(i32, 99), val.toInt32(ctx));
}

test "eval" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const result = Value.eval(ctx, "1 + 2", "<test>", .{ .retval = true });
    try std.testing.expectEqual(@as(i32, 3), result.toInt32(ctx));
}

test "globalObject" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const global = Value.globalObject(ctx);
    try std.testing.expect(!global.isNull());
    try std.testing.expect(!global.isUndefined());
}

test "getClassId" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const obj = Value.newObject(ctx);
    const class_id = obj.getClassId(ctx);
    try std.testing.expect(class_id >= 0);
}

test "call function with two params" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const add_fn = Value.eval(ctx,
        \\(function(a, b) { 
        \\  return a + b; 
        \\})
    , "<test>", .{ .retval = true });
    try std.testing.expect(add_fn.isFunction(ctx));

    // Calling convention: push args in reverse order, then func, then this_obj
    Value.pushArg(ctx, Value.newInt32(ctx, 32)); // arg[1] (second param)
    Value.pushArg(ctx, Value.newInt32(ctx, 10)); // arg[0] (first param)
    Value.pushArg(ctx, add_fn);
    Value.pushArg(ctx, Value.null); // this

    const result = Value.call(ctx, 2);
    try std.testing.expect(!result.isException());
    try std.testing.expectEqual(@as(i32, 42), result.toInt32(ctx));
}

test "init with Value passthrough" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const original = Value.newInt32(ctx, 123);
    const result = Value.init(ctx, original);
    try std.testing.expectEqual(original, result);
}

test "init with bool" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const true_val = Value.init(ctx, true);
    const false_val = Value.init(ctx, false);
    try std.testing.expect(true_val.isBool());
    try std.testing.expect(false_val.isBool());
}

test "init with null and void" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const null_val = Value.init(ctx, null);
    try std.testing.expect(null_val.isNull());

    const void_val = Value.init(ctx, {});
    try std.testing.expect(void_val.isNull());
}

test "init with signed integers" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const i8_val = Value.init(ctx, @as(i8, -42));
    try std.testing.expectEqual(@as(i32, -42), i8_val.toInt32(ctx));

    const i16_val = Value.init(ctx, @as(i16, -1000));
    try std.testing.expectEqual(@as(i32, -1000), i16_val.toInt32(ctx));

    const i32_val = Value.init(ctx, @as(i32, -123456));
    try std.testing.expectEqual(@as(i32, -123456), i32_val.toInt32(ctx));

    const i64_val = Value.init(ctx, @as(i64, 9999999999));
    try std.testing.expect(i64_val.isNumber(ctx));
}

test "init with unsigned integers" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const u8_val = Value.init(ctx, @as(u8, 200));
    try std.testing.expectEqual(@as(u32, 200), u8_val.toUint32(ctx));

    const u16_val = Value.init(ctx, @as(u16, 60000));
    try std.testing.expectEqual(@as(u32, 60000), u16_val.toUint32(ctx));

    const u32_val = Value.init(ctx, @as(u32, 4000000000));
    try std.testing.expectEqual(@as(u32, 4000000000), u32_val.toUint32(ctx));
}

test "init with comptime_int" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const val = Value.init(ctx, 42);
    try std.testing.expectEqual(@as(i32, 42), val.toInt32(ctx));
}

test "init with floats" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const f32_val = Value.init(ctx, @as(f32, 3.14));
    try std.testing.expect(f32_val.isNumber(ctx));

    const f64_val = Value.init(ctx, @as(f64, 2.718281828));
    try std.testing.expectApproxEqRel(@as(f64, 2.718281828), f64_val.toNumber(ctx), 0.0001);
}

test "init with comptime_float" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const val = Value.init(ctx, 3.14159);
    try std.testing.expect(val.isNumber(ctx));
    try std.testing.expectApproxEqRel(@as(f64, 3.14159), val.toNumber(ctx), 0.0001);
}

test "init with optional" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const some_val: ?i32 = 42;
    const some_result = Value.init(ctx, some_val);
    try std.testing.expectEqual(@as(i32, 42), some_result.toInt32(ctx));

    const none_val: ?i32 = null;
    const none_result = Value.init(ctx, none_val);
    try std.testing.expect(none_result.isNull());
}

test "init with string slice" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const str: []const u8 = "hello world";
    const val = Value.init(ctx, str);
    try std.testing.expect(val.isString(ctx));
}

test "init with string literal" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const val = Value.init(ctx, "hello");
    try std.testing.expect(val.isString(ctx));
}

test "invoke with no args" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const fn_val = Value.eval(ctx,
        \\(function() { return 42; })
    , "<test>", .{ .retval = true });
    try std.testing.expect(fn_val.isFunction(ctx));

    const result = fn_val.invoke(ctx, Value.null, .{});
    try std.testing.expect(!result.isException());
    try std.testing.expectEqual(@as(i32, 42), result.toInt32(ctx));
}

test "invoke with one arg" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const fn_val = Value.eval(ctx,
        \\(function(x) { return x * 2; })
    , "<test>", .{ .retval = true });
    try std.testing.expect(fn_val.isFunction(ctx));

    const result = fn_val.invoke(ctx, Value.null, .{@as(i32, 21)});
    try std.testing.expect(!result.isException());
    try std.testing.expectEqual(@as(i32, 42), result.toInt32(ctx));
}

test "invoke with multiple args" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const fn_val = Value.eval(ctx,
        \\(function(a, b, c) { return a + b + c; })
    , "<test>", .{ .retval = true });
    try std.testing.expect(fn_val.isFunction(ctx));

    const result = fn_val.invoke(ctx, Value.null, .{
        @as(i32, 10),
        @as(i32, 20),
        @as(i32, 12),
    });
    try std.testing.expect(!result.isException());
    try std.testing.expectEqual(@as(i32, 42), result.toInt32(ctx));
}

test "invoke with this value" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const fn_val = Value.eval(ctx,
        \\(function() { return this.value; })
    , "<test>", .{ .retval = true });
    try std.testing.expect(fn_val.isFunction(ctx));

    const this_obj = Value.newObject(ctx);
    _ = this_obj.setPropertyStr(ctx, "value", Value.newInt32(ctx, 42));

    const result = fn_val.invoke(ctx, this_obj, .{});
    try std.testing.expect(!result.isException());
    try std.testing.expectEqual(@as(i32, 42), result.toInt32(ctx));
}

test "invoke with mixed arg types" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const fn_val = Value.eval(ctx,
        \\(function(a, b) { return a ? b : 0; })
    , "<test>", .{ .retval = true });
    try std.testing.expect(fn_val.isFunction(ctx));

    const result = fn_val.invoke(ctx, Value.null, .{ true, @as(i32, 42) });
    try std.testing.expect(!result.isException());
    try std.testing.expectEqual(@as(i32, 42), result.toInt32(ctx));
}

const TestLogger = struct {
    var buf: std.ArrayList(u8) = .empty;

    pub fn reset() void {
        buf.deinit(std.testing.allocator);
        buf = .empty;
    }

    pub fn output() []const u8 {
        return buf.items;
    }

    pub fn logFunc(
        _: ?*anyopaque,
        data_: ?*const anyopaque,
        len: usize,
    ) callconv(.c) void {
        const data = data_ orelse return;
        const bytes: [*]const u8 = @ptrCast(data);
        buf.appendSlice(std.testing.allocator, bytes[0..len]) catch unreachable;
    }
};

test "setLogFunc and print" {
    TestLogger.reset();
    defer TestLogger.reset();

    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();
    ctx.setLogFunc(TestLogger.logFunc);

    const val = Value.newInt32(ctx, 42);
    val.print(ctx);

    const output = TestLogger.output();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "42") != null);
}

test "printWithFlags" {
    TestLogger.reset();
    defer TestLogger.reset();

    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();
    ctx.setLogFunc(TestLogger.logFunc);

    const obj = Value.newObject(ctx);
    _ = obj.setPropertyStr(ctx, "x", Value.newInt32(ctx, 1));

    obj.printWithFlags(ctx, .{ .long = true });

    const output = TestLogger.output();
    try std.testing.expect(output.len > 0);
}

test "dump with prefix" {
    TestLogger.reset();
    defer TestLogger.reset();

    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();
    ctx.setLogFunc(TestLogger.logFunc);

    const val = Value.newString(ctx, "hello");
    val.dump(ctx, "test: ");

    const output = TestLogger.output();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "test: ") != null);
}

test "dumpWithFlags" {
    TestLogger.reset();
    defer TestLogger.reset();

    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();
    ctx.setLogFunc(TestLogger.logFunc);

    const obj = Value.newObject(ctx);
    _ = obj.setPropertyStr(ctx, "key", Value.newInt32(ctx, 99));

    obj.dumpWithFlags(ctx, "obj: ", .{ .long = true, .no_quote = true });

    const output = TestLogger.output();
    try std.testing.expect(output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, output, "obj: ") != null);
}

test "dumpMemory" {
    TestLogger.reset();
    defer TestLogger.reset();

    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();
    ctx.setLogFunc(TestLogger.logFunc);

    ctx.dumpMemory(false);

    const output = TestLogger.output();
    try std.testing.expect(output.len > 0);
}

test "newObjectClassUser" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const obj = Value.newObjectClassUser(ctx, c.JS_CLASS_USER);
    try std.testing.expect(!obj.isException());
    try std.testing.expect(!obj.isNull());
    try std.testing.expect(!obj.isUndefined());

    const class_id = obj.getClassId(ctx);
    try std.testing.expectEqual(c.JS_CLASS_USER, class_id);
}

test "newObjectClassUser with opaque data" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const obj = Value.newObjectClassUser(ctx, c.JS_CLASS_USER);
    try std.testing.expect(!obj.isException());

    var data: i32 = 42;
    obj.setOpaque(ctx, &data);
    const retrieved = obj.getOpaque(ctx);
    try std.testing.expect(retrieved != null);
    const ptr: *i32 = @ptrCast(@alignCast(retrieved.?));
    try std.testing.expectEqual(@as(i32, 42), ptr.*);
}

test "throwError creates exception" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const result = Value.throwError(ctx, c.JS_CLASS_TYPE_ERROR, "test error message");
    try std.testing.expect(result.isException());

    const exc = Value.getException(ctx);
    try std.testing.expect(exc.isError(ctx));
}

test "throwError with different error classes" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const result = Value.throwError(ctx, c.JS_CLASS_RANGE_ERROR, "out of range");
    try std.testing.expect(result.isException());

    const exc = Value.getException(ctx);
    try std.testing.expect(exc.isError(ctx));
}

test "isBytecode with invalid data" {
    const invalid_data = [_]u8{ 0x00, 0x01, 0x02, 0x03 };
    try std.testing.expect(!Value.isBytecode(&invalid_data));
}

test "isBytecode with wrong magic" {
    var data: [@sizeOf(Value.BytecodeHeader)]u8 = undefined;
    @memset(&data, 0);
    std.mem.writeInt(u16, data[0..2], 0x1234, .little);
    try std.testing.expect(!Value.isBytecode(&data));
}

test "isBytecode with empty buffer" {
    const empty: []const u8 = &.{};
    try std.testing.expect(!Value.isBytecode(empty));
}

test "toZigString" {
    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    const func = Value.parse(
        ctx,
        \\"hello world"
    ,
        "<test>",
        .{ .retval = true },
    );
    const result = func.run(ctx);
    var str_buf: Value.StringBuf = undefined;
    const str = result.toZigString(ctx, &str_buf);
    try std.testing.expect(str != null);
    try std.testing.expectEqualStrings("hello world", str.?);
}
