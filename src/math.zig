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


/// transform a point from ball (spherical surface) coord to Cartesian coord
pub inline fn ballToCartesianPoint(p: anytype) @Vector(3, @typeInfo(@TypeOf(p)).vector.child) {
    const theta, const phi = p;
    return .{@sin(theta) * @cos(phi), @sin(theta) * @sin(phi), @cos(theta)};
}
/// transform a vector from ball (spherical surface) coord to Cartesian coord
pub inline fn ballToCartesianVector(p: anytype, v: @TypeOf(p)) @Vector(3, @typeInfo(@TypeOf(p)).vector.child) {
    const theta, const phi = p;
    const v_theta, const v_phi = v;
    const v_x = @cos(theta) * @cos(phi) * v_theta - @sin(theta) * @sin(phi) * v_phi;
    const v_y = @cos(theta) * @sin(phi) * v_theta + @sin(theta) * @cos(phi) * v_phi;
    const v_z = -@sin(theta) * v_theta;
    return .{v_x, v_y, v_z};
}

/// transform a point from Cartesian coord to ball (spherical surface) coord
///
/// `p`: normalized
pub inline fn cartesianToBallPoint(p: anytype) @Vector(2, @typeInfo(@TypeOf(p)).vector.child) {
    const x, const y, const z = p;
    return .{std.math.acos(z), std.math.atan2(y, x)};
}
/// transform a vector from Cartesian coord to ball (spherical surface) coord
///
/// `p`: normalized
/// `d`: the tangent vector of `p` on the unit ball, ie, `dot(p,d) = 0`
pub inline fn cartesianToBallVector(p: anytype, v: @TypeOf(p)) @Vector(2, @typeInfo(@TypeOf(p)).vector.child) {
    const x, const y, const z = p;
    const v_x, const v_y, const v_z = v;
    const sin_theta = @sqrt(sqr(x) + sqr(y));
    if (sin_theta < 1e-10) return .{@sqrt(sqr(v_x) + sqr(v_y)), 0};
    const v_theta = -v_z / sin_theta;
    const tmp = z / sin_theta * v_theta;
    const v_phi = if (@abs(x) > @abs(y))
        (v_y - tmp * y) / x
    else
        (tmp * x - v_x) / y;
    return .{v_theta, v_phi};
}


/// x10^30 kg
pub const solar_mass = 1.988416;
/// x10^-20 km^3/kg/s^2
pub const gravitational_constant = 6.6743015;
/// km/s
pub const light_speed = 299792.458;


pub const v2f64 = @Vector(2, f64);
pub const v3f64 = @Vector(3, f64);
pub const v4f64 = @Vector(4, f64);

/// scalar-vector multiplication
pub fn svm(s: anytype, v: anytype) @TypeOf(v) {
    return @as(@TypeOf(v), @splat(s)) * v;
}

pub inline fn spacial(v: v4f64) v3f64 {
    return .{v[0], v[1], v[2]};
}
pub inline fn temporal(v: v4f64) f64 {
    return v[3];
}
pub inline fn spacetime(s: v3f64, t: f64) v4f64 {
    return .{s[0], s[1], s[2], t};
}



/// the local space-time frame around `position`,
/// all axes are orthogonal, and normalized to having space-time length 1 (temporal) or -1 (spacial).
///
/// the temporal axit is also the forward diretion of the whole frame in space-time.
pub const Frame = struct {
    position: v4f64,
    axis_x: v4f64,
    axis_y: v4f64,
    axis_z: v4f64,
    axis_t: v4f64,

    /// the Lorentz transformation of the frame
    pub fn localLorenz(self: *Frame, direction: v3f64) void {
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
    pub fn rotateSpacial(self: *Frame, axis: v3f64, angle: f64) void {
        const r_x = rotate3d(v3f64 {1, 0, 0}, axis, angle);
        const r_y = rotate3d(v3f64 {0, 1, 0}, axis, angle);
        const r_z = rotate3d(v3f64 {0, 0, 1}, axis, angle);
        const axis_x = svm(r_x[0], self.axis_x) + svm(r_x[1], self.axis_y) + svm(r_x[2], self.axis_z);
        const axis_y = svm(r_y[0], self.axis_x) + svm(r_y[1], self.axis_y) + svm(r_y[2], self.axis_z);
        const axis_z = svm(r_z[0], self.axis_x) + svm(r_z[1], self.axis_y) + svm(r_z[2], self.axis_z);
        self.axis_x = axis_x;
        self.axis_y = axis_y;
        self.axis_z = axis_z;
    }

    pub fn toUniform(self: Frame) shader_layout.SpaceTimeFrame {
        return .{
            .position = @as(@Vector(4, f32), @floatCast(self.position)),
            .axis_x = @as(@Vector(4, f32), @floatCast(self.axis_x)),
            .axis_y = @as(@Vector(4, f32), @floatCast(self.axis_y)),
            .axis_z = @as(@Vector(4, f32), @floatCast(self.axis_z)),
            .axis_t = @as(@Vector(4, f32), @floatCast(self.axis_t)),
        };
    }
};

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
    pub fn lorentz(A: v4f64, V_spacial: v3f64) v4f64 {
        const V_temporal = @sqrt(1 + dot(V_spacial, V_spacial));
        const scale = temporal(A) + dot(spacial(A), V_spacial) / (V_temporal + 1);
        const B_spacial = spacial(A) + svm(scale, V_spacial);
        const B_temporal = dot(A, spacetime(V_spacial, V_temporal));
        return spacetime(B_spacial, B_temporal);
    }

    /// inner product (dot product)
    pub fn inner(u: v4f64, v: v4f64) f32 {
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
    /// x10^30 kg
    pub const mass = schwarzschild.radius * cub(light_speed / 100000.0) / gravitational_constant * 100000;

    pub fn distantTime(p: v4f64) f64 {
        const r = length(spacial(p));
        const t = temporal(p);
        return t + _signChanger(schwarzschild.radius * @log(@abs(r / schwarzschild.radius - 1)));
    }
    pub fn deltaDistantTime(p: v4f64, d: v4f64) f64 {
        const r = length(spacial(p));
        const dr = dot(spacial(p), spacial(d)) / r;
        return temporal(d) + _signChanger(schwarzschild.radius * dr / (r - schwarzschild.radius));
    }

    /// inner product (dot product)
    pub fn inner(p: v4f64, u: v4f64, v: v4f64) f64 {
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
        position: v4f64,

        pub fn call(self: schwarzschild.InnerAt, u: v4f64, v: v4f64) f64 {
            return schwarzschild.inner(self.position, u, v);
        }
    };


    pub const frame = struct {
        pub const InitState = enum {
            at_rest,
            circular_orbit,
        };
        pub fn init(state: InitState, p: v4f64, d: v3f64) !Frame {
            switch (state) {
                .at_rest => return initAtRest(p),
                .circular_orbit => return initCircularOrbit(p, d),
            }
        }

        /// init frame at the circular orbit around black/white hole
        pub fn initCircularOrbit(p: v4f64, d: v3f64) !Frame {
            const s = spacial(p);
            const r = length(s);
            if (r <= 1.5 * schwarzschild.radius) {
                log.err("circular orbit does not exist inside photon sphere (1.5x schwarzschild radius), current: {}x", .{r / schwarzschild.radius});
                return error.InvalidArgument;
            }

            const direction = normalize(d - svm(dot(d, s) / dot(s, s), s));
            const time_angle_scale = @sqrt(2 * r / schwarzschild.radius);
            var f: Frame = .{
                .position = p,
                .axis_x = spacetime(.{1, 0, 0}, 0),
                .axis_y = spacetime(.{0, 1, 0}, 0),
                .axis_z = spacetime(.{0, 0, 1}, 0),
                .axis_t = spacetime(direction, time_angle_scale),
            };
            normalizeAxes(&f);
            return f;
        }
        /// init frame at rest (in a short time)
        pub fn initAtRest(p: v4f64) !Frame {
            const r = length(spacial(p));
            if (r <= schwarzschild.radius) {
                log.err("cannot rest inside event horizon (1x schwarzschild radius), current: {}x", .{r / schwarzschild.radius});
                return error.InvalidArgument;
            }

            var f: Frame = .{
                .position = p,
                .axis_x = spacetime(.{1, 0, 0}, 0),
                .axis_y = spacetime(.{0, 1, 0}, 0),
                .axis_z = spacetime(.{0, 0, 1}, 0),
                .axis_t = spacetime(.{0, 0, 0}, 1),
            };
            normalizeAxes(&f);
            return f;
        }

        /// axes normalization order: t -> y -> x -> z
        pub fn normalizeAxes(f: *Frame) void {
            const i: InnerAt = .{ .position = f.position };

            const axis_t = svm(1 / @sqrt(i.call(f.axis_t, f.axis_t)), f.axis_t);

            const axis_y_1 = f.axis_y - svm(i.call(f.axis_y, axis_t), axis_t);
            const axis_y = svm(1 / @sqrt(-i.call(axis_y_1, axis_y_1)), axis_y_1);

            const axis_x_1 = f.axis_x - svm(i.call(f.axis_x, axis_t), axis_t);
            const axis_x_2 = axis_x_1 + svm(i.call(axis_x_1, axis_y), axis_y);
            const axis_x = svm(1 / @sqrt(-i.call(axis_x_2, axis_x_2)), axis_x_2);

            const axis_z_1 = f.axis_z - svm(i.call(f.axis_z, axis_t), axis_t);
            const axis_z_2 = axis_z_1 + svm(i.call(axis_z_1, axis_y), axis_y);
            const axis_z_3 = axis_z_2 + svm(i.call(axis_z_2, axis_x), axis_x);
            const axis_z = svm(1 / @sqrt(-i.call(axis_z_3, axis_z_3)), axis_z_3);

            f.axis_t = axis_t;
            f.axis_y = axis_y;
            f.axis_x = axis_x;
            f.axis_z = axis_z;
        }

        /// transport the whole frame forawrd in space-time, stop simulation if return false
        pub fn forward(f: *Frame, step_size: f64) bool {
            if (length(spacial(f.position)) < 0.07 * schwarzschild.radius) return false;

            const p1 = f.position;
            const x1 = f.axis_x;
            const y1 = f.axis_y;
            const z1 = f.axis_z;
            const t1 = f.axis_t;
            const ax1 = deltaParallelTransport(p1, t1, x1);
            const ay1 = deltaParallelTransport(p1, t1, y1);
            const az1 = deltaParallelTransport(p1, t1, z1);
            const at1 = deltaParallelTransport(p1, t1, t1);

            const p2 = p1 + svm(step_size * (2.0/3.0), t1);
            const x2 = x1 + svm(step_size * (2.0/3.0), ax1);
            const y2 = y1 + svm(step_size * (2.0/3.0), ay1);
            const z2 = z1 + svm(step_size * (2.0/3.0), az1);
            const t2 = t1 + svm(step_size * (2.0/3.0), at1);
            const ax2 = deltaParallelTransport(p2, t2, x2);
            const ay2 = deltaParallelTransport(p2, t2, y2);
            const az2 = deltaParallelTransport(p2, t2, z2);
            const at2 = deltaParallelTransport(p2, t2, t2);

            f.position += svm(step_size * 0.25, t1) + svm(step_size * 0.75, t2);
            f.axis_x += svm(step_size * 0.25, ax1) + svm(step_size * 0.75, ax2);
            f.axis_y += svm(step_size * 0.25, ay1) + svm(step_size * 0.75, ay2);
            f.axis_z += svm(step_size * 0.25, az1) + svm(step_size * 0.75, az2);
            f.axis_t += svm(step_size * 0.25, at1) + svm(step_size * 0.75, at2);
            return true;
        }
    };


    /// the delta of the component values in transpoting `v` along `d` while maintaining `v` parallel.
    ///
    /// this is a variant of the geodesics equation.
    pub fn deltaParallelTransport(p: v4f64, d: v4f64, v:v4f64) v4f64 {
        const inv_r = 1 / length(spacial(p));
        const r_12 = schwarzschild.radius * sqr(inv_r);
        const r_23 = sqr(schwarzschild.radius) * cub(inv_r);

        const s_11 = svm(inv_r, spacial(p));
        const s_d = s_11 * spacial(d);
        const s_v = s_11 * spacial(v);

        const tt = temporal(d) * temporal(v);
        const tsa = @reduce(.Add, svm(temporal(d), s_v) + svm(temporal(v), s_d));
        const aa = dot(spacial(d), spacial(v));
        const sasa = @reduce(.Add, svm(s_d[0], s_v) + svm(s_d[1], s_v) + svm(s_d[2], s_v));

        const c_t_tt = _signChanger(0.5 * r_23);
        const c_t_tsa = 0.5 * (r_12 + r_23);
        const c_t_aa = _signChanger(-r_12);
        const c_t_sasa = _signChanger(2 * r_12 + 0.5 * r_23);

        const c_sa_tt = 0.5 * (r_12 - r_23);
        const c_sa_tsa = _signChanger(-0.5 * r_23);
        const c_sa_aa = r_12;
        const c_sa_sasa = -1.5 * r_12 + -0.5 * r_23;

        return -spacetime(
            svm(c_sa_tt * tt + c_sa_tsa * tsa + c_sa_aa * aa + c_sa_sasa * sasa, s_11),
            c_t_tt * tt + c_t_tsa * tsa + c_t_aa * aa + c_t_sasa * sasa,
        );
    }

    inline fn _signChanger(x: anytype) @TypeOf(x) {
        return  x; // for black hole
        //return -x; // for white hole (not tested)
    }
};

/// Ellis wormhole
///
/// the spacial components in ellis coordinates is similar to spherical coordinates, but in `(rho, theta, phi)` instead of `(r, theta, phi)`,
/// and `rho` can be less than 0, note that when `rho = 0`, the space does not collapse into a point like in spherical coordinates.
pub const ellis = struct {
    /// the radius of the wormhole, note that this radius is located outside of space-time.
    pub const radius = 1.0;

    pub fn inner(p: v4f64, u: v4f64, v: v4f64) f64 {
        const rho, const theta, _ = spacial(p);
        const u_s = spacial(u); const v_s = spacial(v);

        const inner_soild_angle = u_s[1]*v_s[1] + sqr(@sin(theta)) * u_s[2]*v_s[2];
        return temporal(u)*temporal(v) - u_s[0]*v_s[0] - (sqr(rho)+sqr(ellis.radius)) * inner_soild_angle;
    }

    /// a wrapper of `ellis.inner`
    pub const InnerAt = struct {
        position: v4f64,

        pub fn call(self: ellis.InnerAt, u: v4f64, v: v4f64) f64 {
            return ellis.inner(self.position, u, v);
        }
    };


    pub const frame = struct {
        pub fn initAtRest(distance: f64) Frame {
            var f: Frame = .{
                .position = spacetime(.{distance, 0.5 * std.math.pi, 0}, 0),
                .axis_x = spacetime(.{0, 0, 1}, 0),
                .axis_y = spacetime(.{-1, 0, 0}, 0),
                .axis_z = spacetime(.{0, -1, 0}, 0),
                .axis_t = spacetime(.{0, 0, 0}, 1),
            };
            normalizeAxes(&f);
            return f;
        }

        /// axes normalization order: t -> y -> x -> z
        pub fn normalizeAxes(f: *Frame) void {
            const i: InnerAt = .{ .position = f.position };

            const axis_t = svm(1 / @sqrt(i.call(f.axis_t, f.axis_t)), f.axis_t);

            const axis_y_1 = f.axis_y - svm(i.call(f.axis_y, axis_t), axis_t);
            const axis_y = svm(1 / @sqrt(-i.call(axis_y_1, axis_y_1)), axis_y_1);

            const axis_x_1 = f.axis_x - svm(i.call(f.axis_x, axis_t), axis_t);
            const axis_x_2 = axis_x_1 + svm(i.call(axis_x_1, axis_y), axis_y);
            const axis_x = svm(1 / @sqrt(-i.call(axis_x_2, axis_x_2)), axis_x_2);

            const axis_z_1 = f.axis_z - svm(i.call(f.axis_z, axis_t), axis_t);
            const axis_z_2 = axis_z_1 + svm(i.call(axis_z_1, axis_y), axis_y);
            const axis_z_3 = axis_z_2 + svm(i.call(axis_z_2, axis_x), axis_x);
            const axis_z = svm(1 / @sqrt(-i.call(axis_z_3, axis_z_3)), axis_z_3);

            f.axis_t = axis_t;
            f.axis_y = axis_y;
            f.axis_x = axis_x;
            f.axis_z = axis_z;
        }

        /// transport the whole frame forawrd in space-time, stop simulation if return false
        pub fn forward(f: *Frame, step_size: f64) void {
            const p1 = f.position;
            const x1 = f.axis_x;
            const y1 = f.axis_y;
            const z1 = f.axis_z;
            const t1 = f.axis_t;
            const ax1 = deltaParallelTransport(p1, t1, x1);
            const ay1 = deltaParallelTransport(p1, t1, y1);
            const az1 = deltaParallelTransport(p1, t1, z1);
            const at1 = deltaParallelTransport(p1, t1, t1);

            const p2 = p1 + svm(step_size * (2.0/3.0), t1);
            const x2 = x1 + svm(step_size * (2.0/3.0), ax1);
            const y2 = y1 + svm(step_size * (2.0/3.0), ay1);
            const z2 = z1 + svm(step_size * (2.0/3.0), az1);
            const t2 = t1 + svm(step_size * (2.0/3.0), at1);
            const ax2 = deltaParallelTransport(p2, t2, x2);
            const ay2 = deltaParallelTransport(p2, t2, y2);
            const az2 = deltaParallelTransport(p2, t2, z2);
            const at2 = deltaParallelTransport(p2, t2, t2);

            f.position += svm(step_size * 0.25, t1) + svm(step_size * 0.75, t2);
            f.axis_x += svm(step_size * 0.25, ax1) + svm(step_size * 0.75, ax2);
            f.axis_y += svm(step_size * 0.25, ay1) + svm(step_size * 0.75, ay2);
            f.axis_z += svm(step_size * 0.25, az1) + svm(step_size * 0.75, az2);
            f.axis_t += svm(step_size * 0.25, at1) + svm(step_size * 0.75, at2);
        }};


    /// the delta of the component values in transpoting `v` along `d` while maintaining `v` parallel.
    pub fn deltaParallelTransport(p: v4f64, d: v4f64, v:v4f64) v4f64 {
        const rho, const theta, _ = spacial(p);
        const d_s = spacial(d); const v_s = spacial(v);

        const C_rho_thetatheta = -rho;
        const C_rho_phiphi = -rho * sqr(@sin(theta));
        const C_theta_rhotheta = rho / (sqr(rho) + sqr(ellis.radius));
        const C_theta_phiphi = @cos(theta) * @sin(theta);
        const C_phi_rhophi = C_theta_rhotheta;
        const C_phi_thetaphi = @cos(theta) / @sin(theta);

        return -spacetime(.{
            C_rho_thetatheta * d_s[1]*v_s[1] + C_rho_phiphi * d_s[2]*v_s[2],
            C_theta_rhotheta * (d_s[0]*v_s[1] + d_s[1]*v_s[0]) + C_theta_phiphi * d_s[2]*v_s[2],
            C_phi_rhophi * (d_s[0]*v_s[2] + d_s[2]*v_s[0]) + C_phi_thetaphi * (d_s[1]*v_s[2] + d_s[2]*v_s[1]),
        }, 0);
    }
};
