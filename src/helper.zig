const builtin = @import("builtin");
const std = @import("std");


pub const is_safe_mode = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;


var debug_alloc: if (is_safe_mode) std.heap.DebugAllocator(.{}) else void = undefined;
pub var allocator: std.mem.Allocator = undefined;

pub fn initAllocator() void {
    if (is_safe_mode) {
        debug_alloc = @TypeOf(debug_alloc).init;
        allocator = debug_alloc.allocator();
    } else {
        allocator = std.heap.smp_allocator;
    }
}
pub fn deinitAllocator() if (is_safe_mode) std.heap.Check else void {
    if (is_safe_mode) {
        return debug_alloc.deinit();
    }
}
