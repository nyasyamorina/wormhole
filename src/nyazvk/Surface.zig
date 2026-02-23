const std = @import("std");
const nyazrc = @import("nyazrc");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const nyazvk = @import("nyazvk.zig");
const Instance = @import("Instance.zig");


instance: Instance,
inner: nyazrc.Rc(Inner),


const Surface = @This();

const Inner = struct {
    window: *anyopaque, // nyazrc.Rc(Window),
    window_deinitor: *const fn (*anyopaque, std.mem.Allocator) void,
    handle: vk.SurfaceKHR,
};

pub const InitGlfwError = error {
    InitializationFailed,
    ExtensionNotPresent,
    NativeWindowInUseKHR,
    Unknown,
} || std.mem.Allocator.Error;
pub fn initGlfw(allocator: std.mem.Allocator, instance: Instance, window: nyazrc.Rc(*glfw.Window)) InitGlfwError!Surface {
    var hndl: glfw.vk.SurfaceKHR = null;
    const result = glfw.glfwCreateWindowSurface(
        @ptrFromInt(@intFromEnum(instance.inner.value.handle)),
        window.value.*,
        null,
        &hndl,
    );

    switch (@as(vk.Result, @enumFromInt(@intFromEnum(result)))) {
        .success => {},
        .error_initialization_failed => return error.InitializationFailed,
        .error_extension_not_present => return error.ExtensionNotPresent,
        .error_native_window_in_use_khr => return error.NativeWindowInUseKHR,
        else => return error.Unknown,
    }

    const handle: vk.SurfaceKHR = @enumFromInt(@intFromPtr(hndl));
    errdefer instance.inner.value.wrapper.destroySurfaceKHR(instance.inner.value.handle, handle, null);

    return .{
        .instance = instance.clone(),
        .inner = try .init(allocator, .{
            .window = @ptrCast(window.clone().value),
            .window_deinitor = &deinitGlfwWindow,
            .handle = handle,
        }),
    };
}

pub fn clone(self: Surface) Surface {
    return .{
        .instance = self.instance.clone(),
        .inner = self.inner.clone(),
    };
}

pub fn deinit(self: Surface, allocator: std.mem.Allocator) void {
    if (self.inner.deinit(allocator)) |inner| {
        self.instance.inner.value.wrapper.destroySurfaceKHR(self.instance.inner.value.handle, inner.handle, null);
        inner.window_deinitor(inner.window, allocator);
    }
    self.instance.deinit(allocator);
}


fn deinitGlfwWindow(rc: *anyopaque, allocator: std.mem.Allocator) void {
    const window: nyazrc.Rc(*glfw.Window) = .{ .value = @ptrCast(@alignCast(rc)) };
    if (window.deinit(allocator)) |w| w.destroy();
}
