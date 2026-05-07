const builtin = @import("builtin");
const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");


pub const is_macos = builtin.os.tag == .macos;
pub const is_windows = builtin.os.tag == .windows;
pub const is_debug = builtin.mode == .Debug;
pub const is_safe_mode = builtin.mode == .Debug or builtin.mode == .ReleaseSafe;


var debug_alloc: if (is_safe_mode) std.heap.DebugAllocator(.{}) else void = if (is_safe_mode) .init else undefined;
pub const allocator: std.mem.Allocator = if (is_safe_mode) debug_alloc.allocator() else std.heap.c_allocator;

pub var io: std.Io = undefined;

pub var cwd: std.Io.Dir = undefined;

var stdout_buff: [512]u8 = undefined;
var stdout_handle: std.Io.File = undefined;
pub var stdout: std.Io.File.Writer = undefined;

pub fn init(in_io: std.Io) !void {
    io = in_io;

    cwd = .cwd();

    stdout_handle = .stdout();
    stdout = stdout_handle.writer(io, &stdout_buff);
}

pub fn deinit() void {
    if (is_safe_mode) {
        _ = debug_alloc.deinit();
    }
}
