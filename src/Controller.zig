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


pub fn printState(self: Controller, time: i128) !void {
    const i: math.schwarzschild.InnerAt = .{ .position = self.frame.position };
    const max_err = @max(
        @abs(i.call(self.frame.axis_x, self.frame.axis_x) - -1),
        @abs(i.call(self.frame.axis_y, self.frame.axis_y) - -1),
        @abs(i.call(self.frame.axis_z, self.frame.axis_z) - -1),
        @abs(i.call(self.frame.axis_t, self.frame.axis_t) -  1),
        @abs(i.call(self.frame.axis_t, self.frame.axis_x) -  0),
        @abs(i.call(self.frame.axis_t, self.frame.axis_y) -  0),
        @abs(i.call(self.frame.axis_t, self.frame.axis_z) -  0),
        @abs(i.call(self.frame.axis_x, self.frame.axis_y) -  0),
        @abs(i.call(self.frame.axis_x, self.frame.axis_z) -  0),
        @abs(i.call(self.frame.axis_y, self.frame.axis_z) -  0),
    );

    const r = length(math.spacial(self.frame.position));
    const v = math.length(math.spacial(self.frame.axis_t));
    const dr = math.dot(math.spacial(self.frame.position), math.spacial(self.frame.axis_t)) / r;
    const T = if (r < math.schwarzschild.radius) std.math.nan(f32) else math.schwarzschild.distantTime(self.frame.position);
    const dT = if (r < math.schwarzschild.radius) std.math.nan(f32) else math.schwarzschild.deltaDistantTime(self.frame.position, self.frame.axis_t);

    try helper.stdout.interface.print(
           "center object mass: {:.02}x10^30 kg ({:.02}x solar mass)" ++ helper.clear_line_and_break
        ++ "schwarzschild radius (rs): {:.02} km" ++ helper.clear_line_and_break
        ++ "your perspective:" ++ helper.line_break
        ++ "  time: {:.05} s" ++ helper.clear_line_and_break
        ++ "  speed: {:.02} km/s" ++ helper.clear_line_and_break
        ++ "  radial position: {:.02} km ({:.05}x rs)" ++ helper.clear_line_and_break
        ++ "  radial seed: {:.02} km/s ({:.05}x rs/s)" ++ helper.clear_line_and_break
        ++ "distant perspective:" ++ helper.line_break
        ++ "  time: {:.05} s" ++ helper.clear_line_and_break
        ++ "  speed: {:.02} km/s" ++ helper.clear_line_and_break
        ++ "  radial speed: {:.02} km/s ({:.05}x rs/s)" ++ helper.clear_line_and_break
        ++ "maximum simulation error: {:.03}%" ++ helper.clear_line_and_break
        , .{
            math.schwarzschild.mass, math.schwarzschild.mass / math.solar_mass,
            math.schwarzschild.radius * math.light_speed,

            @as(f32, @floatFromInt(time)) / std.time.ns_per_s,
            v * math.light_speed,
            r * math.light_speed, r / math.schwarzschild.radius,
            dr * math.light_speed, dr / math.schwarzschild.radius,

            T,
            v * math.light_speed / dT,
            dr  * math.light_speed / dT, dr / math.schwarzschild.radius / dT,
            max_err * 100,
        },
    );
}
