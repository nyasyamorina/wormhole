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

pub const line_break = if (is_windows) "\r\n" else "\n";
pub const clear_line_and_break = "\x1b[K" ++ line_break;

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


pub fn Timer(comptime tags: []const @TypeOf(.enum_literal), comptime smooth: f32) type {
    return struct {
        state: [tags.len]f32,
        timestamps: [tags.len]std.Io.Timestamp,

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
            self.timestamps[idx] = .now(io, .real);
        }

        pub fn stop(self: *@This(), comptime tag: @TypeOf(.enum_literal)) void {
            const idx = tagIndex(tag);
            const dur = self.timestamps[idx].durationTo(.now(io, .real));
            self.state[idx] = smooth * self.state[idx] + (1 - smooth) * @as(f32, @floatFromInt(dur.nanoseconds)) / std.time.ns_per_ms;
        }

        pub fn report(self: @This()) !void {
            try stdout.interface.print("timer report:\n", .{});
            inline for (tags, self.state) |t, s| {
                try stdout.interface.print("  {s}: {:.02} ms" ++ clear_line_and_break, .{@tagName(t), s});
            }
        }
    };
}


pub const multi_array = struct {
    pub fn Child(comptime M: type) type {
        switch (@typeInfo(M)) {
            .array => |info| return Child(info.child),
            else => return M,
        }
    }

    pub fn axes(comptime M: type) comptime_int {
        switch (@typeInfo(M)) {
            .array => |info| return 1 + axes(info.child),
            else => return 0,
        }
    }

    pub fn size(comptime M: type, comptime axis: usize) comptime_int {
        if (axis == 0) return @typeInfo(M).array.len;
        return size(@typeInfo(M).array.child, axis - 1);
    }

    pub fn len(comptime M: type) comptime_int {
        var l = 1;
        for (0 .. axes(M)) |axis| l *= size(M, axis);
        return l;
    }

    pub fn AsFlat(comptime M: type) type {
        return [len(M)]Child(M);
    }

    pub fn Similar(comptime A: type, comptime E: type) type {
        switch (@typeInfo(A)) {
            .array => |info| return [info.len]Similar(info.child, E),
            else => return E,
        }
    }
};
