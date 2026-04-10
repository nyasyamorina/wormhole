const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");


frame_width: c_int,
frame_height: c_int,

mouse_move_x: f64 = 0,
mouse_move_y: f64 = 0,

press_w: bool = false,
press_a: bool = false,
press_s: bool = false,
press_d: bool = false,
press_ctrl: bool = false,
press_space: bool = false,

q_pressed: bool = false,

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
        .Q => self.q_pressed = action.action == .release,
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
    if (self.frame_width == 0 or self.frame_height == 0) return null;

    const res: vk.Extent2D = .{ .width = @intCast(self.frame_width), .height = @intCast(self.frame_height) };
    self.frame_width = 0; self.frame_height = 0;
    return res;
}
pub fn takeMouseMove(self: *GlfwCallback) ?[2]f32 {
    if (self.mouse_move_x == 0 and self.mouse_move_y == 0) return null;

    const res: [2]f32 = .{@floatCast(self.mouse_move_x), @floatCast(self.mouse_move_y)};
    self.mouse_move_x = 0; self.mouse_move_y = 0;
    return res;
}
pub fn takeMovement(self: GlfwCallback) ?[3]i2 {
    var direction: [3]i2 = .{0, 0, 0};

    direction[0] += @intFromBool(self.press_d);
    direction[0] -= @intFromBool(self.press_a);

    direction[1] += @intFromBool(self.press_w);
    direction[1] -= @intFromBool(self.press_s);

    direction[2] += @intFromBool(self.press_space);
    direction[2] -= @intFromBool(self.press_ctrl);

    if (direction[0] == 0 and direction[1] == 0 and direction[2] == 0) return null;
    return direction;
}
pub fn takeScroll(self: *GlfwCallback) ?f32 {
    if (self.scroll_y == 0) return null;

    const res: f32 = @floatCast(self.scroll_y);
    self.scroll_y = 0;
    return res;
}
