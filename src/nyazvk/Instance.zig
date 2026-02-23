const builtin = @import("builtin");
const std = @import("std");
const nyazrc = @import("nyazrc");
const vk = @import("vulkan-zig");

const nyazvk = @import("nyazvk.zig");
const utils = @import("utils.zig");


inner: nyazrc.Rc(Inner),


const Instance = @This();

const Inner = struct {
    handle: vk.Instance,
    wrapper: vk.InstanceWrapper,
    messenger: vk.DebugUtilsMessengerEXT,
};

pub const DebugMessengerCreateInfo = struct {
    message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
    message_type: vk.DebugUtilsMessageTypeFlagsEXT,
    callback: vk.PfnDebugUtilsMessengerCallbackEXT = defaultCallback,
    user_data: ?*anyopaque = null,

    pub const default: DebugMessengerCreateInfo = .{
        .message_severity = .{
            .error_bit_ext = true,
            .warning_bit_ext = true,
            .info_bit_ext = false,
            .verbose_bit_ext = false,
        },
        .message_type = .{
            .general_bit_ext = true,
            .validation_bit_ext = true,
            .performance_bit_ext = true,
            .device_address_binding_bit_ext = false,
        },
    };

    pub fn to(self: DebugMessengerCreateInfo) vk.DebugUtilsMessengerCreateInfoEXT {
        return .{
            .message_severity = self.message_severity,
            .message_type = self.message_type,
            .pfn_user_callback = self.callback,
            .p_user_data = self.user_data,
        };
    }

    fn defaultCallback(
        m_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
        m_types: vk.DebugUtilsMessageTypeFlagsEXT,
        callback_data: *const vk.DebugUtilsMessengerCallbackDataEXT,
        _: ?*anyopaque,
    ) callconv(vk.vulkan_call_conv) vk.Bool32 {
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

        const log = std.log.scoped(.debug_utils);
        switch (level) {
            .err => log.err(log_format, log_args),
            .warn => log.warn(log_format, log_args),
            .info => log.info(log_format, log_args),
            .debug => log.debug(log_format, log_args),
        }

        return .false;
    }
};

pub const CreateInfo = struct {
    flags: vk.InstanceCreateFlags = .{},
    application_info: ?*const vk.ApplicationInfo = null,
    enabled_layers: EnabledLayers = .empty,
    enabled_extensions: EnabledExtensions = .empty,
    debug_utils_info: ?*const DebugMessengerCreateInfo = if (builtin.mode == .Debug) &.default else null,
    check: bool = true,

    pub const EnabledLayers = union(enum) {
        layers: []const [*:0]const u8,
        all: void,

        pub const empty: EnabledLayers = .{ .layers = &.{} };

        pub const CollectAllocError = vk.BaseWrapper.EnumerateInstanceLayerPropertiesAllocError;
        pub fn collectAlloc(self: EnabledLayers, allocator: std.mem.Allocator, base: vk.BaseWrapper, enable_validation: bool) CollectAllocError![]const [*:0]const u8 {
            switch (self) {
                .layers => |layers| {
                    var extra_buf: [1][*:0]const u8 = undefined;
                    var extras: std.ArrayList([*:0]const u8) = .initBuffer(&extra_buf);

                    if (enable_validation) {
                        if (!utils.containName(layers, nyazvk.layers.khronos_validation)) {
                            extras.appendAssumeCapacity(nyazvk.layers.khronos_validation);
                        }
                    }

                    return std.mem.concat(allocator, [*:0]const u8, &.{layers, extras.items});
                },
                .all => {
                    const supported_layers = try base.enumerateInstanceLayerPropertiesAlloc(allocator);
                    defer allocator.free(supported_layers);

                    const layers = try allocator.alloc([*:0]const u8, supported_layers.len);
                    errdefer allocator.free(layers);

                    for (supported_layers, layers) |layer, *name| name.* = @ptrCast(&layer.layer_name);
                    return layers;
                },
            }
        }
    };

    pub const EnabledExtensions = union(enum) {
        extensions: []const [*:0]const u8,
        all: void,

        pub const empty: EnabledExtensions = .{ .extensions = &.{} };

        pub const CollectAllocError = vk.BaseWrapper.EnumerateInstanceExtensionPropertiesAllocError || vk.BaseWrapper.EnumerateInstanceVersionError;
        pub fn collectAlloc(self: EnabledExtensions, allocator: std.mem.Allocator, base: vk.BaseWrapper, enable_validation: bool) CollectAllocError![]const [*:0]const u8 {
            switch (self) {
                .extensions => |extensions| {
                    var extra_buf: [2][*:0]const u8 = undefined;
                    var extras: std.ArrayList([*:0]const u8) = .initBuffer(&extra_buf);

                    if (enable_validation) {
                        if (!utils.containName(extensions, vk.extensions.ext_debug_utils.name)) {
                            extras.appendAssumeCapacity(vk.extensions.ext_debug_utils.name);
                        }
                    }
                    if (builtin.os.tag == .macos) {
                        const target_version: u32 = comptime @bitCast(vk.makeApiVersion(0, 1, 3, 216));
                        if (try base.enumerateInstanceVersion() >= target_version and !utils.containName(extensions, vk.extensions.khr_portability_enumeration.name)) {
                            extras.appendAssumeCapacity(vk.extensions.khr_portability_enumeration.name);
                        }
                    }

                    return std.mem.concat(allocator, [*:0]const u8, &.{extensions, extras.items});
                },
                .all => {
                    const supported_extensions = try base.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
                    defer allocator.free(supported_extensions);

                    const extensions = try allocator.alloc([*:0]const u8, supported_extensions.len);
                    errdefer allocator.free(extensions);

                    for (supported_extensions, extensions) |extension, *name| name.* = @ptrCast(&extension.extension_name);
                    return extensions;
                },
            }
        }
    };
};

pub const InitError = error {
    NotSupportAllLayers,
    NotSupportAllExtensions,
}   || CheckLayersSupportError
    || CheckExtensionsSupportError
    || vk.BaseWrapper.CreateInstanceError;
pub fn init(allocator: std.mem.Allocator, info: CreateInfo, loader: vk.PfnGetInstanceProcAddr) InitError!Instance {
    const base: vk.BaseWrapper = .load(@as(vk.PfnGetInstanceProcAddr, loader));

    const debug_info = if (info.debug_utils_info) |i| &i.to() else null;
    const enable_validation = debug_info != null;

    const layers = try info.enabled_layers.collectAlloc(allocator, base, enable_validation);
    defer allocator.free(layers);
    if (info.check and info.enabled_layers != .all and !try checkLayersSupport(allocator, base, layers, true)) return InitError.NotSupportAllLayers;

    const extensions = try info.enabled_extensions.collectAlloc(allocator, base, enable_validation);
    defer allocator.free(extensions);
    if (info.check and info.enabled_extensions != .all and !try checkExtensionsSupport(allocator, base, extensions, true)) return InitError.NotSupportAllExtensions;

    const handle = try base.createInstance(&.{
        .p_next = debug_info,
        .flags = info.flags,
        .p_application_info = info.application_info,
        .enabled_layer_count = @intCast(layers.len),
        .pp_enabled_layer_names = layers.ptr,
        .enabled_extension_count = @intCast(extensions.len),
        .pp_enabled_extension_names = extensions.ptr,
    }, null);
    const wrapper: vk.InstanceWrapper = .load(handle, base.dispatch.vkGetInstanceProcAddr.?);
    errdefer wrapper.destroyInstance(handle, null);

    const messenger: vk.DebugUtilsMessengerEXT = if (debug_info) |i|
        try wrapper.createDebugUtilsMessengerEXT(handle, i, null)
    else .null_handle;
    errdefer if (messenger != .null_handle) wrapper.destroyDebugUtilsMessengerEXT(handle, messenger, null);

    return .{ .inner = try .init(allocator, .{
        .handle = handle,
        .wrapper = wrapper,
        .messenger = messenger,
    })};
}

pub fn clone(self: Instance) Instance {
    return .{ .inner = self.inner.clone() };
}

pub fn deinit(self: Instance, allocator: std.mem.Allocator) void {
    if (self.inner.deinit(allocator)) |inner| {
        if (inner.messenger != .null_handle) inner.wrapper.destroyDebugUtilsMessengerEXT(inner.handle, inner.messenger, null);
        inner.wrapper.destroyInstance(inner.handle, null);
    }
}

pub const CheckLayersSupportError = vk.BaseWrapper.EnumerateInstanceLayerPropertiesAllocError;
pub fn checkLayersSupport(allocator: std.mem.Allocator, base: vk.BaseWrapper, layers: []const [*:0]const u8, warn: bool) CheckLayersSupportError!bool {
    if (layers.len == 0) return true;

    const supported_layers = try base.enumerateInstanceLayerPropertiesAlloc(allocator);
    defer allocator.free(supported_layers);

    var find_all = true;
    for (layers) |target| {
        for (supported_layers) |layer| {
            if (std.mem.orderZ(u8, @ptrCast(&layer.layer_name), target) == .eq) break;
        } else {
            if (warn) nyazvk.log.warn("instance layer \"{s}\" not supported", .{target});
            find_all = false;
        }
    }

    return find_all;
}

pub const CheckExtensionsSupportError = vk.BaseWrapper.EnumerateInstanceExtensionPropertiesAllocError;
pub fn checkExtensionsSupport(allocator: std.mem.Allocator, base: vk.BaseWrapper, extensions: []const [*:0]const u8, warn: bool) CheckExtensionsSupportError!bool {
    if (extensions.len == 0) return true;

    const supported_extensions = try base.enumerateInstanceExtensionPropertiesAlloc(null, allocator);
    defer allocator.free(supported_extensions);

    var find_all = true;
    for (extensions) |target| {
        for (supported_extensions) |extension| {
            if (std.mem.orderZ(u8, @ptrCast(&extension.extension_name), target) == .eq) break;
        } else {
            if (warn) nyazvk.log.warn("instance extension \"{s}\" not supported", .{target});
            find_all = false;
        }
    }

    return find_all;
}
