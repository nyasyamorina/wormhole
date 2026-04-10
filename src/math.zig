const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const shader_layout = @import("shader_layout.zig");

const log = std.log.scoped(.math);


pub inline fn sqr(x: anytype) @TypeOf(x) {
    return x * x;
}
pub inline fn cub(x: anytype) @TypeOf(x) {
    return x * x * x;
}


pub fn dot(u: anytype, v: @TypeOf(u)) @typeInfo(@TypeOf(u)).vector.child {
    return @reduce(.Add, u * v);
}
pub fn length(v: anytype) @typeInfo(@TypeOf(v)).vector.child {
    return @sqrt(dot(v, v));
}
pub fn normalize(v: anytype) @TypeOf(v) {
    const l = length(v);
    return svm(1 / l, v);
}

pub fn cross(u: anytype, v: @TypeOf(u)) @TypeOf(u) {
    std.debug.assert(@typeInfo(@TypeOf(u)).vector.len == 3);
    return .{
        u[1] * v[2] - u[2] * v[1],
        u[2] * v[0] - u[0] * v[2],
        u[0] * v[1] - u[1] * v[0],
    };
}

/// `axis`: normalized
pub fn rotate3d(p: anytype, axis: @TypeOf(p), angle: @typeInfo(@TypeOf(p)).vector.child) @TypeOf(p) {
    return svm(@cos(angle), p) + svm((1 - @cos(angle)) * dot(p, axis), axis) + svm(@sin(angle), cross(axis, p));
}


/// km/s
pub const light_speed = 299792.458;


pub const v2f32 = @Vector(2, f32);
pub const v3f32 = @Vector(3, f32);
pub const v4f32 = @Vector(4, f32);

/// scalar-vector multiplication
pub fn svm(s: anytype, v: anytype) @TypeOf(v) {
    return @as(@TypeOf(v), @splat(s)) * v;
}

pub inline fn spacial(v: v4f32) v3f32 {
    return .{v[0], v[1], v[2]};
}
pub inline fn temporal(v: v4f32) f32 {
    return v[3];
}
pub inline fn spacetime(s: v3f32, t: f32) v4f32 {
    return .{s[0], s[1], s[2], t};
}


pub const special_relativity = struct {
    /// consider the camera 4-velocity `V` in space-time, it is also the time axis of the tangent space-time of the camera,
    /// `V` has space-time length of 1, so the time component of `V` is `temporal(V) = sqrt(1 + dot(spacial(V), spacial(V)))`.
    ///
    /// consider a Lorenz transformation `L` that transform the global time axis `spacetime({0,0,0}, 1)` into `V`.
    /// the speed of the camera for "global observers" is `v = length(spacial(V)) / temporal(V)`,
    /// so the Lorenz factor of `L` is `γ = 1 / sqrt(1 - β * β)`, where `β = v/c` and `c` is the speed of light, we set `c = 1` here.
    /// then yields `γ = temporal(V)`.
    ///
    /// consider a Lorenz transformation in 1-d space `l`, and `l` has the same Lorenz factor as `L`,
    /// then `l` can transform `spacetime(0, 1)` into `spacetime(length(spacial(V)), temporal(V))`.
    /// consider a space rotation `R` that transform `spacial(V)` into `{length(spacial(V)),0,0}`,
    /// then the full `L` is construct as `L = inv(R) * l * R`.
    ///
    /// fortunately, there is no need to calculate `R`, because the net effect of `L` in space is expanding or shrinking along `spacial(V)`,
    /// marked `L` applies to arbitrary space-time vector `A` gets `B`, and assume `spacial(B) = spacial(A) + k * normalize(spacial(V))`,
    /// consider `l` applies to `spacetime(x0, t0)` gets `spacetime(x1, t1) = spacetime(γ * (β * t0 + x0), γ * (t0 + β * x0))`, then `x1 = x0 + k`,
    /// yields `spacial(B) = spacial(A) + (temporal(A) + dot(spacial(A), spacial(V)) / (temporal(V) + 1)) * spacial(V)`
    /// and `temporal(B) = temporal(A) * temporal(V) + dot(spacial(A), spacial(V))`.
    pub fn lorentz(A: v4f32, V_spacial: v3f32) v4f32 {
        const V_temporal = @sqrt(1 + dot(V_spacial, V_spacial));
        const scale = temporal(A) + dot(spacial(A), V_spacial) / (V_temporal + 1);
        const B_spacial = spacial(A) + svm(scale, V_spacial);
        const B_temporal = dot(A, spacetime(V_spacial, V_temporal));
        return spacetime(B_spacial, B_temporal);
    }

    /// inner product (dot product)
    pub fn inner(u: v4f32, v: v4f32) f32 {
        return temporal(u) * temporal(v) - dot(spacial(u), spacial(v));
    }
};

/// in Eddington–Finkelstein coordinates, but with Cartesian spacial components instead of spherical. (x, y, z, `t`)
///
/// note that the `t` component in Eddington–Finkelstein coordinates is not "time",
/// the actual coordinate time is `t + _signChanger(schwarzschild.radius * ln(abs(r / schwarzschild.radius - 1)))`
pub const schwarzschild = struct {
    /// = 2GM/c/c
    pub const radius = 1.0;

    /// inner product (dot product)
    pub fn inner(p: v4f32, u: v4f32, v: v4f32) f32 {
        const inv_r = 1 / length(spacial(p));
        const r_11 = schwarzschild.radius * inv_r;
        const s_11 = svm(inv_r, spacial(p));

        const s_u = s_11 * spacial(u);
        const s_v = s_11 * spacial(v);

        const flat_tt = temporal(u) * temporal(v);
        const flat_ss = @reduce(.Add, spacial(u) * spacial(v));

        const cross_tt = temporal(u) * temporal(v);
        const cross_ts = _signChanger(@reduce(.Add, svm(temporal(u), s_v) + svm(temporal(v), s_u)));
        const cross_ss = @reduce(.Add, svm(s_u[0], s_v) + svm(s_u[1], s_v) + svm(s_u[2], s_v));

        return (flat_tt - flat_ss) - r_11 * (cross_tt + cross_ts + cross_ss);
    }

    /// a wrapper of `schwarzschild.inner`
    pub const InnerAt = struct {
        position: v4f32,

        pub fn call(self: schwarzschild.InnerAt, u: v4f32, v: v4f32) f32 {
            return schwarzschild.inner(self.position, u, v);
        }
    };

    /// the local space-time frame around `position`,
    /// all axes are orthogonal, and normalized to having space-time length 1 (temporal) or -1 (spacial).
    ///
    /// the temporal axit is also the forward diretion of the whole frame in space-time.
    pub const Frame = struct {
        position: v4f32,
        axis_x: v4f32,
        axis_y: v4f32,
        axis_z: v4f32,
        axis_t: v4f32,

        /// init frame at the circular orbit around black/white hole
        pub fn initCircularOrbit(p: v4f32, d: v3f32) !schwarzschild.Frame {
            const s = spacial(p);
            const r = length(s);
            if (r <= 1.5 * schwarzschild.radius) {
                log.err("circular orbit does not exist inside photon sphere (1.5x schwarzschild radius), current: {}x", .{r / schwarzschild.radius});
                return error.InvalidArgument;
            }

            const direction = normalize(d - svm(dot(d, s) / dot(s, s), s));
            const time_angle_scale = r * @sqrt(2 * r / schwarzschild.radius);
            var self: schwarzschild.Frame = .{
                .position = p,
                .axis_x = spacetime(.{1, 0, 0}, 0),
                .axis_y = spacetime(.{0, 1, 0}, 0),
                .axis_z = spacetime(.{0, 0, 1}, 0),
                .axis_t = spacetime(direction, time_angle_scale),
            };
            self.normalizeAxes();
            return self;
        }

        /// init frame at rest (in a short time)
        pub fn initAtRest(p: v4f32) !schwarzschild.Frame {
            const r = length(spacial(p));
            if (r <= schwarzschild.radius) {
                log.err("cannot rest inside event horizon (1x schwarzschild radius), current: {}x", .{r / schwarzschild.radius});
                return error.InvalidArgument;
            }

            var self: schwarzschild.Frame = .{
                .position = p,
                .axis_x = spacetime(.{1, 0, 0}, 0),
                .axis_y = spacetime(.{0, 1, 0}, 0),
                .axis_z = spacetime(.{0, 0, 1}, 0),
                .axis_t = spacetime(.{0, 0, 0}, 1),
            };
            self.normalizeAxes();
            return self;
        }

        /// axes normalization order: t -> y -> x -> z
        pub fn normalizeAxes(self: *schwarzschild.Frame) void {
            const i: InnerAt = .{ .position = self.position };

            const axis_t = svm(1 / @sqrt(i.call(self.axis_t, self.axis_t)), self.axis_t);
            self.axis_t = axis_t;

            const axis_y_1 = self.axis_y - svm(i.call(self.axis_y, axis_t), axis_t);
            const axis_y = svm(1 / @sqrt(-i.call(axis_y_1, axis_y_1)), axis_y_1);
            self.axis_y = axis_y;

            const axis_x_1 = self.axis_x - svm(i.call(self.axis_x, axis_t), axis_t);
            const axis_x_2 = axis_x_1 + svm(i.call(axis_x_1, axis_y), axis_y);
            const axis_x = svm(1 / @sqrt(-i.call(axis_x_2, axis_x_2)), axis_x_2);
            self.axis_x = axis_x;

            const axis_z_1 = self.axis_z - svm(i.call(self.axis_z, axis_t), axis_t);
            const axis_z_2 = axis_z_1 + svm(i.call(axis_z_1, axis_y), axis_y);
            const axis_z_3 = axis_z_2 + svm(i.call(axis_z_2, axis_x), axis_x);
            const axis_z = svm(1 / @sqrt(-i.call(axis_z_3, axis_z_3)), axis_z_3);
            self.axis_z = axis_z;
        }

        /// transport the whole frame forawrd in space-time
        pub fn forward(self: *schwarzschild.Frame, step_size: f32) void {
            // TODO
            _ = .{self, step_size};
        }

        /// the Lorentz transformation of the frame
        pub fn accelerate(self: *schwarzschild.Frame, direction: v3f32) void {
            const axis_x_local = special_relativity.lorentz(spacetime(.{1, 0, 0}, 0), direction);
            const axis_y_local = special_relativity.lorentz(spacetime(.{0, 1, 0}, 0), direction);
            const axis_z_local = special_relativity.lorentz(spacetime(.{0, 0, 1}, 0), direction);
            const axis_t_local = special_relativity.lorentz(spacetime(.{0, 0, 0}, 1), direction);
            const axis_x = svm(spacial(axis_x_local)[0], self.axis_x) + svm(spacial(axis_x_local)[1], self.axis_y) + svm(spacial(axis_x_local)[2], self.axis_z) + svm(temporal(axis_x_local), self.axis_t);
            const axis_y = svm(spacial(axis_y_local)[0], self.axis_x) + svm(spacial(axis_y_local)[1], self.axis_y) + svm(spacial(axis_y_local)[2], self.axis_z) + svm(temporal(axis_y_local), self.axis_t);
            const axis_z = svm(spacial(axis_z_local)[0], self.axis_x) + svm(spacial(axis_z_local)[1], self.axis_y) + svm(spacial(axis_z_local)[2], self.axis_z) + svm(temporal(axis_z_local), self.axis_t);
            const axis_t = svm(spacial(axis_t_local)[0], self.axis_x) + svm(spacial(axis_t_local)[1], self.axis_y) + svm(spacial(axis_t_local)[2], self.axis_z) + svm(temporal(axis_t_local), self.axis_t);
            self.axis_x = axis_x;
            self.axis_y = axis_y;
            self.axis_z = axis_z;
            self.axis_t = axis_t;
        }

        /// `axis`: normalized
        pub fn rotateSpacial(self: *schwarzschild.Frame, axis: v3f32, angle: f32) void {
            const r_x = rotate3d(v3f32 {1, 0, 0}, axis, angle);
            const r_y = rotate3d(v3f32 {0, 1, 0}, axis, angle);
            const r_z = rotate3d(v3f32 {0, 0, 1}, axis, angle);
            const axis_x = svm(r_x[0], self.axis_x) + svm(r_x[1], self.axis_y) + svm(r_x[2], self.axis_z);
            const axis_y = svm(r_y[0], self.axis_x) + svm(r_y[1], self.axis_y) + svm(r_y[2], self.axis_z);
            const axis_z = svm(r_z[0], self.axis_x) + svm(r_z[1], self.axis_y) + svm(r_z[2], self.axis_z);
            self.axis_x = axis_x;
            self.axis_y = axis_y;
            self.axis_z = axis_z;
        }

        pub fn toUniform(self: schwarzschild.Frame) shader_layout.SpaceTimeFrame {
            return .{
                .position = self.position,
                .axis_x = self.axis_x,
                .axis_y = self.axis_y,
                .axis_z = self.axis_z,
                .axis_t = self.axis_t,
            };
        }
    };

    /// the delta of the component values in transpoting `v` along `d` while maintaining `v` parallel.
    ///
    /// this is a variant of the geodesics equation.
    pub fn deltaParallelTransport(p: v4f32, d: v4f32, v:v4f32) v4f32 {
        // TODO
        _ = .{p, d, v};
        return undefined;
    }

    inline fn _signChanger(x: f32) f32 {
        return  x; // for black hole
        //return -x; // for white hole (not tested)
    }
};
