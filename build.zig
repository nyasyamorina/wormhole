const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    //const vulkan_dll_name = if (target.result.os.tag == .windows) "vulkan-1" else "vulkan";

    const nyazrc = b.dependency("nyazrc", .{
        .optimize = optimize,
        .target = target,
    });
    const rc = nyazrc.module("nyazrc");

    const vk_hdrs = b.dependency("vk_hdrs", .{});
    const vk_xml = vk_hdrs.path("registry/vk.xml");
    const vulkan_zig = b.dependency("vulkan_zig", .{
        .registry = vk_xml,
        .optimize = optimize,
        .target = target,
    });
    const vk = vulkan_zig.module("vulkan-zig");

    const nyazglfw = b.dependency("nyazglfw", .{
        .optimize = optimize,
        .target = target,
    });
    const glfw = nyazglfw.module("glfw");

    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
        .link_libc = true,
        .imports = &.{
            .{ .name = "vulkan-zig", .module = vk },
            .{ .name = "glfw", .module = glfw },
            .{ .name = "nyazrc", .module = rc },
        },
    });
    //main_module.linkSystemLibrary(vulkan_dll_name, .{});
    main_module.linkSystemLibrary("glfw3", .{});

    b.installArtifact(b.addExecutable(.{
        .name = "wormhole",
        .root_module = main_module,
        .use_llvm = true, // for lldb debug
    }));


    const check_step = b.step("check", "");
    check_step.dependOn(&b.addExecutable(.{
        .name = "",
        .root_module = main_module,
    }).step);
}
