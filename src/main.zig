const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");
const VulkanContext = @import("VulkanContext.zig");


pub const std_options: std.Options = .{
    .logFn = helper.logger,
    .fmt_max_depth = 10,
};

pub fn main() !void {
    defer _ = helper.deinitAllocator();

    if (!glfw.init()) return error.FaildToInitGlfw;
    defer glfw.terminate();

    var vk_ctx: VulkanContext = try .init();
    defer vk_ctx.deinit();
}
