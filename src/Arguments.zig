const std = @import("std");

const helper = @import("helper.zig");


slangc: Option(String, "slangc", null, "slangc"),
shader_folder: Option(String, null, 's', "shader"),


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
                    if (s1 == s2) {
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

        pub fn load(self: *@This(), matched: MatchResult, arg: []const u8) !void {
            if (self.matched) {
                const argarg = comptime if (short_arg) |s| s ++ " | " ++ long_arg else long_arg;
                log.err("option matched multiple times: {s}", .{argarg});
                return error.MatchedMultipleTimes;
            }
            self.matched  = true;

            const prefix = switch (matched) {
                .not_matched => unreachable,
                .short => blk: {
                    std.debug.assert(short != null);
                    break :blk short_arg.?;
                },
                .long => long_arg,
            };
            if (arg.len <= prefix.len) {
                if (T == bool) {
                    self.value = true;
                    return;
                } else {
                    log.err("missing value for: {s}", .{arg});
                    return error.MissingValue;
                }
            }

            std.debug.assert(arg[prefix.len] == '=');
            var value_str = arg[prefix.len+1 ..];
            if (value_str[0] == '\'' or value_str[0] == '"') {
                const quot = value_str[0];
                if (value_str[value_str.len-1] == quot) {
                    value_str = value_str[1 .. value_str.len-1];
                }
            }

            if (T == String) {
                const old = self.value;
                self.value = try helper.allocator.dupeZ(u8, value_str);
                if (comptime default != null) {
                    helper.allocator.free(old);
                } else {
                    if (old) |o| helper.allocator.free(o);
                }
            } else if (T == bool) {
                if (std.mem.eql(u8, value_str, "true")) {
                    self.value = true;
                } else if (std.mem.eql(u8, value_str, "false")) {
                    self.value = false;
                } else {
                    return unexpectedValue(arg, "false|true");
                }
            } else if (@typeInfo(T) == .int) {
                self.value = std.fmt.parseInt(T, value_str, 0) catch return unexpectedValue(arg,
                    @tagName(@typeInfo(T).int.signedness) ++ std.fmt.comptimePrint(" {d}-bit integer", .{@typeInfo(T).int.bits})
                );
            } else if (@typeInfo(T) == .float) {
                self.value = std.fmt.parseFloat(T, value_str) catch return unexpectedValue(arg, "number");
            } else comptime unreachable;
        }

        fn unexpectedValue(arg: []const u8, expect: []const u8) !void {
            log.err("got unexpected value for {s}, expect {}", .{arg, expect});
            return error.UnexpectedValue;
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
