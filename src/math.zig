const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const shader_layout = @import("shader_layout.zig");


pub fn dot(u: anytype, v: @TypeOf(u)) @typeInfo(@TypeOf(u)).vector.child {
    return @reduce(.Add, u * v);
}
pub fn length(v: anytype) @typeInfo(@TypeOf(v)).vector.child {
    return @sqrt(dot(v, v));
}
pub fn normalize(v: anytype) @TypeOf(v) {
    const l = length(v);
    return v / @as(@TypeOf(v), @splat(l));
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
    std.debug.assert(@typeInfo(@TypeOf(p)).vector.len == 3);
    const sin_v: @TypeOf(p) = @splat(@sin(angle));
    const cos_v: @TypeOf(p) = @splat(@cos(angle));
    const tmp_v: @TypeOf(p) = @splat((1 - @cos(angle)) * dot(p, axis));
    return cos_v * p + tmp_v * axis + sin_v * cross(axis, p);
}


/// km/s
pub const light_speed = 299792.458;
