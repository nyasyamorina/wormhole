const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");


frame_resize: bool = false,
frame_width: c_int = undefined,
frame_height: c_int = undefined,

mouse_move_x: f64 = 0,
mouse_move_y: f64 = 0,

press_w: bool = false,
press_a: bool = false,
press_s: bool = false,
press_d: bool = false,
press_ctrl: bool = false,
press_space: bool = false,

scroll_y: f64 = 0,


const GlfwCallback = @This();

pub fn setCallbacks(self: *GlfwCallback, window: *glfw.Window) void {
    window.setUserPointer(@ptrCast(self));
    _ = window.setFramebufferSizeCallback(&resizeCB);
    _ = window.setCursorPosCallback(&mouseMoveCB);
    _ = window.setKeyCallback(&keyCB);
    _ = window.setScrollCallback(&scrollCB);
}

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
pub fn keyCB(window: *glfw.Window, key: glfw.Key, scan_code: c_int, action: glfw.ActionPadded, mods: glfw.Modifier) callconv(.c) void {
    const self = getSelf(window);
    switch (key) {
        .W => self.press_w = action.action != .release,
        .A => self.press_a = action.action != .release,
        .S => self.press_s = action.action != .release,
        .D => self.press_d = action.action != .release,
        .left_control => self.press_ctrl = action.action != .release,
        .space => self.press_space = action.action != .release,
        else => {},
    }
    _ = .{scan_code, mods};
}
pub fn scrollCB(window: *glfw.Window, x: f64, y: f64) callconv(.c) void {
    const self = getSelf(window);
    self.scroll_y += y;
    _ = x;
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
pub fn takeMouseMove(self: *GlfwCallback) [2]f32 {
    const move: [2]f32 = .{@floatCast(self.mouse_move_x), @floatCast(self.mouse_move_y)};
    self.mouse_move_x -= move[0]; self.mouse_move_y -= move[1];
    return move;
}
pub fn takeMovement(self: GlfwCallback) [3]i2 {
    var direction: [3]i2 = .{0, 0, 0};

    direction[0] += @intFromBool(self.press_d);
    direction[0] -= @intFromBool(self.press_a);

    direction[1] += @intFromBool(self.press_w);
    direction[1] -= @intFromBool(self.press_s);

    direction[2] += @intFromBool(self.press_space);
    direction[2] -= @intFromBool(self.press_ctrl);

    return direction;
}
pub fn takeScroll(self: *GlfwCallback) f32 {
    const scroll: f32 = @floatCast(self.scroll_y);
    self.scroll_y -= scroll;
    return scroll;
}
