const std = @import("std");
const vk = @import("vulkan-zig");


pub const Stage = enum {
    init_ray,
    iter_ray,
    render_ray,
    post_process_1,
    post_process_2,
    final,

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


pub const SpaceTimeFrame = extern struct {
    position: [4]f32 align(16),
    axis_x: [4]f32 align(16),
    axis_y: [4]f32 align(16),
    axis_z: [4]f32 align(16),
    axis_t: [4]f32 align(16),
};

pub const Uniform = extern struct {
    frame: SpaceTimeFrame,
    screen_scale: [2]f32 align(8),
    iter_per_call: u32,
};

pub const set_layout = struct {
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

pub const set_layout_infos = [_] vk.DescriptorSetLayoutCreateInfo {
    set_layout.uniform,
    set_layout.storage,
    set_layout.surface,
};

pub const pipeline_set_has_surface = struct {
    pub const init_ray = false;
    pub const iter_ray = false;
    pub const render_ray = false;
    pub const post_process_1 = false;
    pub const post_process_2 = false;
    pub const final = true;
};
