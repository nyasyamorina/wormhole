const std = @import("std");

pub fn build(b: *std.Build) !void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    //const vulkan_dll_name = if (target.result.os.tag == .windows) "vulkan-1" else "vulkan";

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
        },
    });
    //main_module.linkSystemLibrary(vulkan_dll_name, .{});
    if (target.result.os.tag == .windows) main_module.addLibraryPath(b.path("pack-stuff/windows"));
    main_module.linkSystemLibrary("glfw3", .{});
    try addCompressedShaders(b, main_module);

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


fn addCompressedShaders(b: *std.Build, module: *std.Build.Module) !void {
    var shader_dir = try b.path("src/shaders/").getPath3(b, null).openDir(".", .{ .iterate = true });
    defer shader_dir.close();

    var iter = shader_dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file) {
            const shader_path = try std.fs.path.join(b.allocator, &.{"src/shaders", entry.name});
            defer b.allocator.free(shader_path);

            // TODO use `std.compress.flate.Compress` when zig 0.16 is out
            const output_name = try std.fmt.allocPrint(b.allocator, "{s}.xz", .{entry.name});
            defer b.allocator.free(output_name);

            var xz = b.addSystemCommand(&.{ "xz", "-zkc9e" });
            xz.addFileArg(b.path(shader_path));
            module.addAnonymousImport(output_name, .{ .root_source_file = xz.captureStdOut() });
        }
    }
}
