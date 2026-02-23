const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");
const VulkanContext = @import("VulkanContext.zig");


pub const std_options: std.Options = .{
    .logFn = helper.logger,
};

pub fn main() !void {
    if (!glfw.init()) return error.FaildToInitGlfw;
    defer glfw.terminate();

    helper.initAllocator();
    defer _ = helper.deinitAllocator();

    var vk_ctx: VulkanContext = try .init();
    defer vk_ctx.deinit();
}
