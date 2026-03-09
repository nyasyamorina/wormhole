const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const helper = @import("helper.zig");


window: *glfw.Window,
instance: vk.InstanceProxy,
debug_messenger: vk.DebugUtilsMessengerEXT,
surface: vk.SurfaceKHR,
physical_device: vk.PhysicalDevice,
device: vk.DeviceProxy,
queue: vk.QueueProxy,
swapchain_info: vk.SwapchainCreateInfoKHR,
swapchain: vk.SwapchainKHR = .null_handle,
outdated_swapchain: bool = true,
swapchain_views: std.ArrayList(vk.ImageView) = .empty,
command_pool: vk.CommandPool,


const VulkanContext = @This();
const log = std.log.scoped(.VulkanContext);

var instance_wrapper: vk.InstanceWrapper = .{ .dispatch = .{} };
var device_wrapper: vk.DeviceWrapper = .{ .dispatch = .{} };

pub fn init() !VulkanContext {
    const window = try createWindow();
    errdefer window.destroy();

    const instance = try createInstance(helper.allocator);
    errdefer helper.allocator.destroy(instance.wrapper);
    errdefer instance.destroyInstance(null);

    const debug_messenger = try createDebugMessenger(instance);
    errdefer instance.destroyDebugUtilsMessengerEXT(debug_messenger, null);

    const surface = try createSurface(instance, window);
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

    const physical_device, const queue_family = try pickPhysicalDevice(helper.allocator, instance, surface, target_features, &target_extensions);

    const device = try createDevice(instance, physical_device, queue_family, target_features, &target_extensions);
    errdefer helper.allocator.destroy(device.wrapper);
    errdefer device.destroyDevice(null);

    const queue = getQueue(device, queue_family);
    const swapchain_info = try getSwapchainInfo(helper.allocator, instance, physical_device, window, surface);

    const command_pool = try createCommandPool(device, queue_family);
    errdefer device.destroyCommandPool(command_pool, null);

    return .{
        .window = window,
        .instance = instance,
        .debug_messenger = debug_messenger,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .queue = queue,
        .swapchain_info = swapchain_info,
        .command_pool = command_pool,
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
}


fn createWindow() !*glfw.Window {
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

fn createInstance(allocator: std.mem.Allocator) !vk.InstanceProxy {
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

fn createDebugMessenger(instance: vk.InstanceProxy) !vk.DebugUtilsMessengerEXT {
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


fn createSurface(instance: vk.InstanceProxy, window: *glfw.Window) !vk.SurfaceKHR {
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

fn pickPhysicalDevice(allocator: std.mem.Allocator, instance: vk.InstanceProxy, surface: vk.SurfaceKHR, target_features: anytype, target_extensions: []const [*:0]const u8) !struct {vk.PhysicalDevice, u32} {
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

        const queue_family = try findGeneralQueueFamily(allocator, instance, p, surface) orelse continue;

        return .{p, queue_family};
    } else return error.SuitablePhysicalDeviceNotFound;
}

fn findGeneralQueueFamily(allocator: std.mem.Allocator, instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice, surface: vk.SurfaceKHR) !?u32 {
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

fn createDevice(instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice, queue_family: u32, target_features: anytype, target_extensions: []const [*:0]const u8) !vk.DeviceProxy {
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

fn getQueue(device: vk.DeviceProxy, queue_family: u32) vk.QueueProxy {
    const handle = device.getDeviceQueue(queue_family, 0);
    return .init(handle, device.wrapper);
}


fn getSwapchainInfo(allocator: std.mem.Allocator, instance: vk.InstanceProxy, physical_device: vk.PhysicalDevice, window: *glfw.Window, surface: vk.SurfaceKHR) !vk.SwapchainCreateInfoKHR {
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

fn recreateSwapchain(allocator: std.mem.Allocator, device: vk.DeviceProxy, info: *vk.SwapchainCreateInfoKHR, old: vk.SwapchainKHR, swapchain_views: *std.ArrayList(vk.ImageView)) vk.SwapchainKHR {
    // create new swachain from old one
    info.old_swapchain = old;
    const handle = try device.createSwapchainKHR(&info, null);
    errdefer device.destroySwapchainKHR(handle, null);

    // get swapchain images
    const images = try device.getSwapchainImagesAllocKHR(handle, allocator);
    defer allocator.free(images);
    try swapchain_views.ensureTotalCapacity(allocator, images.len);
    // create new swapchain image views
    var views: std.ArrayList(vk.ImageView) = try .initCapacity(allocator, images.len);
    defer views.deinit(allocator);
    errdefer for (views) |v| device.destroyImageView(v, null);
    for (images) |i| views.appendAssumeCapacity(try device.createImageView(&.{
        .image = i,
        .format = info.image_format,
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
    }, null));

    // destroy old swapchain image views
    for (swapchain_views.items) |v| device.destroyImageView(v, null);
    swapchain_views.clearRetainingCapacity();
    // destroy old swapchain
    device.destroySwapchainKHR(old, null);
    // return
    swapchain_views.appendSliceAssumeCapacity(views.items);
    return handle;
}


fn createCommandPool(device: vk.DeviceProxy, queue_family: u32) !vk.CommandPool {
    return device.createCommandPool(&.{
        .queue_family_index = queue_family,
    }, null);
}

fn createCommandBuffer(device: vk.DeviceProxy, command_pool: vk.CommandPool) !vk.CommandBufferProxy {
    var handles: [1]vk.CommandBuffer = undefined;
    try device.allocateCommandBuffers(&.{
        .level = .primary,
        .command_pool = command_pool,
        .command_buffer_count = 1,
    }, &handles);
    return .init(handles[0], device.wrapper);
}
