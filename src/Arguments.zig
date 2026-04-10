const std = @import("std");

const helper = @import("helper.zig");


slangc: Option(String, "slangc", null, "slangc"),
shader_folder: Option(String, null, 's', "shader"),
iter_per_call: Option(u32, 500, 'i', "iter-pre-call"),
n_iter_calls: Option(usize, 1, 'n', "n-iter-calls"),
fov_y: Option(f32, 60, 'f', "fov"),
circular: Option(bool, false, 'c', "circular"),
position: Option(f32, 100, 'p', "position"),
simulation_speed: Option(f32, 1, null, "simulation-speed"),


const Arguments = @This();
const options = @typeInfo(Arguments).@"struct".fields;
comptime {
    for (options[0 .. options.len-1], 0..) |o1, idx| {
        for (options[idx+1 ..]) |o2| {
            if (std.mem.eql(u8, o1.type.long_arg, o2.type.long_arg)) {
                @compileError("long name collision: " ++ o1.type.long_arg[2..]);
            }
            if (o1.type.short_arg) |s1| {
                if (o2.type.short_arg) |s2| {
                    if (std.mem.eql(u8, s1, s2)) {
                        @compileError("short name collision: " ++ s1);
                    }
                }
            }
        }
    }
}

const log = std.log.scoped(.Arguments);

pub const String = [:0]const u8;

pub fn Option(comptime T: type, comptime default: ?T, comptime short: ?u8, comptime long: []const u8) type {
    return struct {
        value: if (default) |_| T else ?T,
        matched: bool = false,

        pub const short_arg: ?[]const u8 = if (short) |s| "-" ++ [1]u8 {s} else null;
        pub const long_arg = "--" ++ long;

        pub fn init() !@This() {
            if (default) |d| {
                switch (T) {
                    String => return .{ .value = try helper.allocator.dupeZ(u8, d) },
                    else => return .{ .value = d },
                }
            } else return .{ .value = null };
        }

        pub fn deinit(self: @This()) void {
            switch (T) {
                String => if (comptime default == null) {
                    if (self.value) |v| helper.allocator.free(v);
                } else {
                    helper.allocator.free(self.value);
                },
                else => {},
            }
        }

        pub const MatchResult = enum {
            not_matched,
            short,
            long,
        };
        pub fn match(arg: []const u8) MatchResult {
            if (std.mem.startsWith(u8, arg, long_arg)) {
                if (arg.len == long_arg.len or arg[long_arg.len] == '=') return .long;
            }
            if (comptime short != null) {
                if (std.mem.startsWith(u8, arg, short_arg.?)) {
                if (arg.len == short_arg.?.len or arg[short_arg.?.len] == '=') return .short;
                }
            }
            return .not_matched;
        }

        fn _argPrefix(matched: MatchResult) []const u8 {
            return switch (matched) {
                .not_matched => unreachable,
                .short => blk: {
                    std.debug.assert(short != null);
                    break :blk short_arg.?;
                },
                .long => long_arg,
            };
        }
        fn _loadValueString(prefix: []const u8, arg: []const u8) ?[]const u8 {
            if (arg.len <= prefix.len) return null;

            std.debug.assert(arg[prefix.len] == '=');
            var value_str = arg[prefix.len+1 ..];
            if (value_str[0] == '\'' or value_str[0] == '"') {
                const quot = value_str[0];
                if (value_str[value_str.len-1] == quot) {
                    value_str = value_str[1 .. value_str.len-1];
                }
            }
            return value_str;
        }
        fn _parseValueString(arg_prefix: []const u8, value_str: []const u8) !T {
            if (T == String) {
                return helper.allocator.dupeZ(u8, value_str);
            } else if (T == bool) {
                if (std.mem.eql(u8, value_str, "true")) {
                    return true;
                } else if (std.mem.eql(u8, value_str, "false")) {
                    return false;
                } else {
                    _logUnexpectedValue(arg_prefix, "false|true");
                    return error.UnexpectedValue;
                }
            } else if (@typeInfo(T) == .int) {
                return std.fmt.parseInt(T, value_str, 0) catch {
                    _logUnexpectedValue(arg_prefix, std.fmt.comptimePrint("{t} {d}-bit integer", .{@typeInfo(T).int.signedness, @typeInfo(T).int.bits}));
                    return error.UnexpectedValue;
                };
            } else if (@typeInfo(T) == .float) {
                return std.fmt.parseFloat(T, value_str) catch {
                    _logUnexpectedValue(arg_prefix, "real number");
                    return error.UnexpectedValue;
                };
            } else comptime unreachable;
        }
        fn _logUnexpectedValue(arg_prefix: []const u8, expect: []const u8) void {
            log.err("got unexpected value for `{s}`, expect a {s}", .{arg_prefix, expect});
        }
        pub fn load(self: *@This(), matched: MatchResult, arg: []const u8) !void {
            if (self.matched) {
                const argarg = comptime if (short_arg) |s| s ++ " | " ++ long_arg else long_arg;
                log.err("argument matched multiple times: {s}", .{argarg});
                return error.ArgumentMatchedMultipleTimes;
            }
            self.matched  = true;

            const arg_prefix = _argPrefix(matched);

            const old = self.value;
            if (_loadValueString(arg_prefix, arg)) |value_str| {
                self.value = try _parseValueString(arg_prefix, value_str);
            } else if (T == bool) {
                self.value = true;
                return;
            } else {
                log.err("missing value for: {s}", .{arg});
                return error.MissingValue;
            }

            if (T == String) {
                if (comptime default != null) {
                    helper.allocator.free(old);
                } else {
                    if (old) |o| helper.allocator.free(o);
                }
            }
        }
    };
}

pub fn init() !Arguments {
    var self: Arguments = undefined;
    var inited_count: usize = 0;

    errdefer inline for (options, 0..) |o, idx| {
        if (idx < inited_count) @field(self, o.name).deinit();
    };

    inline for (options) |o| {
        @field(self, o.name) = try .init();
        inited_count += 1;
    }

    return self;
}

pub fn deinit(self: Arguments) void {
    inline for (options) |o| {
        @field(self, o.name).deinit();
    }
}

pub fn load(self: *Arguments, allow_extra: bool) !void {
    var iter = try std.process.argsWithAllocator(helper.allocator);
    defer iter.deinit();

    _ = iter.skip();
    next_arg: while (iter.next()) |arg| {
        inline for (options) |o| {
            const matched = o.type.match(arg);
            if (matched != .not_matched) {
                try @field(self, o.name).load(matched, arg);
                continue :next_arg;
            }
        } else if (!allow_extra) {
            log.err("unmatched argument: {s}", .{arg});
            return error.UnmatchedArgumrnt;
        }
    }
}
