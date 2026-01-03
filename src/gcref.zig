const c = @import("mquickjs_c");
const Context = @import("context.zig").Context;
const Value = @import("value.zig").Value;

/// GCRef provides safe references to JS values across GC boundaries.
///
/// MQuickJS uses a tracing, compacting garbage collector where object
/// addresses can move during any JS allocation. GCRef maintains a stable
/// pointer to a JSValue that the GC updates when objects move.
///
/// Use the stack-based push/pop API for LIFO-ordered references (faster),
/// or the list-based add/delete API for arbitrary-order removal (slower).
///
/// C: JSGCRef
pub const GCRef = extern struct {
    val: c.JSValue,
    prev: ?*GCRef,

    /// Initial GCRef
    pub const empty: GCRef = undefined;

    /// Push this reference onto the GC reference stack.
    ///
    /// Returns a pointer to the value that remains valid across GC cycles.
    /// Must be paired with a corresponding `pop` call in LIFO order.
    ///
    /// C: JS_PushGCRef
    pub fn push(self: *GCRef, ctx: *Context) *Value {
        return @ptrCast(c.JS_PushGCRef(@ptrCast(ctx), @ptrCast(self)));
    }

    /// Pop this reference from the GC reference stack.
    ///
    /// Returns the current value. Must be called in reverse order of push.
    ///
    /// C: JS_PopGCRef
    pub fn pop(self: *GCRef, ctx: *Context) Value {
        return .initC(c.JS_PopGCRef(@ptrCast(ctx), @ptrCast(self)));
    }

    /// Add this reference to the GC reference list.
    ///
    /// Returns a pointer to the value that remains valid across GC cycles.
    /// Unlike push/pop, references can be deleted in any order.
    /// This is slower than the stack-based API.
    ///
    /// C: JS_AddGCRef
    pub fn add(self: *GCRef, ctx: *Context) *Value {
        return @ptrCast(c.JS_AddGCRef(@ptrCast(ctx), @ptrCast(self)));
    }

    /// Delete this reference from the GC reference list.
    ///
    /// Unlike pop, references can be deleted in any order.
    ///
    /// C: JS_DeleteGCRef
    pub fn delete(self: *GCRef, ctx: *Context) void {
        c.JS_DeleteGCRef(@ptrCast(ctx), @ptrCast(self));
    }

    /// Get the current value.
    pub fn value(self: *const GCRef) Value {
        return .initC(self.val);
    }
};

test "GCRef stack push/pop" {
    const std = @import("std");

    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    var ref1: GCRef = .empty;
    var ref2: GCRef = .empty;

    const ptr1 = ref1.push(ctx);
    const ptr2 = ref2.push(ctx);

    ptr1.* = Value.newInt32(ctx, 42);
    ptr2.* = Value.newInt32(ctx, 100);

    try std.testing.expectEqual(@as(i32, 42), ptr1.toInt32(ctx));
    try std.testing.expectEqual(@as(i32, 100), ptr2.toInt32(ctx));

    const val2 = ref2.pop(ctx);
    const val1 = ref1.pop(ctx);

    try std.testing.expectEqual(@as(i32, 100), val2.toInt32(ctx));
    try std.testing.expectEqual(@as(i32, 42), val1.toInt32(ctx));
}

test "GCRef list add/delete" {
    const std = @import("std");

    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    var ref1: GCRef = .empty;
    var ref2: GCRef = .empty;

    const ptr1 = ref1.add(ctx);
    const ptr2 = ref2.add(ctx);

    ptr1.* = Value.newInt32(ctx, 42);
    ptr2.* = Value.newInt32(ctx, 100);

    try std.testing.expectEqual(@as(i32, 42), ptr1.toInt32(ctx));
    try std.testing.expectEqual(@as(i32, 100), ptr2.toInt32(ctx));

    ref1.delete(ctx);
    try std.testing.expectEqual(@as(i32, 100), ptr2.toInt32(ctx));

    ref2.delete(ctx);
}

test "GCRef with objects survives allocations" {
    const std = @import("std");

    var buf: [1024 * 10]u8 align(8) = undefined;
    const ctx = try Context.newTest(&buf);
    defer ctx.free();

    var ref: GCRef = .empty;
    const ptr = ref.push(ctx);

    ptr.* = Value.newObject(ctx);
    _ = ptr.setPropertyStr(ctx, "x", Value.newInt32(ctx, 42));

    _ = Value.newObject(ctx);
    _ = Value.newObject(ctx);
    _ = Value.newObject(ctx);

    const x = ptr.getPropertyStr(ctx, "x");
    try std.testing.expectEqual(@as(i32, 42), x.toInt32(ctx));

    _ = ref.pop(ctx);
}
