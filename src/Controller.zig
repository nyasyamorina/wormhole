const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");
const math = @import("math.zig");
const shader_layout = @import("shader_layout.zig");


camera: shader_layout.Camera = undefined,


const Controller = @This();

pub fn init() !Controller {
    return .{
        .camera = undefined,
    };
}
pub fn deinit(self: Controller) void {
    _ = self;
}

pub const CameraInitInfo = struct {
    position: @Vector(3, f32),
    direction: @Vector(3, f32),
    view_up: @Vector(3, f32),
    /// in deg
    fov_v: f32,
};
pub fn initCamera(self: *Controller, info: CameraInitInfo) void {
    const d = math.normalize(info.direction);
    const u_n = math.normalize(math.cross(d, info.view_up));
    const v_n = math.cross(u_n, d);

    self.camera = .{
        .position = info.position,
        .direction = d,
        .u = u_n,
        .v = v_n,
    };
}
pub fn setCameraAspectRatio(self: *Controller, extent: vk.Extent2D) void {
    const u: @Vector(3, f32) = self.camera.u;
    const v: @Vector(3, f32) = self.camera.v;
    const inv_old_aspect_ratio = @sqrt(math.lengthSqr(v) / math.lengthSqr(u));
    const new_aspect_ratio = @as(f32, @floatFromInt(extent.width)) / @as(f32, @floatFromInt(extent.height));
    const scale_u = new_aspect_ratio * @sqrt(inv_old_aspect_ratio);
    self.camera.u = u * @as(@Vector(3, f32), @splat(scale_u));
}
pub fn rotateCamera(self: *Controller, move: glfw.Cursor.Pos, speed: f32) void {
    const d: @Vector(3, f32) = self.camera.direction;
    const u: @Vector(3, f32) = self.camera.u;
    const v: @Vector(3, f32) = self.camera.v;

    const move_x: @Vector(3, f32) = @splat(@floatCast(move.x));
    const move_y: @Vector(3, f32) = @splat(@floatCast(-move.y));
    const move_direction = move_x * math.normalize(u) + move_y * math.normalize(v);

    const rotate_vector = math.cross(move_direction, d);
    const rotate_angle = speed * math.length(rotate_vector);
    const rotate_axis = math.normalize(rotate_vector);

    self.camera.direction = math.rotate3d(d, rotate_axis, rotate_angle);
    self.camera.u = math.rotate3d(u, rotate_axis, rotate_angle);
    self.camera.v = math.rotate3d(v, rotate_axis, rotate_angle);
}
