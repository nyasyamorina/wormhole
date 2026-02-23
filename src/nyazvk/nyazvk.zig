const std = @import("std");


pub const Instance = @import("Instance.zig");
pub const Surface = @import("Surface.zig");

pub const layers = struct {
    pub const khronos_validation = "VK_LAYER_KHRONOS_validation";
};

pub const log = std.log.scoped(.nyazvk);
