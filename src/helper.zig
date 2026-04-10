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

pub var cwd: std.fs.Dir = undefined;

var stdout_buff: [512]u8 = undefined;
var stdout_handle: std.fs.File = undefined;
pub var stdout: std.fs.File.Writer = undefined;

pub const line_break = if (is_windows) "\r\n" else "\n";
pub const clear_line_and_break = "\x1b[K" ++ line_break;

pub fn init() !void {
    cwd = std.fs.cwd();

    stdout_handle = .stdout();
    stdout = stdout_handle.writer(&stdout_buff);
}

pub fn deinit() void {
    if (is_safe_mode) {
        _ = debug_alloc.deinit();
    }
}


pub fn Timer(comptime tags: []const @TypeOf(.enum_literal), comptime smooth: f32) type {
    return struct {
        state: [tags.len]f32,
        timestamps: [tags.len]i128,

        pub const init: @This() = .{
            .state = std.mem.zeroes([tags.len]f32),
            .timestamps = undefined,
        };

        fn tagIndex(comptime tag: @TypeOf(.enum_literal)) usize {
            inline for (tags, 0..) |t, idx| {
                if (t == tag) return idx;
            }
            @compileError("`" ++ @tagName(tag) ++ "` is not an available tag");
        }

        pub fn start(self: *@This(), comptime tag: @TypeOf(.enum_literal)) void {
            const idx = tagIndex(tag);
            self.timestamps[idx] = std.time.nanoTimestamp();
        }

        pub fn stop(self: *@This(), comptime tag: @TypeOf(.enum_literal)) void {
            const idx = tagIndex(tag);
            const time = std.time.nanoTimestamp() - self.timestamps[idx];
            self.state[idx] = smooth * self.state[idx] + (1 - smooth) * @as(f32, @floatFromInt(time)) / std.time.ns_per_ms;
        }

        pub fn report(self: @This()) void {
            std.debug.print("timer report:\n", .{});
            inline for (tags, self.state) |t, s| {
                std.debug.print("  {s}: {:.02} ms" ++ clear_line_and_break, .{@tagName(t), s});
            }
        }
    };
}
