const std = @import("std");
const vk = @import("vulkan-zig");


pub const Stage = enum {
    init_ray,
    render_ray,

    pub const all = std.meta.tags(Stage);

    pub fn getComptimeNamed(comptime self: Stage, comptime set: anytype) @TypeOf(@field(set, @tagName(self))) {
        return @field(set, @tagName(self));
    }

    pub fn getNamedRef(self: Stage, set_ptr: anytype) GetNamedRef(@TypeOf(set_ptr)) {
        inline for (all) |stage| {
            if (self == stage) return &@field(set_ptr, @tagName(stage));
        }
        unreachable;
    }
    fn GetNamedRef(comptime SetPtr: type) type {
        const ptr_info = @typeInfo(SetPtr).pointer;
        std.debug.assert(ptr_info.size == .one);
        const Set = ptr_info.child;
        const T = std.meta.fieldInfo(Set, .init_ray).type;
        return if (ptr_info.is_const) *const T else *T;
    }

    pub fn getNamedStatic(self: Stage, comptime namespace: type) GetNamedStatic(namespace) {
        inline for (all) |stage| {
            if (self == stage) return @field(namespace, @tagName(stage));
        }
        unreachable;
    }
    fn GetNamedStatic(namespace: type) type {
        return @TypeOf(namespace.init_ray);
    }
};

pub const Partical = extern struct {
    position: [4]f64,
    direction: [4]f64,
};

pub const uniforms = struct {
    pub const init_ray = extern struct {
        extent: [2]u32,
    };

    pub const render_ray = extern struct {
        extent: [2]u32,
    };
};

pub const set_layout_infos = struct {
    pub const init_ray = generate(&.{.uniform_buffer, .storage_buffer});
    pub const render_ray = generate(&.{.uniform_buffer, .uniform_buffer, .storage_image});

    inline fn generate(comptime types: []const vk.DescriptorType) vk.DescriptorSetLayoutCreateInfo {
        const bindings = blk: {
            var b: [types.len]vk.DescriptorSetLayoutBinding = undefined;
            for (types, 0..) |t, idx| {
                b[idx] = .{
                    .binding = idx,
                    .descriptor_type = t,
                    .descriptor_count = 1,
                    .stage_flags = .{ .compute_bit = true },
                };
            }
            break :blk b;
        };
        return .{
            .binding_count = bindings.len,
            .p_bindings = &bindings,
        };
    }
};
