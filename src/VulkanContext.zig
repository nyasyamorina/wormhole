const std = @import("std");
const nyazrc = @import("nyazrc");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");
const nyazvk = @import("nyazvk");

const helper = @import("helper.zig");


window: nyazrc.Rc(*glfw.Window),
instance: nyazvk.Instance,
surface: nyazvk.Surface,


const VulkanContext = @This();
const log = std.log.scoped(.VulkanContext);

pub fn init() !VulkanContext {
    const window: nyazrc.Rc(*glfw.Window) = try .init(helper.allocator, try createWindow());
    errdefer if (window.deinit(helper.allocator)) |w| w.destroy();

    const glfw_may_null_extensions = glfw.getRequiredInstanceExtensions() orelse &.{};
    for (glfw_may_null_extensions) |may_null| std.debug.assert(may_null != null);
    const glfw_extensions: []const [*:0]const u8 = @ptrCast(glfw_may_null_extensions);

    const instance: nyazvk.Instance = try .init(helper.allocator, .{
        .enabled_extensions = .{ .extensions = glfw_extensions },
    }, @ptrCast(&glfw.getInstanceProcAddress));
    errdefer instance.deinit(helper.allocator);

    const surface: nyazvk.Surface = try .initGlfw(helper.allocator, instance, window);
    errdefer surface.deinit(helper.allocator);

    return .{
        .window = window,
        .instance = instance,
        .surface = surface,
    };
}

pub fn deinit(self: VulkanContext) void {
    defer if (self.window.deinit(helper.allocator)) |w| w.destroy();
    defer self.instance.deinit(helper.allocator);
    defer self.surface.deinit(helper.allocator);
}


fn createWindow() !*glfw.Window {
    glfw.Window.Hint.set.clientApi(.no_api);
    glfw.Window.Hint.set.resizable(true);
    glfw.Window.Hint.set.transparentFramebuffer(true);

    const window = glfw.Window.create(.{ .width = 800, .height = 600 }, "wormhole", null, null) orelse return error.FaildToCreateWindow;

    // TODO: callbacks
    //window.setUserPointer(user_data: ?*anyopaque)
    //window.setFramebufferSizeCallback(cb: ?*const fn (*Window, c_int, c_int) void)
    //window.setScrollCallback(cb: ?*const fn (*Window, f64, f64) void)
    //window.setMouseButtonCallback(cb: ?*const fn (*Window, MouseButton, ActionPadded, Modifier) void)
    //window.setKeyCallback(cb: ?*const fn (*Window, Key, c_int, ActionPadded, Modifier) void)
    //...

    return window;
}
