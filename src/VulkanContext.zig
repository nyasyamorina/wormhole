const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");
const GlfwCallback = @import("GlfwCallback.zig");
const shader_layout = @import("shader_layout.zig");
const Stage = shader_layout.Stage;
const set_layout = shader_layout.set_layout;
const Controller = @import("Controller.zig");

pub const in_flight_count = 2;
const Fences = [in_flight_count]vk.Fence;
const Commands = [in_flight_count]vk.CommandBuffer;
const Semaphores = [in_flight_count]vk.Semaphore;
const UniformBuffers = [in_flight_count]vk.Buffer;
const UniformOffsets = [in_flight_count + 1]u64;
const StorageImages = [in_flight_count][set_layout.storage_count]vk.Image;
const StorageViews = [in_flight_count][set_layout.storage_count]vk.ImageView;
const SetLayouts = [set_layout.layout_count]vk.DescriptorSetLayout;
const Sets = [in_flight_count][set_layout.layout_count]vk.DescriptorSet;
const PipelineLayouts = [Stage.all.len]vk.PipelineLayout;
const Pipelines = [Stage.all.len]vk.Pipeline;


controller: *Controller,
glfw_callback: *GlfwCallback,
window: *glfw.Window,
instance: vk.InstanceProxy,
debug_messenger: vk.DebugUtilsMessengerEXT,
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
memory_type_fiinder: MemoryTypeFinder,
device: vk.DeviceProxy,
queue: vk.Queue,
swapchain_info: vk.SwapchainCreateInfoKHR,
command_pool: vk.CommandPool,
set_pool: vk.DescriptorPool,

swapchain_outdate: bool = true,
swapchain: vk.SwapchainKHR = .null_handle,
swapchain_images: std.ArrayList(vk.Image) = .empty,
swapchain_views: std.ArrayList(vk.ImageView) = .empty,
swapchain_semaphores: std.ArrayList(vk.Semaphore) = .empty,

next_frame: u1 = 0, // total 2 frames, one is on rendering, one is on recording
frame_timestamp: i128,
frame_fences: Fences,
acquiring_semaphore: vk.Semaphore,
computing_commands: Commands,
computing_semaphores: Semaphores,
rendering_commands: Commands,
rendering_semaphores: Semaphores,

uniform_memory: vk.DeviceMemory,
uniform_buffers: UniformBuffers,
uniform_offsets: UniformOffsets,

storage_extent: vk.Extent2D = .{ .width = 0, .height = 0 },
storage_size: u64 = 0,
storage_memory_type: u5 = undefined,
storage_memory: vk.DeviceMemory = .null_handle,
storage_images: StorageImages = std.mem.zeroes(StorageImages),
storage_views: StorageViews = std.mem.zeroes(StorageViews),

set_layouts: SetLayouts,
sets: Sets,

pipeline_layouts: PipelineLayouts,
pipelines: Pipelines = std.mem.zeroes(Pipelines),


const VulkanContext = @This();
const log = std.log.scoped(.VulkanContext);

var instance_wrapper: vk.InstanceWrapper = .{ .dispatch = .{} };
var device_wrapper: vk.DeviceWrapper = .{ .dispatch = .{} };

pub fn init(controller: *Controller) !VulkanContext {
    const glfw_callback = try helper.allocator.create(GlfwCallback);
    errdefer helper.allocator.destroy(glfw_callback);
    glfw_callback.* = .{};

    const window = try _createWindow();
    errdefer window.destroy();
    glfw_callback.setCallbacks(window);

    const instance = try _createInstance(helper.allocator);
    errdefer instance.destroyInstance(null);

    const debug_messenger = try _createDebugMessenger(instance);
    errdefer if (helper.is_debug) instance.destroyDebugUtilsMessengerEXT(debug_messenger, null);

    const surface = try _createSurface(instance, window);
    errdefer instance.destroySurfaceKHR(surface, null);

    var target_features: PhysicalDeviceFeatures(&.{vk.PhysicalDeviceSynchronization2Features}) = .{};
    target_features.set("synchronization_2", true);
    _ = target_features.link();

    const target_extensions = [_][*:0]const u8 {
        vk.extensions.khr_swapchain.name,
        vk.extensions.khr_spirv_1_4.name,
        vk.extensions.khr_synchronization_2.name,
    };

    const physical_device, const queue_family = try _pickPhysicalDevice(helper.allocator, instance, surface, target_features, &target_extensions);
    const memory_type_fiinder: MemoryTypeFinder = .init(instance, physical_device);

    const device = try _createDevice(instance, physical_device, queue_family, target_features, &target_extensions);
    errdefer device.destroyDevice(null);

    const queue = _getQueue(device, queue_family);
    const swapchain_info = try _getSwapchainInfo(helper.allocator, instance, physical_device, window, surface);
    controller.camera.setAspectRatio(swapchain_info.image_extent);

    const command_pool = try _createCommandPool(device, queue_family);
    errdefer device.destroyCommandPool(command_pool, null);
    const set_pool = try _createDescriptorPool(device);
    errdefer device.destroyDescriptorPool(set_pool, null);

    const frame_fences = try _createFences(device);
    errdefer for (frame_fences) |f| device.destroyFence(f, null);
    const acquiring_semephore = try device.createSemaphore(&.{}, null);
    errdefer device.destroySemaphore(acquiring_semephore, null);
    const computing_commands = try _createCommands(device, command_pool);
    const computing_semaphores = try _createSemaphores(device);
    errdefer for (computing_semaphores) |s| device.destroySemaphore(s, null);
    const rendering_commands = try _createCommands(device, command_pool);
    const rendering_semaphores = try _createSemaphores(device);
    errdefer for (rendering_semaphores) |s| device.destroySemaphore(s, null);

    const uniform_buffers = try _createUniformBuffers(device);
    errdefer for(uniform_buffers) |b| device.destroyBuffer(b, null);
    const uniform_offsets, const memory_type_mask = _calcuteUniformMemoryInfo(device, uniform_buffers);
    const memory_type = try memory_type_fiinder.find(memory_type_mask, .{ .host_visible_bit = true, .host_coherent_bit = true });
    const uniform_memory = try _allocAndBindUniformMemory(device, memory_type, uniform_buffers, uniform_offsets);
    errdefer device.freeMemory(uniform_memory, null);

    const set_layouts = try _createSetLayouts(device);
    errdefer for (set_layouts) |l| device.destroyDescriptorSetLayout(l, null);
    const sets = try _createSets(device, set_pool, set_layouts);
    _updateUniformDesriptor(device, uniform_buffers, sets);

    const pipeline_layouts = try _createPipelineLayouts(device, set_layouts);
    errdefer for (pipeline_layouts) |l| device.destroyPipelineLayout(l, null);

    return .{
        .controller = controller,
        .glfw_callback = glfw_callback,
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
        .set_pool = set_pool,

        .frame_timestamp = std.time.nanoTimestamp(),
        .frame_fences = frame_fences,
        .acquiring_semaphore = acquiring_semephore,
        .computing_semaphores = computing_semaphores,
        .computing_commands = computing_commands,
        .rendering_semaphores = rendering_semaphores,
        .rendering_commands = rendering_commands,

        .uniform_memory = uniform_memory,
        .uniform_buffers = uniform_buffers,
        .uniform_offsets = uniform_offsets,

        .set_layouts = set_layouts,
        .sets = sets,

        .pipeline_layouts = pipeline_layouts,
    };
}

pub fn deinit(self: *VulkanContext) void {
    defer helper.allocator.destroy(self.glfw_callback);
    defer self.window.destroy();
    defer self.instance.destroyInstance(null);
    defer if (helper.is_debug) self.instance.destroyDebugUtilsMessengerEXT(self.debug_messenger, null);
    defer self.instance.destroySurfaceKHR(self.surface, null);
    defer self.device.destroyDevice(null);
    defer self.device.destroyCommandPool(self.command_pool, null);
    defer self.device.destroyDescriptorPool(self.set_pool, null);

    defer self.device.destroySwapchainKHR(self.swapchain, null);
    defer self.swapchain_images.deinit(helper.allocator);
    defer self.swapchain_views.deinit(helper.allocator);
    defer for (self.swapchain_views.items) |v| self.device.destroyImageView(v, null);
    defer self.swapchain_semaphores.deinit(helper.allocator);
    defer for (self.swapchain_semaphores.items) |s| self.device.destroySemaphore(s, null);

    defer for (self.frame_fences) |f| self.device.destroyFence(f, null);
    defer self.device.destroySemaphore(self.acquiring_semaphore, null);
    defer for (self.computing_semaphores) |s| self.device.destroySemaphore(s, null);
    defer for (self.rendering_semaphores) |s| self.device.destroySemaphore(s, null);

    defer self.device.freeMemory(self.uniform_memory, null);
    defer for (self.uniform_buffers) |b| self.device.destroyBuffer(b, null);

    defer self.device.freeMemory(self.storage_memory, null);
    defer for (self.storage_images) |im1| for (im1) |im| self.device.destroyImage(im, null);
    defer for (self.storage_views) |v1| for (v1) |v| self.device.destroyImageView(v, null);

    defer for (self.set_layouts) |l| self.device.destroyDescriptorSetLayout(l, null);

    defer for (self.pipeline_layouts) |l| self.device.destroyPipelineLayout(l, null);
    defer for (self.pipelines) |p| self.device.destroyPipeline(p, null);

    self.device.deviceWaitIdle() catch |err| log.err("failed to wait device idle: {t}", .{err});
}

fn _aligAppendSize(size: u64, alignment: u64) u64 {
    std.debug.assert(std.math.isPowerOfTwo(alignment));
    return (alignment - (size & (alignment - 1))) & (alignment - 1);
}

fn _createWindow() !*glfw.Window {
    glfw.Window.Hint.set.clientApi(.no_api);
    glfw.Window.Hint.set.resizable(true);
    glfw.Window.Hint.set.transparentFramebuffer(false);

    const window = glfw.Window.create(.{ .width = 800, .height = 600 }, "wormhole", null, null) orelse {
        const result = glfw.getError();
        std.log.scoped(.glfw).err("failed to create window: ({t}) {s}", .{result.code, result.description orelse ""});
        return error.FaildToCreateWindow;
    };

    window.setInputMode(.cursor, .disable);
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

fn _getQueue(device: vk.DeviceProxy, queue_family: u32) vk.Queue {
    return device.getDeviceQueue(queue_family, 0);
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
    var choose_idx: ?usize = null;
    for (surface_formats, 0..) |format, idx| {
        if (format.format == .r8g8b8a8_unorm) {
            choose_idx = idx;
            if (format.color_space == .srgb_nonlinear_khr) break;
        }
    }
    const surface_format = surface_formats[choose_idx orelse return error.NoSuitableSurfaceFormat];

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
        .flags = .{ .reset_command_buffer_bit = true },
        .queue_family_index = queue_family,
    }, null);
}

fn _createCommands(device: vk.DeviceProxy, pool: vk.CommandPool) ![in_flight_count]vk.CommandBuffer {
    var commands = std.mem.zeroes([in_flight_count]vk.CommandBuffer);
    errdefer device.freeCommandBuffers(pool, commands.len, &commands);
    try device.allocateCommandBuffers(&.{
        .level = .primary,
        .command_pool = pool,
        .command_buffer_count = commands.len,
    }, &commands);
    return commands;
}

fn _createDescriptorPool(device: vk.DeviceProxy) !vk.DescriptorPool {
    const pool_sizes = [_]vk.DescriptorPoolSize {
        .{
            .type = .uniform_buffer,
            .descriptor_count = in_flight_count,
        },
        .{
            .type = .storage_image,
            .descriptor_count = in_flight_count * (set_layout.storage_count + 1),
        },
    };
    return device.createDescriptorPool(&.{
        .flags = .{ .free_descriptor_set_bit = true },
        .max_sets = in_flight_count * (set_layout.layout_count - 1 + Stage.all.len),
        .pool_size_count = pool_sizes.len,
        .p_pool_sizes = &pool_sizes,
    }, null);
}
fn _createSetLayouts(device: vk.DeviceProxy) !SetLayouts {
    var layouts = std.mem.zeroes(SetLayouts);
    errdefer for (layouts) |l| device.destroyDescriptorSetLayout(l, null);

    layouts[0] = try device.createDescriptorSetLayout(&shader_layout.set_layout.uniform, null);
    layouts[1] = try device.createDescriptorSetLayout(&shader_layout.set_layout.storage, null);
    layouts[2] = try device.createDescriptorSetLayout(&shader_layout.set_layout.surface, null);
    return layouts;
}
fn _createSets(device: vk.DeviceProxy, pool: vk.DescriptorPool, layouts: SetLayouts) !Sets {
    const set_count = in_flight_count * (set_layout.layout_count);

    var set_layouts: [in_flight_count]SetLayouts = undefined;
    @memset(&set_layouts, layouts);

    var sets = std.mem.zeroes(Sets);
    errdefer device.freeDescriptorSets(pool, set_count, @ptrCast(&sets)) catch {};
    try device.allocateDescriptorSets(&.{
        .descriptor_pool = pool,
        .descriptor_set_count = set_count,
        .p_set_layouts = @ptrCast(&set_layouts),
    }, @ptrCast(&sets));
    return sets;
}

fn _updateUniformDesriptor(device: vk.DeviceProxy, buffers: UniformBuffers, sets: Sets) void {
    var writes: [in_flight_count]vk.WriteDescriptorSet = undefined;
    for (0 .. in_flight_count) |f| {
        writes[f] = .{
            .descriptor_type = .uniform_buffer,
            .descriptor_count = 1,
            .p_buffer_info = &.{ .{
                .buffer = buffers[f],
                .offset = 0,
                .range = vk.WHOLE_SIZE,
            } },
            .dst_set = sets[f][0],
            .dst_binding = 0,
            .dst_array_element = 0,
            .p_image_info = undefined,
            .p_texel_buffer_view = undefined,
        };
    }

    device.updateDescriptorSets(writes.len, &writes, 0, null);
}
fn _updateStorageDescriptor(device: vk.DeviceProxy, views: StorageViews, sets: Sets) void {
    var infos: [in_flight_count][set_layout.storage_count]vk.DescriptorImageInfo = undefined;
    for (0 .. in_flight_count) |f| for (0 .. set_layout.storage_count) |im| {
        infos[f][im] = .{
            .sampler = .null_handle,
            .image_view = views[f][im],
            .image_layout = .general,
        };
    };

    var writes: [in_flight_count][set_layout.storage_count]vk.WriteDescriptorSet = undefined;
    for (0 .. in_flight_count) |f| for (0 .. set_layout.storage_count) |im| {
        writes[f][im] = .{
            .descriptor_type = .storage_image,
            .descriptor_count = 1,
            .p_image_info = infos[f][im .. im+1].ptr,
            .dst_set = sets[f][1],
            .dst_binding = @intCast(im),
            .dst_array_element = 0,
            .p_buffer_info = undefined,
            .p_texel_buffer_view = undefined,
        };
    };

    device.updateDescriptorSets(in_flight_count * set_layout.storage_count, @ptrCast(&writes), 0, null);
}
fn _updateSurfaceDescriptor(device: vk.DeviceProxy, view: vk.ImageView, set: vk.DescriptorSet) void {
    device.updateDescriptorSets(1, &.{ vk.WriteDescriptorSet {
        .descriptor_type = .storage_image,
        .descriptor_count = 1,
        .p_image_info = &.{ vk.DescriptorImageInfo {
            .sampler = .null_handle,
            .image_view = view,
            .image_layout = .general,
        } },
        .dst_set = set,
        .dst_binding = 0,
        .dst_array_element = 0,
        .p_buffer_info = undefined,
        .p_texel_buffer_view = undefined,
    } }, 0, null);
}

fn _createPipelineLayouts(device: vk.DeviceProxy, set_layouts: SetLayouts) !PipelineLayouts {
    var layouts = std.mem.zeroes([Stage.all.len]vk.PipelineLayout);
    errdefer for (layouts) |l| device.destroyPipelineLayout(l, null);

    var ps_layouts: SetLayouts = undefined;
    for (Stage.all) |stage| {
        const set_layout_indices = stage.getNamedStatic(shader_layout.pipeline_set_layout_indices);
        for (set_layout_indices, 0..) |layout_idx, idx| ps_layouts[idx] = set_layouts[layout_idx];

        layouts[@intFromEnum(stage)] = try device.createPipelineLayout(&.{
            .set_layout_count = @intCast(set_layout_indices.len),
            .p_set_layouts = &ps_layouts,
        }, null);
    }
    return layouts;
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

    pub fn find(self: MemoryTypeFinder, mask: u32, props: vk.MemoryPropertyFlags) !u5 {
        var idx: u6 = 0;
        var bit: u32 = 1;
        while (idx < self.count) : ({ idx += 1; bit <<= 1; }) {
            if (mask & bit != 0 and self.memory_type_flags[idx].contains(props)) {
                return @intCast(idx);
            }
        } else return error.NoSuitableMemoryType;
    }
};

fn _createUniformBuffers(device: vk.DeviceProxy) !UniformBuffers {
    var buffers = std.mem.zeroes(UniformBuffers);
    errdefer for (buffers) |b| device.destroyBuffer(b, null);

    for (0 .. in_flight_count) |f| {
        buffers[f] = try device.createBuffer(&.{
            .sharing_mode = .exclusive,
            .size = @sizeOf(shader_layout.Uniform),
            .usage = .{ .uniform_buffer_bit = true },
        }, null);
    }
    return buffers;
}
fn _calcuteUniformMemoryInfo(device: vk.DeviceProxy, buffers: UniformBuffers) struct {UniformOffsets, u32} {
    var offsets: UniformOffsets = undefined;
    var size: u64 = 0;
    var mask: u32 = std.math.maxInt(u32);

    for (0 .. in_flight_count) |f| {
        const mem_req = device.getBufferMemoryRequirements(buffers[f]);

        size += _aligAppendSize(size, mem_req.alignment);
        offsets[f] = size;

        size += mem_req.size;
        mask &= mem_req.memory_type_bits;
    }

    offsets[in_flight_count] = size;
    return .{offsets, mask};
}
fn _allocAndBindUniformMemory(device: vk.DeviceProxy, memory_type: u5, buffers: UniformBuffers, offsets: UniformOffsets) !vk.DeviceMemory {
    const memory = try device.allocateMemory(&.{
        .memory_type_index = memory_type,
        .allocation_size = offsets[in_flight_count],
    }, null);
    errdefer device.freeMemory(memory, null);

    for (buffers, offsets[0 .. in_flight_count]) |b, o| {
        try device.bindBufferMemory(b, memory, o);
    }

    return memory;
}

fn _createSemaphores(device: vk.DeviceProxy) !Semaphores {
    var semaphores = std.mem.zeroes(Semaphores);
    errdefer for (semaphores) |s| device.destroySemaphore(s, null);

    for (&semaphores) |*s| s.* = try device.createSemaphore(&.{}, null);
    return semaphores;
}
fn _createFences(device: vk.DeviceProxy) !Fences {
    var fences = std.mem.zeroes(Fences);
    errdefer for (fences) |f| device.destroyFence(f, null);

    for (&fences) |*f| f.* = try device.createFence(&.{
        .flags = .{ .signaled_bit = true },
    }, null);
    return fences;
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

fn _growthSemaphores(allocator: std.mem.Allocator, device: vk.DeviceProxy, semaphores: *std.ArrayList(vk.Semaphore), len: usize) !void {
    std.debug.assert(semaphores.items.len <= len);
    try semaphores.ensureTotalCapacity(allocator, len);
    for (0 .. len - semaphores.items.len) |_|{
        semaphores.appendAssumeCapacity(
            try device.createSemaphore(&.{}, null)
        );
    }
}
fn _shrinkSemaphores(device: vk.DeviceProxy, semaphores: *std.ArrayList(vk.Semaphore), len: usize) void {
    std.debug.assert(semaphores.items.len >= len);
    for (0 .. semaphores.items.len - len) |_| {
        device.destroySemaphore(semaphores.pop().?, null);
    }
}

fn _3dExtent(extent2d: vk.Extent2D) vk.Extent3D {
    return .{ .width = extent2d.width, .height = extent2d.height, .depth = 1 };
}


pub fn shouldRecreateSwapchain(self: VulkanContext) bool {
    return self.swapchain_outdate;
}
pub fn recreateSwapchain(self: *VulkanContext) !void {
    // create new swapchain
    self.swapchain_info.old_swapchain = self.swapchain;
    const swapchain = try self.device.createSwapchainKHR(&self.swapchain_info, null);
    errdefer self.device.destroySwapchainKHR(swapchain, null);

    // get swapchain images
    const images = try self.device.getSwapchainImagesAllocKHR(swapchain, helper.allocator);
    defer helper.allocator.free(images);
    try self.swapchain_images.ensureTotalCapacity(helper.allocator, images.len);
    try self.swapchain_views.ensureTotalCapacity(helper.allocator, images.len);
    // create new swapchain image views
    var views: std.ArrayList(vk.ImageView) = try .initCapacity(helper.allocator, images.len);
    defer views.deinit(helper.allocator);
    errdefer for (views.items) |v| self.device.destroyImageView(v, null);
    for (images) |i| views.appendAssumeCapacity(try _createImageView(self.device, i, self.swapchain_info.image_format));

    // growth swapchain semaphores
    const old_len = self.swapchain_semaphores.items.len;
    errdefer if (self.swapchain_semaphores.items.len > old_len) _shrinkSemaphores(self.device, &self.swapchain_semaphores, old_len);
    if (self.swapchain_semaphores.items.len < images.len) try _growthSemaphores(helper.allocator, self.device, &self.swapchain_semaphores, images.len);

    if (!std.meta.eql(self.swapchain_info.image_extent, self.storage_extent)) {
        // create new storage images and views
        var storage_images = std.mem.zeroes([in_flight_count][set_layout.storage_count]vk.Image);
        var offsets: [in_flight_count][set_layout.storage_count]u64 = undefined;
        errdefer for (storage_images) |im1| for (im1) |im| self.device.destroyImage(im, null);

        var mem_type_mask: u32 = std.math.maxInt(u32);
        var total_size: u64 = 0;
        for (0 .. in_flight_count) |f| for (0 .. set_layout.storage_count) |i| {
            storage_images[f][i] = try self.device.createImage(&.{
                .image_type = .@"2d",
                .format = .r32g32b32a32_sfloat,
                .extent = _3dExtent(self.swapchain_info.image_extent),
                .mip_levels = 1,
                .array_layers = 1,
                .samples = @bitCast(@as(vk.Flags, 1)),
                .tiling = .optimal,
                .usage = .{ .storage_bit = true },
                .sharing_mode = .exclusive,
                .initial_layout = .undefined,
            }, null);

            const mem_req = self.device.getImageMemoryRequirements(storage_images[f][i]);
            total_size += _aligAppendSize(total_size, mem_req.alignment);
            offsets[f][i] = total_size;
            total_size += mem_req.size;
            mem_type_mask &= mem_req.memory_type_bits;
        };

        var storage_views = std.mem.zeroes([in_flight_count][set_layout.storage_count]vk.ImageView);
        errdefer for (storage_views) |v1| for (v1) |v| self.device.destroyImageView(v, null);

        const realloc_memory = total_size > self.storage_size or mem_type_mask & (@as(u32, 1) << self.storage_memory_type) == 0;
        const storage_memory, const memory_type = if (realloc_memory) blk: {
            // alloc new storage memory
            const mem_type = try self.memory_type_fiinder.find(mem_type_mask, .{ .device_local_bit = true });

            const memory = try self.device.allocateMemory(&.{
                .memory_type_index = mem_type,
                .allocation_size = total_size,
            }, null);
            break :blk .{memory, mem_type};
        } else .{self.storage_memory, self.storage_memory_type};
        errdefer if (realloc_memory) self.device.freeMemory(storage_memory, null);

        // bind image memory and create new image views
        for (0 .. in_flight_count) |f| for (0 .. set_layout.storage_count) |i| {
            try self.device.bindImageMemory(storage_images[f][i], storage_memory, offsets[f][i]);
            storage_views[f][i] = try _createImageView(self.device, storage_images[f][i], .r32g32b32a32_sfloat);
        };

        // transite image layout
        {
            // create one-time command buffer
            var command: vk.CommandBufferProxy = .{ .handle = .null_handle, .wrapper = self.device.wrapper };
            try self.device.allocateCommandBuffers(&.{
                .command_pool = self.command_pool,
                .level = .primary,
                .command_buffer_count = 1,
            }, @ptrCast(&command.handle));
            defer self.device.freeCommandBuffers(self.command_pool, 1, @ptrCast(&command.handle));

            // record commands
            try command.beginCommandBuffer(&.{});
            for (storage_images) |im1| for (im1) |im| {
                command.pipelineBarrier2(&.{
                    .image_memory_barrier_count = 1,
                    .p_image_memory_barriers = &.{ vk.ImageMemoryBarrier2 {
                        .image = im,
                        .subresource_range = .{
                            .aspect_mask = .{ .color_bit = true },
                            .base_mip_level = 0,
                            .level_count = 1,
                            .base_array_layer = 0,
                            .layer_count = 1,
                        },

                        .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                        .src_stage_mask = .{ .top_of_pipe_bit = true },
                        .src_access_mask = .{},
                        .old_layout = .undefined,

                        .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                        .dst_stage_mask = .{ .compute_shader_bit = true },
                        .dst_access_mask = .{ .shader_write_bit = true },
                        .new_layout = .general,
                    } },
                });
            };
            try command.endCommandBuffer();

            // submit
            const queue: vk.QueueProxy = .{ .handle = self.queue, .wrapper = self.device.wrapper };
            try queue.submit(1, &.{ vk.SubmitInfo {
                .command_buffer_count = 1,
                .p_command_buffers = &.{command.handle},
            } }, .null_handle);

            try queue.waitIdle();
        }

        try self.device.deviceWaitIdle();
    //=//=//=// vvv No Error Context vvv

        if (realloc_memory) {
            // free old memory
            self.device.freeMemory(self.storage_memory, null);

            // store new memory
            self.storage_memory = storage_memory;
            self.storage_size = total_size;
            self.storage_memory_type = memory_type;
        }

        // destroy images and views
        for (self.storage_images) |im1| for (im1) |im| self.device.destroyImage(im, null);
        for (self.storage_views) |v1| for (v1) |v| self.device.destroyImageView(v, null);

        // store new storage images and views
        self.storage_extent = self.swapchain_info.image_extent;
        self.storage_images = storage_images;
        self.storage_views = storage_views;

        // update descriptor
        _updateStorageDescriptor(self.device, self.storage_views, self.sets);
    }

    // destroy extra swapchain semaphores
    if (self.swapchain_semaphores.items.len > images.len) _shrinkSemaphores(self.device, &self.swapchain_semaphores, images.len);
    // destroy old swapchain image views
    for (self.swapchain_views.items) |v| self.device.destroyImageView(v, null);
    self.swapchain_views.clearRetainingCapacity();
    self.swapchain_images.clearRetainingCapacity();
    // destroy old swapchain
    self.device.destroySwapchainKHR(self.swapchain, null);

    // store new swapchain and views
    self.swapchain_images.appendSliceAssumeCapacity(images);
    self.swapchain_views.appendSliceAssumeCapacity(views.items);
    self.swapchain = swapchain;
    self.swapchain_outdate = false;
}

pub fn buildPipeline(self: *VulkanContext, stage: Stage, code: []const u32) !void {
    const module = try self.device.createShaderModule(&.{
        .code_size = 4 * code.len,
        .p_code = @ptrCast(code),
    }, null);
    defer self.device.destroyShaderModule(module, null);

    var pipeline: vk.Pipeline = .null_handle;
    _ = try self.device.createComputePipelines(.null_handle, 1, &.{ vk.ComputePipelineCreateInfo {
        .stage = .{
            .stage = .{ .compute_bit = true },
            .module = module,
            .p_name = "main",
        },
        .layout = self.pipeline_layouts[@intFromEnum(stage)],
        .base_pipeline_index = 0,
    } }, null, @ptrCast(&pipeline));

    self.pipelines[@intFromEnum(stage)] = pipeline;
}


pub fn shouldExit(self: VulkanContext) bool {
    return self.window.shouldClose();
}


pub const FrameResouces = struct {
    swapchain: vk.SwapchainKHR,
    extent: vk.Extent2D,
    swapchain_index: u32,
    swapchain_image: vk.Image,
    swapchain_view: vk.ImageView,
    is_suboptimal: bool,
    swapchain_outdate: *bool,
    prev_frame_time: i128,

    device: vk.DeviceProxy,
    queue: vk.Queue,
    fence: vk.Fence,
    acquiring_semaphore: vk.Semaphore,
    computing_command: vk.CommandBuffer,
    computing_semaphore: vk.Semaphore,
    rendering_command: vk.CommandBuffer,
    rendering_semaphore: vk.Semaphore,

    uniform_range: [2]u64,
    uniform_memory: vk.DeviceMemory,
    uniform_buffer: vk.Buffer,

    sets: [set_layout.layout_count]vk.DescriptorSet,
    pipeline_layouts: PipelineLayouts,
    pipelines: Pipelines,

    pub fn setUniform(self: *FrameResouces, uniform: shader_layout.Uniform) !void {
        const data = try self.device.mapMemory(self.uniform_memory, self.uniform_range[0], self.uniform_range[1] - self.uniform_range[0], .{});
        const map: *shader_layout.Uniform = @ptrCast(@alignCast(data.?));
        map.* = uniform;
        self.device.unmapMemory(self.uniform_memory);
    }

    pub const DrawFrameInfo = struct {
        n_iter_call: usize,
    };

    pub fn drawFrame(self: FrameResouces, info: DrawFrameInfo) !void {
        _updateSurfaceDescriptor(self.device, self.swapchain_view, self.sets[self.sets.len - 1]);

        const queue: vk.QueueProxy = .{ .handle = self.queue, .wrapper = self.device.wrapper };
        const group_x = std.math.divCeil(u32, self.extent.width, 16) catch unreachable;
        const group_y = std.math.divCeil(u32, self.extent.height, 16) catch unreachable;

        const computing_command: vk.CommandBufferProxy = .{ .handle = self.computing_command, .wrapper = self.device.wrapper };
        const rendering_command: vk.CommandBufferProxy = .{ .handle = self.rendering_command, .wrapper = self.device.wrapper };

        _ = .{info};

        try computing_command.resetCommandBuffer(.{});
        try computing_command.beginCommandBuffer(&.{});
        { // init ray
            const stage = Stage.init_ray;
            const uniform_set = self.sets[0];
            const storage_set = self.sets[1];
            const set_count = comptime stage.getNamedStatic(shader_layout.pipeline_set_layout_indices).len;
            const pipeline_layout = self.pipeline_layouts[@intFromEnum(stage)];
            const pipeline = self.pipelines[@intFromEnum(stage)];

            computing_command.bindPipeline(.compute, pipeline);
            computing_command.bindDescriptorSets(
                .compute, pipeline_layout,
                0, set_count, &.{uniform_set, storage_set},
                0, null,
            );
            computing_command.dispatch(group_x, group_y, 1);
        }
        { // iter ray
            const stage = Stage.iter_ray;
            const uniform_set = self.sets[0];
            const storage_set = self.sets[1];
            const set_count = comptime stage.getNamedStatic(shader_layout.pipeline_set_layout_indices).len;
            const pipeline_layout = self.pipeline_layouts[@intFromEnum(stage)];
            const pipeline = self.pipelines[@intFromEnum(stage)];

            computing_command.bindPipeline(.compute, pipeline);
            computing_command.bindDescriptorSets(
                .compute, pipeline_layout,
                0, set_count, &.{uniform_set, storage_set},
                0, null,
            );
            for (0 .. info.n_iter_call) |_| computing_command.dispatch(group_x, group_y, 1);
        }
        try computing_command.endCommandBuffer();

        try rendering_command.resetCommandBuffer(.{});
        try rendering_command.beginCommandBuffer(&.{});
        { // render ray
            const stage = Stage.render_ray;
            const uniform_set = self.sets[0];
            const storage_set = self.sets[1];
            const surface_set = self.sets[2];
            const set_count = comptime stage.getNamedStatic(shader_layout.pipeline_set_layout_indices).len;
            const pipeline_layout = self.pipeline_layouts[@intFromEnum(stage)];
            const pipeline = self.pipelines[@intFromEnum(stage)];

            rendering_command.pipelineBarrier2(&.{
                .image_memory_barrier_count = 1,
                .p_image_memory_barriers = &.{ vk.ImageMemoryBarrier2 {
                    .image = self.swapchain_image,
                    .subresource_range = .{
                        .aspect_mask = .{ .color_bit = true },
                        .base_mip_level = 0,
                        .level_count = 1,
                        .base_array_layer = 0,
                        .layer_count = 1,
                    },

                    .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                    .src_stage_mask = .{ .top_of_pipe_bit = true },
                    .src_access_mask = .{},
                    .old_layout = .undefined,

                    .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                    .dst_stage_mask = .{ .compute_shader_bit = true },
                    .dst_access_mask = .{ .shader_write_bit = true },
                    .new_layout = .general,
                } },
            });

            rendering_command.bindPipeline(.compute, pipeline);
            rendering_command.bindDescriptorSets(
                .compute, pipeline_layout,
                0, set_count, &.{uniform_set, storage_set, surface_set},
                0, null,
            );
            rendering_command.dispatch(group_x, group_y, 1);

            rendering_command.pipelineBarrier2(&.{
                .image_memory_barrier_count = 1,
                .p_image_memory_barriers = &.{ vk.ImageMemoryBarrier2 {
                    .image = self.swapchain_image,
                    .subresource_range = .{
                        .aspect_mask = .{ .color_bit = true },
                        .base_mip_level = 0,
                        .level_count = 1,
                        .base_array_layer = 0,
                        .layer_count = 1,
                    },

                    .src_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                    .src_stage_mask = .{ .compute_shader_bit = true },
                    .src_access_mask = .{ .shader_write_bit = true },
                    .old_layout = .general,

                    .dst_queue_family_index = vk.QUEUE_FAMILY_IGNORED,
                    .dst_stage_mask = .{ .bottom_of_pipe_bit = true },
                    .dst_access_mask = .{},
                    .new_layout = .present_src_khr,
                } },
            });
        }
        try rendering_command.endCommandBuffer();

        try queue.submit(2, &.{
            vk.SubmitInfo {
                .command_buffer_count = 1,
                .p_command_buffers = &.{computing_command.handle},
                .signal_semaphore_count = 1,
                .p_signal_semaphores = @ptrCast(&self.computing_semaphore),
            },
            vk.SubmitInfo {
                .command_buffer_count = 1,
                .p_command_buffers = &.{rendering_command.handle},
                .wait_semaphore_count = 2,
                .p_wait_semaphores = &.{self.computing_semaphore, self.acquiring_semaphore},
                .p_wait_dst_stage_mask = &.{.{ .compute_shader_bit = true }, .{ .compute_shader_bit = true } },
                .signal_semaphore_count = 1,
                .p_signal_semaphores = @ptrCast(&self.rendering_semaphore),
            },
        }, self.fence);
        const present_result = queue.presentKHR(&.{
            .swapchain_count = 1,
            .p_swapchains = &.{self.swapchain},
            .p_image_indices = &.{self.swapchain_index},
            .wait_semaphore_count = 1,
            .p_wait_semaphores = @ptrCast(&self.rendering_semaphore),
        });

        if (present_result) |result| switch (result) {
            .success => {},
            .suboptimal_khr => self.swapchain_outdate.* = true,
            else => unreachable,
        } else |err| switch (err) {
            error.OutOfDateKHR => self.swapchain_outdate.* = true,
            else => return err,
        }
    }
};

pub fn acquireFrame(self: *VulkanContext) !?FrameResouces {
    // glfw callback
    if (self.glfw_callback.takeResizeInfo()) |extent| {
        self.swapchain_info.image_extent = extent;
        self.swapchain_outdate = true;
        self.controller.camera.setAspectRatio(extent);
        return null;
    }

    const fence = self.frame_fences[self.next_frame];

    var wait_count: usize = 0;
    const wait_time = std.time.ns_per_s;
    while (try self.device.waitForFences(1, &.{fence}, .true, wait_time) == .timeout) {
        wait_count += 1;
        log.warn("waiting for frame fence over {d}s", .{wait_count});
    }

    const result = self.device.acquireNextImageKHR(
        self.swapchain,
        std.math.maxInt(u64),
        self.acquiring_semaphore,
        .null_handle,
    ) catch |err| switch (err) {
        error.OutOfDateKHR => {
            self.swapchain_outdate = true;
            return null;
        },
        else => return err,
    };
    if (result.result == .not_ready) return null;

    try self.device.resetFences(1, &.{fence});

    const resources: FrameResouces = .{
        .swapchain = self.swapchain,
        .extent = self.storage_extent,
        .swapchain_index = result.image_index,
        .swapchain_image = self.swapchain_images.items[result.image_index],
        .swapchain_view = self.swapchain_views.items[result.image_index],
        .is_suboptimal = result.result == .suboptimal_khr,
        .swapchain_outdate = &self.swapchain_outdate,
        .prev_frame_time = blk: {
            const curr_time = std.time.nanoTimestamp();
            const dt = curr_time - self.frame_timestamp;
            self.frame_timestamp = curr_time;
            break :blk dt;
        },

        .device = self.device,
        .queue = self.queue,
        .fence = fence,
        .acquiring_semaphore = self.acquiring_semaphore,
        .computing_command = self.computing_commands[self.next_frame],
        .computing_semaphore = self.computing_semaphores[self.next_frame],
        .rendering_command = self.rendering_commands[self.next_frame],
        .rendering_semaphore = self.rendering_semaphores[self.next_frame],

        .uniform_range = .{self.uniform_offsets[self.next_frame], self.uniform_offsets[@as(u2, self.next_frame) + 1]},
        .uniform_memory = self.uniform_memory,
        .uniform_buffer = self.uniform_buffers[self.next_frame],

        .sets = self.sets[self.next_frame],
        .pipeline_layouts = self.pipeline_layouts,
        .pipelines = self.pipelines,
    };

    std.mem.swap(vk.Semaphore, &self.acquiring_semaphore, &self.swapchain_semaphores.items[result.image_index]);
    self.next_frame +%= 1;

    return resources;
}
