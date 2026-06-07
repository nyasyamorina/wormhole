const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");
const math = @import("math.zig");
const shader_layout = @import("shader_layout.zig");

const v2f64 = math.v2f64;
const v3f64 = math.v3f64;
const v4f64 = math.v4f64;
const sqr = math.sqr;
const normalize = math.normalize;
const length = math.length;
const svm = math.svm;


frame: math.Frame,
sub_frame: math.ellis.frame.SubFrame = .{},
screen_scale: ScreenScale,
/// in local coord
thrust: f64,
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

    pub fn unScale(self: ScreenScale, p: [2]f64) [2]f64 {
        return .{
            self.mouse_scale_u * p[0],
            self.mouse_scale_v * p[1],
        };
    }

    pub fn toUniform(self: ScreenScale) [2]f32 {
        return .{self.u, self.v};
    }
};

pub fn rotateCamera(self: *Controller, mouse_move: [2]f64, speed: f64) void {
    const move = self.screen_scale.unScale(mouse_move);
    const rotate: v3f64 = .{move[1], 0, -move[0]};
    const axis = normalize(rotate);
    const angle = speed * length(rotate);
    self.frame.rotateSpacial(axis, angle);
}

pub fn changeThrust(self: *Controller, scroll: f64) void {
    const scroll_scale = 0.05;
    self.thrust *= @exp(scroll_scale * scroll);
}

pub fn accelerate(self: *Controller, direction: [3]i2, time_step: f64) void {
    const d: v3f64 = .{@floatFromInt(direction[0]), @floatFromInt(direction[1]), @floatFromInt(direction[2])};
    self.frame.localLorenz(svm(std.math.sinh(time_step * self.thrust), normalize(d)));
    self.sub_frame.recalculateBallComponents(&self.frame);
}

pub fn step(self: *Controller, time_step: f64) void {
    const step_size = time_step / @as(f64, @floatFromInt(self.simulation_sub_steps));
    for (0 .. self.simulation_sub_steps) |_| math.ellis.frame.forward(&self.frame, step_size);
}


pub fn printState(self: Controller, time: i96) !void {
    const i: math.ellis.InnerAt = .{ .position = self.frame.position };
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

    const coord_time = math.temporal(self.frame.position);
    const rho = math.spacial(self.frame.position)[0];
    const v_s = math.spacial(self.frame.axis_t);
    const v_rho = -std.math.sign(rho) * v_s[0];
    const v_angle_v4 = math.spacetime(.{0, v_s[1], v_s[2]}, 0);
    const v_angle = -i.call(v_angle_v4, v_angle_v4);

    try helper.stdout.interface.print(
        std.fmt.comptimePrint("wormhole radius: {:.02} km ({:.05} l.s.)", .{math.ellis.radius * math.light_speed, math.ellis.radius}) ++ helper.line_break
        ++ "time: {:.05} s" ++ helper.clear_line_and_break
        ++ "distamt time: {:.05}s" ++ helper.clear_line_and_break
        ++ "distance to wormhole: {:.02} km ({:.05} l.s.)" ++ helper.clear_line_and_break
        ++ "speed toward wormhole: {:.02} km/s ({:.05}x speed of light)" ++ helper.clear_line_and_break
        ++ "angular speed: {:.02} km/s ({:.05} deg/s)" ++ helper.clear_line_and_break
        ++ "maximum simulation error: {:.03}%" ++ helper.clear_line_and_break
        , .{
            @as(f32, @floatFromInt(time)) / std.time.ns_per_s,
            coord_time,
            @abs(rho) * math.light_speed, @abs(rho),
            v_rho * math.light_speed, v_rho,
            v_angle * math.light_speed, v_angle / (sqr(rho) + sqr(math.ellis.radius)) * (180.0 / std.math.pi),
            max_err * 100,
        },
    );
}
