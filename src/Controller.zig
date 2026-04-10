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


space_time_frame: math.schwarzschild.Frame,
screen_scale: ScreenScale,
/// in local coord
thrust: f32,


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


pub const Camera = struct {
    /// normalized
    d: v3f32,
    /// normalized
    u: v3f32,
    /// normalized
    v: v3f32,
    scale_u: f32,
    scale_v: f32,

    pub const InitInfo = struct {
        direction: v3f32,
        view_up: v3f32,
        /// in deg
        fov_v: f32,
    };
    pub fn init(info: InitInfo) Camera {
        const d = math.normalize(info.direction);
        const u_n = math.normalize(math.cross(d, info.view_up));
        const v_n = math.cross(u_n, d);

        const scale = @tan(info.fov_v * (std.math.pi / 180.0 / 2.0));

        return .{
            .d = d,
            .u = u_n,
            .v = v_n,
            .scale_u = scale,
            .scale_v = scale,
        };
    }

    pub fn setAspectRatio(self: *Camera, extent: vk.Extent2D) void {
        const aspect_ratio = @as(f32, @floatFromInt(extent.width)) / @as(f32, @floatFromInt(extent.height));
        self.scale_u = aspect_ratio * self.scale_v;
    }

    pub fn rotate(self: *Camera, move: [2]f32, speed: f32) void {
        const move_direction = svm(move[0], self.u) - svm(move[1], self.v);

        const rotate_vector = math.cross(move_direction, self.d);
        const rotate_angle = speed * self.scale_v * math.length(rotate_vector);
        const rotate_axis = math.normalize(rotate_vector);

        self.d = math.rotate3d(self.d, rotate_axis, rotate_angle);
        self.u = math.rotate3d(self.u, rotate_axis, rotate_angle);
        self.v = math.rotate3d(self.v, rotate_axis, rotate_angle);
    }

    pub fn toUniform(self: Camera) shader_layout.Camera {
        return .{
            .direction = self.d,
            .u = svm(self.scale_u, self.u),
            .v = svm(self.scale_v, self.v),
        };
    }
};


pub fn rotateCamera(self: *Controller, mouse_move: [2]f32, speed: f32) void {
    const move = self.screen_scale.unScale(mouse_move);
    const rotate: v3f32 = .{move[1], 0, -move[0]};
    const axis = normalize(rotate);
    const angle = speed * length(rotate);
    self.space_time_frame.rotateSpacial(axis, angle);
}

pub fn changeThrust(self: *Controller, scroll: f32) void {
    const scroll_scale = 0.05;
    self.thrust *= @exp(scroll_scale * scroll);
}

pub fn accelerate(self: *Controller, direction: [3]i2, time_step: f32) void {
    const d: v3f32 = .{@floatFromInt(direction[0]), @floatFromInt(direction[1]), @floatFromInt(direction[2])};
    self.space_time_frame.accelerate(svm(time_step * self.thrust, normalize(d)));
}

pub fn step(self: *Controller, time_step: f32) void {
    self.space_time_frame.forward(time_step);
}


pub fn printState(self: Controller) !void {
    const i: math.schwarzschild.InnerAt = .{ .position = self.space_time_frame.position };

    try helper.stdout.interface.print(
           "frame:" ++ helper.line_break
        ++ "  p: {any}" ++ helper.clear_line_and_break
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
            self.space_time_frame.position,
            self.space_time_frame.axis_x,
            self.space_time_frame.axis_y,
            self.space_time_frame.axis_z,
            self.space_time_frame.axis_t,
            i.call(self.space_time_frame.axis_x, self.space_time_frame.axis_x),
            i.call(self.space_time_frame.axis_y, self.space_time_frame.axis_y),
            i.call(self.space_time_frame.axis_z, self.space_time_frame.axis_z),
            i.call(self.space_time_frame.axis_t, self.space_time_frame.axis_t),
            i.call(self.space_time_frame.axis_t, self.space_time_frame.axis_x),
            i.call(self.space_time_frame.axis_t, self.space_time_frame.axis_y),
            i.call(self.space_time_frame.axis_t, self.space_time_frame.axis_z),
            i.call(self.space_time_frame.axis_x, self.space_time_frame.axis_y),
            i.call(self.space_time_frame.axis_x, self.space_time_frame.axis_z),
            i.call(self.space_time_frame.axis_y, self.space_time_frame.axis_z),
        },
    );
}
