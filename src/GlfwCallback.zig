const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");


frame_resize: bool = false,
frame_width: c_int = undefined,
frame_height: c_int = undefined,

mouse_move_x: f64 = 0,
mouse_move_y: f64 = 0,


const GlfwCallback = @This();

pub fn resizeCB(window: *glfw.Window, width: c_int, height: c_int) callconv(.c) void {
    const self = getSelf(window);
    self.frame_resize = true;
    self.frame_width = width;
    self.frame_height = height;
}
pub fn mouseMoveCB(window: *glfw.Window, pos_x: f64, pos_y: f64) callconv(.c) void {
    window.setCursorPos(.{ .x = 0, .y = 0 });
    const self = getSelf(window);
    self.mouse_move_x += pos_x;
    self.mouse_move_y += pos_y;
}

fn getSelf(window: *glfw.Window) *GlfwCallback {
    const data = window.getUserPointer();
    return @ptrCast(@alignCast(data));
}

pub fn takeResizeInfo(self: *GlfwCallback) ?vk.Extent2D {
    if (!self.frame_resize) return null;
    self.frame_resize = false;
    return .{
        .width = @intCast(self.frame_width),
        .height = @intCast(self.frame_height),
    };
}
pub fn takeMouseMove(self: *GlfwCallback) glfw.Cursor.Pos {
    const pos: glfw.Cursor.Pos = .{ .x = self.mouse_move_x, .y = self.mouse_move_y };
    self.mouse_move_x = 0; self.mouse_move_y = 0;
    return pos;
}
