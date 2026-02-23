const std = @import("std");


pub fn containName(names: []const [*:0]const u8, name: [*:0]const u8) bool {
    return for (names) |ele| {
        if (std.mem.orderZ(u8, ele, name) == .eq) break true;
    } else false;
}
