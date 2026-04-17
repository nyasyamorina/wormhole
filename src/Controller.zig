const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");
const math = @import("math.zig");
const shader_layout = @import("shader_layout.zig");

const v2f32 = math.v2f32;
const v3f32 = math.v3f32;
const v4f32 = math.v4f32;
const normalize = math.normalize;
const length = math.length;
const svm = math.svm;


frame: math.Frame,
screen_scale: ScreenScale,
/// in local coord
thrust: f32,
simulation_sub_steps: usize,


const Controller = @This();


pub const ScreenScale = struct {
    u: f32,
    v: f32,
    mouse_scale_u: f32 = 1,
    mouse_scale_v: f32 = 1,

    pub fn init(fov_y: f32) ScreenScale {
        const s = @tan(fov_y * (std.math.pi / 180.0 / 2.0));
        return .{ .u = s, .v = s };
    }

    pub fn setAspectRatio(self: *ScreenScale, extent: vk.Extent2D) void {
        const width: f32  = @floatFromInt(extent.width);
        const height: f32 = @floatFromInt(extent.height);
        self.u = (width / height) * self.v;
        self.mouse_scale_u =  self.u / width;
        self.mouse_scale_v = -self.v / height;
    }

    pub fn unScale(self: ScreenScale, p: [2]f32) [2]f32 {
        return .{
            self.mouse_scale_u * p[0],
            self.mouse_scale_v * p[1],
        };
    }

    pub fn toUniform(self: ScreenScale) [2]f32 {
        return .{self.u, self.v};
    }
};

pub fn rotateCamera(self: *Controller, mouse_move: [2]f32, speed: f32) void {
    const move = self.screen_scale.unScale(mouse_move);
    const rotate: v3f32 = .{move[1], 0, -move[0]};
    const axis = normalize(rotate);
    const angle = speed * length(rotate);
    self.frame.rotateSpacial(axis, angle);
}

pub fn changeThrust(self: *Controller, scroll: f32) void {
    const scroll_scale = 0.05;
    self.thrust *= @exp(scroll_scale * scroll);
}

pub fn accelerate(self: *Controller, direction: [3]i2, time_step: f32) void {
    const d: v3f32 = .{@floatFromInt(direction[0]), @floatFromInt(direction[1]), @floatFromInt(direction[2])};
    self.frame.localLorenz(svm(std.math.sinh(time_step * self.thrust), normalize(d)));
}

pub fn step(self: *Controller, time_step: f32) bool {
    const step_size = time_step / @as(f32, @floatFromInt(self.simulation_sub_steps));
    for (0 .. self.simulation_sub_steps) |_| {
        if (!math.schwarzschild.frame.forward(&self.frame, step_size)) return false;
    }
    return true;
}


pub fn printState(self: Controller) !void {
    const i: math.schwarzschild.InnerAt = .{ .position = self.frame.position };

    try helper.stdout.interface.print(
           "position:" ++ helper.line_break
        ++ "  {any} ({}x schwarzschild radius)" ++ helper.clear_line_and_break
        ++ "frame:" ++ helper.line_break
        ++ "  x: {any}" ++ helper.clear_line_and_break
        ++ "  y: {any}" ++ helper.clear_line_and_break
        ++ "  z: {any}" ++ helper.clear_line_and_break
        ++ "  t: {any}" ++ helper.clear_line_and_break
        ++ "frame dot products:" ++ helper.line_break
        ++ "  xx: {}" ++ helper.clear_line_and_break
        ++ "  yy: {}" ++ helper.clear_line_and_break
        ++ "  zz: {}" ++ helper.clear_line_and_break
        ++ "  tt: {}" ++ helper.clear_line_and_break
        ++ "  tx: {}" ++ helper.clear_line_and_break
        ++ "  ty: {}" ++ helper.clear_line_and_break
        ++ "  tz: {}" ++ helper.clear_line_and_break
        ++ "  xy: {}" ++ helper.clear_line_and_break
        ++ "  xz: {}" ++ helper.clear_line_and_break
        ++ "  yz: {}" ++ helper.clear_line_and_break
        , .{
            self.frame.position, length(math.spacial(self.frame.position)) / math.schwarzschild.radius,
            self.frame.axis_x,
            self.frame.axis_y,
            self.frame.axis_z,
            self.frame.axis_t,
            i.call(self.frame.axis_x, self.frame.axis_x),
            i.call(self.frame.axis_y, self.frame.axis_y),
            i.call(self.frame.axis_z, self.frame.axis_z),
            i.call(self.frame.axis_t, self.frame.axis_t),
            i.call(self.frame.axis_t, self.frame.axis_x),
            i.call(self.frame.axis_t, self.frame.axis_y),
            i.call(self.frame.axis_t, self.frame.axis_z),
            i.call(self.frame.axis_x, self.frame.axis_y),
            i.call(self.frame.axis_x, self.frame.axis_z),
            i.call(self.frame.axis_y, self.frame.axis_z),
        },
    );
}
