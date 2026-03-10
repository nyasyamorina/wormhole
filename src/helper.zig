const builtin = @import("builtin");
const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");


pub const is_macos = builtin.os.tag == .macos;
pub const is_windows = builtin.os.tag == .windows;
pub const is_debug = builtin.mode == .Debug;
pub const is_safe_mode = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;


pub fn logger(comptime level: std.log.Level, comptime scope: @Type(.enum_literal), comptime format: []const u8, args: anytype) void {
    const scope_name = switch (scope) {
        .default => "",
        else => "(" ++ @tagName(scope) ++ ")",
    };
    const log_format = scope_name ++ " [" ++ comptime level.asText() ++ "]: " ++ format ++ "\n";
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    var stderr = std.fs.File.stderr().writer(&.{});
    nosuspend stderr.interface.print(log_format, args) catch {};
}


var debug_alloc: if (is_safe_mode) std.heap.DebugAllocator(.{}) else void = if (is_safe_mode) .init else undefined;
pub const allocator: std.mem.Allocator = if (is_safe_mode) debug_alloc.allocator() else std.heap.c_allocator;

pub const cwd = std.fs.cwd();

pub fn init() !void {
}

pub fn deinit() void {
    if (is_safe_mode) {
        _ = debug_alloc.deinit();
    }
}
