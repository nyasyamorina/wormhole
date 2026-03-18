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
    position: [4]f32,
    direction: [4]f32,
};

pub const Camera = extern struct {
    /// normalized
    direction: [3]f32 align(16),
    u: [3]f32 align(16),
    v: [3]f32 align(16),
};

pub const uniforms = struct {
    pub const init_ray = extern struct {
        camera: Camera,
        position: [4]f32 align(16),
        speed: [3]f32 align(16),
    };

    pub const render_ray = extern struct {
        _placeholder: f32,
    };
};

pub const set_layout = struct {
    pub const layout_count = 3;
    pub const storage_count = 4;

    /// index: 0
    pub const uniform: vk.DescriptorSetLayoutCreateInfo = .{
        .binding_count = 1,
        .p_bindings = &.{ .{
            .binding = 0,
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .stage_flags = .{ .compute_bit = true },
        } },
    };

    /// index: 1
    pub const storage: vk.DescriptorSetLayoutCreateInfo = blk: {
        const bindings = blk1: {
            var bs: [storage_count]vk.DescriptorSetLayoutBinding = undefined;
            for (&bs, 0..) |*b, idx| b.* = .{
                .binding = idx,
                .descriptor_type = .storage_image,
                .descriptor_count = 1,
                .stage_flags = .{ .compute_bit = true },
            };
            break :blk1 bs;
        };
        break :blk .{
            .binding_count = bindings.len,
            .p_bindings = &bindings,
        };
    };

    /// index: 2
    pub const surface: vk.DescriptorSetLayoutCreateInfo = .{
        .binding_count = 1,
        .p_bindings = &.{ .{
            .binding = 0,
            .descriptor_type = .storage_image,
            .descriptor_count = 1,
            .stage_flags = .{ .compute_bit = true },
        } },
    };
};

pub const pipeline_set_layout_indices = struct {
    pub const init_ray: []const usize = &.{0, 1};
    pub const render_ray: []const usize = &.{0, 1, 2};
};
