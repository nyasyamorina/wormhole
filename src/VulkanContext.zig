const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");
const shader_layout = @import("shader_layout.zig");
const Stage = shader_layout.Stage;


window: *glfw.Window,
instance: vk.InstanceProxy,
debug_messenger: vk.DebugUtilsMessengerEXT,
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
memory_type_fiinder: MemoryTypeFinder,
device: vk.DeviceProxy,
queue: vk.QueueProxy,
swapchain_info: vk.SwapchainCreateInfoKHR,
swapchain: vk.SwapchainKHR = .null_handle,
outdated_swapchain: bool = true,
swapchain_views: std.ArrayList(vk.ImageView) = .empty,
command_pool: vk.CommandPool,

uniform_memory: vk.DeviceMemory,
uniform_buffers: [Stage.all.len]vk.Buffer,
uniform_offsets_and_sizes: [Stage.all.len][2]u64,

pixel_count: u64 = 0,
storage_memory: vk.DeviceMemory = .null_handle,
ray_map: vk.Buffer = .null_handle,

set_layouts: [Stage.all.len]vk.DescriptorSetLayout = [1]vk.DescriptorSetLayout { .null_handle } ** Stage.all.len,
pipeline_layouts: [Stage.all.len]vk.PipelineLayout = [1]vk.PipelineLayout { .null_handle } ** Stage.all.len,
pipelines: [Stage.all.len]vk.Pipeline = [1]vk.Pipeline { .null_handle } ** Stage.all.len,


const VulkanContext = @This();
const log = std.log.scoped(.VulkanContext);

var instance_wrapper: vk.InstanceWrapper = .{ .dispatch = .{} };
var device_wrapper: vk.DeviceWrapper = .{ .dispatch = .{} };

pub fn init() !VulkanContext {
    const window = try _createWindow();
    errdefer window.destroy();

    const instance = try _createInstance(helper.allocator);
    errdefer helper.allocator.destroy(instance.wrapper);
    errdefer instance.destroyInstance(null);

    const debug_messenger = try _createDebugMessenger(instance);
    errdefer instance.destroyDebugUtilsMessengerEXT(debug_messenger, null);

    const surface = try _createSurface(instance, window);
    errdefer instance.destroySurfaceKHR(surface, null);

    var target_features: PhysicalDeviceFeatures(&.{vk.PhysicalDeviceVulkan13Features, vk.PhysicalDeviceExtendedDynamicStateFeaturesEXT}) = .{};
    target_features.set("dynamic_rendering", true);
    target_features.set("synchronization_2", true);
    _ = target_features.link();

    const target_extensions = [_][*:0]const u8 {
        vk.extensions.khr_swapchain.name,
        vk.extensions.khr_spirv_1_4.name,
        vk.extensions.khr_synchronization_2.name,
        vk.extensions.khr_create_renderpass_2.name,
    };

    const physical_device, const queue_family = try _pickPhysicalDevice(helper.allocator, instance, surface, target_features, &target_extensions);
    const memory_type_fiinder: MemoryTypeFinder = .init(instance, physical_device);

    const device = try _createDevice(instance, physical_device, queue_family, target_features, &target_extensions);
    errdefer helper.allocator.destroy(device.wrapper);
    errdefer device.destroyDevice(null);

    const queue = _getQueue(device, queue_family);
    const swapchain_info = try _getSwapchainInfo(helper.allocator, instance, physical_device, window, surface);

    const command_pool = try _createCommandPool(device, queue_family);
    errdefer device.destroyCommandPool(command_pool, null);

    const uniform_buffers = try _createUniformBuffers(device);
    errdefer for (uniform_buffers) |b| device.destroyBuffer(b, null);
    const uniform_memory, const uniform_offsets_and_sizes = try _allocAndBindUniformMemory(device, memory_type_fiinder, uniform_buffers);
    errdefer device.freeMemory(uniform_memory, null);

    return .{
        .window = window,
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .memory_type_fiinder = memory_type_fiinder,
        .device = device,
        .queue = queue,
        .swapchain_info = swapchain_info,
        .command_pool = command_pool,
        .uniform_memory = uniform_memory,
        .uniform_buffers = uniform_buffers,
        .uniform_offsets_and_sizes = uniform_offsets_and_sizes,
    };
}

pub fn deinit(self: *VulkanContext) void {
    defer self.window.destroy();
    defer self.instance.destroyInstance(null);
    defer self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
    defer self.instance.destroySurfaceKHR(self.surface, null);
    defer self.device.destroyDevice(null);
    defer self.device.destroySwapchainKHR(self.swapchain, null);
    defer self.swapchain_views.deinit(helper.allocator);
    defer for (self.swapchain_views.items) |v| self.device.destroyImageView(v, null);
    defer self.device.destroyCommandPool(self.command_pool, null);
    defer for (self.uniform_buffers) |b| self.device.destroyBuffer(b, null);
    defer self.device.freeMemory(self.uniform_memory, null);

    defer self.device.destroyBuffer(self.ray_map, null);
    defer self.device.freeMemory(self.storage_memory, null);

    defer for (self.set_layouts) |l| self.device.destroyDescriptorSetLayout(l, null);
    defer for (self.pipeline_layouts) |l| self.device.destroyPipelineLayout(l, null);
    defer for (self.pipelines) |p| self.device.destroyPipeline(p, null);
}

pub const MemoryTypeFinder = struct {
    count: u6,
    memory_type_flags: [32]vk.MemoryPropertyFlags,

    pub fn init(instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice) MemoryTypeFinder {
        const props = instance.getPhysicalDeviceMemoryProperties(physical_device);

        var self: MemoryTypeFinder = undefined;
        self.count = @intCast(props.memory_type_count);
        for (0 .. 32) |idx| self.memory_type_flags[idx] = props.memory_types[idx].property_flags;
        return self;
    }

    pub fn find(self: MemoryTypeFinder, mask: u32, props: vk.MemoryPropertyFlags) ?u5 {
        var idx: u6 = 0;
        var bit: u32 = 1;
        while (idx < self.count) : ({ idx += 1; bit <<= 1; }) {
            if (mask & bit != 0 and self.memory_type_flags[idx].contains(props)) {
                return @intCast(idx);
            }
        } else return null;
    }
};

fn _createUniformBuffers(device: vk.DeviceProxy) ![Stage.all.len]vk.Buffer {
    var buffers: [Stage.all.len]vk.Buffer = [1]vk.Buffer { .null_handle } ** Stage.all.len;
    var inited: usize = 0;
    errdefer for (buffers[0 .. inited]) |b| if (b != .null_handle) device.destroyBuffer(b, null);

    inline for (Stage.all) |stage| {
        buffers[@intFromEnum(stage)] = try device.createBuffer(&.{
            .sharing_mode = .exclusive,
            .size = @sizeOf(stage.getComptimeNamed(shader_layout.uniforms)),
            .usage = .{ .uniform_buffer_bit = true },
        }, null);
        inited += 1;
    }
    return buffers;
}
fn _allocAndBindUniformMemory(device: vk.DeviceProxy, finder: MemoryTypeFinder, buffers: [Stage.all.len]vk.Buffer) !struct {vk.DeviceMemory, [Stage.all.len][2]u64} {
    var offsets_and_sizes: [buffers.len][2]u64 = undefined;
    inline for (Stage.all) |stage| {
        offsets_and_sizes[@intFromEnum(stage)][1] = @sizeOf(stage.getComptimeNamed(shader_layout.uniforms));
    }

    var total_size: u64 = 0;
    var mem_type_mask: u32 = std.math.maxInt(u32);
    for (buffers, 0..) |b, idx| {
        const mem_req = device.getBufferMemoryRequirements(b);

        total_size += _aligAppendSize(total_size, mem_req.alignment);
        offsets_and_sizes[idx][0] = total_size;

        total_size += mem_req.size;
        mem_type_mask &= mem_req.memory_type_bits;
    }

    const mem_type = finder.find(mem_type_mask, .{
        .host_visible_bit = true,
        .host_coherent_bit = true,
    }) orelse return error.FailedToFindSuitableMemoryType;

    const memory = try device.allocateMemory(&.{
        .memory_type_index = mem_type,
        .allocation_size = total_size,
    }, null);
    errdefer device.freeMemory(memory, null);

    for (buffers, offsets_and_sizes) |b, os| {
        try device.bindBufferMemory(b, memory, os[0]);
    }

    return .{memory, offsets_and_sizes};
}

fn _aligAppendSize(size: u64, alignment: u64) u64 {
    std.debug.assert(std.math.isPowerOfTwo(alignment));
    return (alignment - (size & (alignment - 1))) & (alignment - 1);
}

fn _createWindow() !*glfw.Window {
    glfw.Window.Hint.set.clientApi(.no_api);
    glfw.Window.Hint.set.resizable(true);
    glfw.Window.Hint.set.transparentFramebuffer(true);

    const window = glfw.Window.create(.{ .width = 800, .height = 600 }, "wormhole", null, null) orelse return error.FaildToCreateWindow;

    // TODO: callbacks
    //window.setUserPointer(user_data: ?*anyopaque)
    //window.setFramebufferSizeCallback(cb: ?*const fn (*Window, c_int, c_int) void)
    //window.setScrollCallback(cb: ?*const fn (*Window, f64, f64) void)
    //window.setMouseButtonCallback(cb: ?*const fn (*Window, MouseButton, ActionPadded, Modifier) void)
    //window.setKeyCallback(cb: ?*const fn (*Window, Key, c_int, ActionPadded, Modifier) void)
    //...

    return window;
}

fn _createInstance(allocator: std.mem.Allocator) !vk.InstanceProxy {
    const vk_base: vk.BaseWrapper = .load(@as(vk.PfnGetInstanceProcAddr, @ptrCast(&glfw.getInstanceProcAddress)));
    const api_version = try vk_base.enumerateInstanceVersion();

    const may_glfw_extensions = glfw.getRequiredInstanceExtensions() orelse &.{};
    for (may_glfw_extensions) |e| std.debug.assert(e != null);

    const extensions = try allocator.alloc([*:0]const u8, may_glfw_extensions.len + @intFromBool(helper.is_debug));
    defer allocator.free(extensions);
    @memcpy(extensions[0 .. may_glfw_extensions.len], @as([*]const [*:0]const u8, @ptrCast(may_glfw_extensions.ptr)));
    if (helper.is_debug) extensions[may_glfw_extensions.len] = vk.extensions.ext_debug_utils.name;

    const validation_layers: []const [*:0]const u8 = if (helper.is_debug) &.{
        "VK_LAYER_KHRONOS_validation",
    } else &.{};

    //const debug_info: vk.DebugUtilsMessengerCreateInfoEXT = if (helper.is_debug) .{
    //    .message_severity = .{
    //        .verbose_bit_ext = true,
    //        .info_bit_ext = true,
    //        .warning_bit_ext = true,
    //        .error_bit_ext = true,
    //    },
    //    .message_type = .{
    //        .general_bit_ext = true,
    //        .performance_bit_ext = true,
    //        .validation_bit_ext = true,
    //    },
    //    .pfn_user_callback = &debugMessengerCallback,
    //} else undefined;

    const handle = try vk_base.createInstance(&.{
        .p_next = null,//if (helper.is_debug) @ptrCast(&debug_info) else null,
        .flags = if (helper.is_macos and api_version > @as(u32, @bitCast(vk.makeApiVersion(0, 1, 3, 215)))) .{
            .enumerate_portability_bit_khr = true,
        } else .{},
        .p_application_info = &.{
            .application_version = 0,
            .engine_version = 0,
            .api_version = api_version,
        },
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
        .enabled_layer_count = @intCast(validation_layers.len),
        .pp_enabled_layer_names = validation_layers.ptr,
    }, null);

    instance_wrapper = .load(handle, vk_base.dispatch.vkGetInstanceProcAddr.?);
    return .init(handle, &instance_wrapper);
}

fn debugMessengerCallback(m_severity: vk.DebugUtilsMessageSeverityFlagsEXT, m_types: vk.DebugUtilsMessageTypeFlagsEXT, callback_data: *const vk.DebugUtilsMessengerCallbackDataEXT, _: ?*anyopaque) callconv(vk.vulkan_call_conv) vk.Bool32 {
    const level: std.log.Level = if (m_severity.error_bit_ext)
        .err
    else if (m_severity.warning_bit_ext)
        .warn
    else if (m_severity.info_bit_ext)
        .info
    else
        .debug
    ;

    const type_msg = comptime [_]struct {vk.Flags, []const u8} {
        .{(vk.DebugUtilsMessageTypeFlagsEXT { .device_address_binding_bit_ext = true }).toInt(), "DeviceAddressBinding"},
        .{(vk.DebugUtilsMessageTypeFlagsEXT { .general_bit_ext = true }).toInt(), "General"},
        .{(vk.DebugUtilsMessageTypeFlagsEXT { .performance_bit_ext = true }).toInt(), "Performance"},
        .{(vk.DebugUtilsMessageTypeFlagsEXT { .validation_bit_ext = true }).toInt(), "Validation"},
    };
    const max_msg_types_len = comptime blk: {
        var len = 0;
        for (type_msg) |tm| len += tm.@"1".len + 1;
        break :blk len;
    };

    var msg_buffer: [max_msg_types_len]u8 = undefined;
    var msg_types: std.ArrayList(u8) = .initBuffer(&msg_buffer);
    inline for (type_msg) |tm| if (@as(vk.Flags, @bitCast(m_types)) & tm.@"0" != 0) msg_types.appendSliceAssumeCapacity(tm.@"1" ++ "|");

    const log_format = "|{s}> {s}: {s}";
    const log_args = .{msg_types.items, callback_data.p_message_id_name orelse "", callback_data.p_message orelse ""};

    const debug_log = std.log.scoped(.debug_utils);
    switch (level) {
        .err => debug_log.err(log_format, log_args),
        .warn => debug_log.warn(log_format, log_args),
        .info => debug_log.info(log_format, log_args),
        .debug => debug_log.debug(log_format, log_args),
    }

    return .false;
}

fn _createDebugMessenger(instance: vk.InstanceProxy) !vk.DebugUtilsMessengerEXT {
    if (helper.is_debug) {
        return instance.createDebugUtilsMessengerEXT(&.{
            .message_severity = .{
                .verbose_bit_ext = true,
                .info_bit_ext = true,
                .warning_bit_ext = true,
                .error_bit_ext = true,
            },
            .message_type = .{
                .general_bit_ext = true,
                .performance_bit_ext = true,
                .validation_bit_ext = true,
            },
            .pfn_user_callback = &debugMessengerCallback,
        }, null);
    } else return .null_handle;
}


fn _createSurface(instance: vk.InstanceProxy, window: *glfw.Window) !vk.SurfaceKHR {
    var handle: vk.SurfaceKHR = .null_handle;
    const result: vk.Result = @enumFromInt(@intFromEnum(glfw.glfwCreateWindowSurface(
        @ptrFromInt(@intFromEnum(instance.handle)),
        window,
        null,
        @ptrCast(&handle),
    )));
    switch (result) {
        .success => {},
        .error_initialization_failed => return error.InitializationFailed,
        .error_extension_not_present => return error.ExtensionNotPresent,
        .error_native_window_in_use_khr => return error.NativeWindowInUseKHR,
        else => return error.Unknown,
    }
    return handle;
}


pub fn PhysicalDeviceFeatures(comptime ExtraFeatures: []const type) type {
    return struct {
        extras: Extras = .{},
        core2: vk.PhysicalDeviceFeatures2 = .{ .features = .{} },

        pub const Extras = blk: {
            var fields: [ExtraFeatures.len]std.builtin.Type.StructField = undefined;
            for (ExtraFeatures, &fields, 0..) |extra, *field, index| {
                field.* = .{
                    .name = std.fmt.comptimePrint("{d}", .{index}),
                    .type = extra,
                    .default_value_ptr = @ptrCast(&extra {}),
                    .is_comptime = false,
                    .alignment = @alignOf(extra),
                };
            }
            break :blk @Type(.{ .@"struct" = .{
                .layout = .auto,
                .fields = &fields,
                .decls = &.{},
                .is_tuple = false,
            } });
        };

        pub fn link(self: *@This()) *vk.PhysicalDeviceFeatures2 {
            inline for (0 .. ExtraFeatures.len) |index| {
                const field_name = comptime std.fmt.comptimePrint("{d}", .{index});
                if (comptime index == 0) {
                    self.core2.p_next = @ptrCast(&@field(self.extras, field_name));
                } else {
                    const field_name_1 = comptime std.fmt.comptimePrint("{d}", .{index - 1});
                    @field(self.extras, field_name_1).p_next = @ptrCast(&@field(self.extras, field_name));
                }
            }
            return &self.core2;
        }

        pub fn set(self: *@This(), comptime feature_name: []const u8, value: bool) void {
            inline for (@typeInfo(vk.PhysicalDeviceFeatures).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, feature_name)) {
                    @field(self.core2.features, feature_name) = if (value) .true else .false;
                    return;
                }
            }
            inline for (ExtraFeatures, 0..) |extra, index| {
                const extra_name = comptime std.fmt.comptimePrint("{d}", .{index});
                inline for (@typeInfo(extra).@"struct".fields) |field| {
                    if (comptime std.mem.eql(u8, field.name, feature_name)) {
                        @field(@field(self.extras, extra_name), feature_name) = if (value) .true else .false;
                        return;
                    }
                }
            }
            @compileError("no feature has name " ++ feature_name);
        }

        pub fn has(self: @This(), comptime feature_name: []const u8) bool {
            inline for (@typeInfo(vk.PhysicalDeviceFeatures).@"struct".fields) |field| {
                if (comptime std.mem.eql(u8, field.name, feature_name)) {
                    return @field(self.core2.features, feature_name) != .false;
                }
            }
            inline for (ExtraFeatures, 0..) |extra, index| {
                const extra_name = comptime std.fmt.comptimePrint("{d}", .{index});
                inline for (@typeInfo(extra).@"struct".fields) |field| {
                    if (comptime std.mem.eql(u8, field.name, feature_name)) {
                        return @field(@field(self.extras, extra_name), feature_name) != .false;
                    }
                }
            }
            @compileError("no feature has name " ++ feature_name);
        }

        pub fn contains(self: @This(), subset: @This()) bool {
            inline for (@typeInfo(vk.PhysicalDeviceFeatures).@"struct".fields) |field| {
                if (@field(subset.core2.features, field.name) != .false) {
                    if (@field(self.core2.features, field.name) == .false) return false;
                }
            }
            inline for (ExtraFeatures, 0..) |extra, index| {
                const extra_name = comptime std.fmt.comptimePrint("{d}", .{index});
                inline for (@typeInfo(extra).@"struct".fields) |field| {
                    if (comptime !std.mem.eql(u8, field.name, "s_type") and !std.mem.eql(u8, field.name, "p_next")) {
                        if (@field(@field(subset.extras, extra_name), field.name) != .false) {
                            if (@field(@field(self.extras, extra_name), field.name) == .false) return false;
                        }
                    }
                }
            }
            return true;
        }
    };
}

fn _pickPhysicalDevice(allocator: std.mem.Allocator, instance: vk.InstanceProxy, surface: vk.SurfaceKHR, target_features: anytype, target_extensions: []const [*:0]const u8) !struct {vk.PhysicalDevice, u32} {
    const handles = try instance.enumeratePhysicalDevicesAlloc(allocator);
    defer allocator.free(handles);

    next_handle: for (handles) |p| {
        var features: @TypeOf(target_features) = .{};
        instance.getPhysicalDeviceFeatures2(p, features.link());
        if (!features.contains(target_features)) continue;

        const extensions = try instance.enumerateDeviceExtensionPropertiesAlloc(p, null, allocator);
        defer allocator.free(extensions);
        next_extension: for (target_extensions) |e1| {
            for (extensions) |e2| {
                if (std.mem.orderZ(u8, @ptrCast(&e2.extension_name), e1) == .eq) continue :next_extension;
            } else continue :next_handle;
        }

        const queue_family = try _findGeneralQueueFamily(allocator, instance, p, surface) orelse continue;

        return .{p, queue_family};
    } else return error.SuitablePhysicalDeviceNotFound;
}

fn _findGeneralQueueFamily(allocator: std.mem.Allocator, instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !?u32 {
    const props = try instance.getPhysicalDeviceQueueFamilyPropertiesAlloc(physical_device, allocator);
    defer allocator.free(props);

    for (props, 0..) |prop, idx| {
        if (prop.queue_flags.graphics_bit and prop.queue_flags.compute_bit) {
            const queue_family_index: u32 = @intCast(idx);
            if (surface != .null_handle) {
                if (try instance.getPhysicalDeviceSurfaceSupportKHR(physical_device, queue_family_index, surface) == .false) {
                    continue;
                }
            }
            return queue_family_index;
        }
    }
    return null;
}

fn _createDevice(instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice, queue_family: u32, target_features: anytype, target_extensions: []const [*:0]const u8) !vk.DeviceProxy {
    const handle = try instance.createDevice(physical_device, &.{
        .p_next = @ptrCast(&target_features.core2),
        .queue_create_info_count = 1,
        .p_queue_create_infos = &.{ .{
            .queue_family_index = queue_family,
            .queue_count = 1,
            .p_queue_priorities = &.{1.0},
        } },
        .enabled_extension_count = @intCast(target_extensions.len),
        .pp_enabled_extension_names = target_extensions.ptr,
    }, null);

    device_wrapper = .load(handle, instance.wrapper.dispatch.vkGetDeviceProcAddr.?);
    return .init(handle, &device_wrapper);
}

fn _getQueue(device: vk.DeviceProxy, queue_family: u32) vk.QueueProxy {
    const handle = device.getDeviceQueue(queue_family, 0);
    return .init(handle, device.wrapper);
}


fn _getSwapchainInfo(allocator: std.mem.Allocator, instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice, window: *glfw.Window, surface: vk.SurfaceKHR) !vk.SwapchainCreateInfoKHR {
    var capas = try instance.getPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface);
    std.debug.assert(capas.supported_usage_flags.contains(.{ .storage_bit = true }));
    const image_extent = if (capas.current_extent.width == std.math.maxInt(u32)) blk: {
        const size = window.getFramebufferSize();
        break :blk vk.Extent2D {
            .width  = std.math.clamp(@as(u32, @intCast(size.width )), capas.min_image_extent.width , capas.max_image_extent.width ),
            .height = std.math.clamp(@as(u32, @intCast(size.height)), capas.min_image_extent.height, capas.max_image_extent.height),
        };
    } else capas.current_extent;

    const surface_formats = try instance.getPhysicalDeviceSurfaceFormatsAllocKHR(physical_device, surface, allocator);
    defer allocator.free(surface_formats);
    const surface_format = for (surface_formats) |f| {
        if (std.meta.eql(f, .{ .format = .b8g8r8a8_unorm, .color_space = .srgb_nonlinear_khr })) break f;
    } else surface_formats[0];

    const present_modes = try instance.getPhysicalDeviceSurfacePresentModesAllocKHR(physical_device, surface, allocator);
    defer allocator.free(present_modes);
    std.debug.assert(std.mem.indexOfScalar(vk.PresentModeKHR, present_modes, .fifo_khr) != null);

    return .{
        .surface = surface,
        .present_mode = .fifo_khr, // always has
        .clipped = .true,
        .min_image_count = capas.min_image_count,
        .image_array_layers = 1,
        .pre_transform = capas.current_transform,
        .composite_alpha = capas.supported_composite_alpha.intersect(.{ .opaque_bit_khr = true }),
        .image_color_space = surface_format.color_space,
        .image_format = surface_format.format,
        .image_extent = image_extent,
        .image_usage = .{ .storage_bit = true },
        .image_sharing_mode = .exclusive,
    };
}


fn _createCommandPool(device: vk.DeviceProxy, queue_family: u32) !vk.CommandPool {
    return device.createCommandPool(&.{
        .queue_family_index = queue_family,
    }, null);
}

fn _createCommandBuffer(device: vk.DeviceProxy, command_pool: vk.CommandPool) !vk.CommandBufferProxy {
    var handles: [1]vk.CommandBuffer = undefined;
    try device.allocateCommandBuffers(&.{
        .level = .primary,
        .command_pool = command_pool,
        .command_buffer_count = 1,
    }, &handles);
    return .init(handles[0], device.wrapper);
}


fn _createImageView(device: vk.DeviceProxy, image: vk.Image, format: vk.Format) !vk.ImageView {
    return device.createImageView(&.{
        .image = image,
        .format = format,
        .view_type = .@"2d",
        .components = .{
            .r = .identity,
            .g = .identity,
            .b = .identity,
            .a = .identity,
        },
        .subresource_range = .{
            .aspect_mask = .{ .color_bit = true },
            .base_mip_level = 0,
            .level_count = 1,
            .base_array_layer = 0,
            .layer_count = 1,
        },
    }, null);
}


pub fn recreateSwapchainStuff(self: *VulkanContext) !void {
    // create new swapchain
    self.swapchain_info.old_swapchain = self.swapchain;
    const swapchain = try self.device.createSwapchainKHR(&self.swapchain_info, null);
    errdefer self.device.destroySwapchainKHR(swapchain, null);

    // get swapchain images
    const images = try self.device.getSwapchainImagesAllocKHR(swapchain, helper.allocator);
    defer helper.allocator.free(images);
    try self.swapchain_views.ensureTotalCapacity(helper.allocator, images.len);
    // create new swapchain image views
    var views: std.ArrayList(vk.ImageView) = try .initCapacity(helper.allocator, images.len);
    defer views.deinit(helper.allocator);
    errdefer for (views) |v| self.device.destroyImageView(v, null);
    for (images) |i| views.appendAssumeCapacity(try _createImageView(self.device, i, self.swapchain_info.image_format));

    const pixel_count = @as(u64, self.swapchain_info.image_extent.width) * self.swapchain_info.image_extent.height;
    if (pixel_count > self.pixel_count) {

    }

    // destroy old swapchain image views
    for (self.swapchain_views.items) |v| self.device.destroyImageView(v, null);
    self.swapchain_views.clearRetainingCapacity();
    // destroy old swapchain
    self.device.destroySwapchainKHR(self.swapchain, null);

    // store
    self.swapchain_views.appendSliceAssumeCapacity(views.items);
    self.swapchain = swapchain;
}

pub fn buildPipeline(self: *VulkanContext, stage: Stage, code: []const u32) !void {
    const module = try self.device.createShaderModule(&.{
        .code_size = 4 * code.len,
        .p_code = @ptrCast(code),
    }, null);
    defer self.device.destroyShaderModule(module, null);

    const set_layout_info = &stage.getNamedStatic(shader_layout.set_layout_infos);
    const set_layout = try self.device.createDescriptorSetLayout(set_layout_info, null);
    errdefer self.device.destroyDescriptorSetLayout(set_layout, null);

    const pipeline_layout = try self.device.createPipelineLayout(&.{
        .set_layout_count = 1,
        .p_set_layouts = &.{set_layout}
    }, null);
    errdefer self.device.destroyPipelineLayout(pipeline_layout, null);

    var pipeline: vk.Pipeline = .null_handle;
    _ = try self.device.createComputePipelines(.null_handle, 1, &.{ vk.ComputePipelineCreateInfo {
        .stage = .{
            .stage = .{ .compute_bit = true },
            .module = module,
            .p_name = "main",
        },
        .layout = pipeline_layout,
        .base_pipeline_index = 0,
    } }, null, @ptrCast(&pipeline));

    self.set_layouts[@intFromEnum(stage)] = set_layout;
    self.pipeline_layouts[@intFromEnum(stage)] = pipeline_layout;
    self.pipelines[@intFromEnum(stage)] = pipeline;
}
