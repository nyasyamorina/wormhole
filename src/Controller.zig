const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");
const math = @import("math.zig");
const shader_layout = @import("shader_layout.zig");

const v3f32 = math.v3f32;
const v4f32 = math.v4f32;
const normalize = math.normalize;
const svm = math.svm;


space_time_frame: math.schwarzschild.Frame,
camera_scale: CameraScale,

/// in local coord
camera: Camera,
/// in global coord (x,y,z,t)
position: v4f32,
/// in global coord (x,y,z)
velocity: v3f32,
/// in local coord
thrust: f32,


const Controller = @This();


pub const CameraScale = struct {
    u: f32,
    v: f32,
    extent_u: f32 = 1,
    extent_v: f32 = 1,

    pub fn init(fov_y: f32) CameraScale {
        const s = @tan(fov_y * (std.math.pi / 180.0 / 2.0));
        return .{ .u = s, .v = s };
    }

    pub fn setAspectRatio(self: *CameraScale, extent: vk.Extent2D) void {
        self.extent_u = @floatFromInt(extent.width);
        self.extent_v = @floatFromInt(extent.height);
        self.u = self.extent_u / self.extent_v * self.v;
    }

    pub fn toUniform(self: CameraScale) [2]f32 {
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


pub fn changeThrust(self: *Controller, scroll: f32) void {
    const scroll_scale = 0.05;
    self.thrust *= @exp(scroll_scale * scroll);
}

pub fn accelerate(self: *Controller, direction: @Vector(3, i2), dt: f32) void {
    const hyperbolic_angle = dt * self.thrust;
    const space_scale = std.math.sinh(hyperbolic_angle);
    const time_scale = std.math.cosh(hyperbolic_angle);

    const d_local_not_norm: v3f32 = @floatFromInt(direction);
    const d_local = svm(space_scale, normalize(d_local_not_norm));
    const d_tangent = svm(d_local[0], self.camera.u) + svm(d_local[1], self.camera.d) + svm(d_local[2], self.camera.v);

    const V_t = @sqrt(1 + math.dot(self.velocity, self.velocity));
    const dot = math.dot(d_tangent, self.velocity);
    const k = time_scale + dot / (V_t + 1);
    self.velocity = d_tangent + svm(k, self.velocity);
}

pub fn step(self: *Controller, dt: f32) void {
    const V_t = @sqrt(1 + math.dot(self.velocity, self.velocity));
    const velocity: v4f32 = .{self.velocity[0], self.velocity[1], self.velocity[2], V_t};
    self.position += svm(dt, velocity);
}


pub fn printState(self: Controller) !void {
    const t = math.dot(self.velocity, self.velocity);
    const beta = @sqrt(t / (1 + t));

    try helper.stdout.interface.print(
        "\x1b[u" ++
        "time (global): {:.2} s\x1b[K\n" ++
        "position (global): ({:.2} km, {:.2} km, {:.2} km)\x1b[K\n" ++
        "speed (global): {:.2} km/s ({:.5}% c)\x1b[K\n" ++
        "movement thrust (local): {:.2} km/s/s\x1b[K\n"
        , .{
            self.position[3],
            self.position[0] * math.light_speed, self.position[1] * math.light_speed, self.position[2] * math.light_speed,
            beta * math.light_speed, beta * 100,
            self.thrust * math.light_speed,
        },
    );
    try helper.stdout.interface.flush();
}
