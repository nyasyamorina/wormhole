const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");


pub fn main() !void {
    if (!glfw.init()) return error.FaildToInitGlfw;
    defer glfw.terminate();

    helper.initAllocator();
    defer _ = helper.deinitAllocator();
}
