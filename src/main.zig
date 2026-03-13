const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const Arguments = @import("Arguments.zig");
const helper = @import("helper.zig");
const VulkanContext = @import("VulkanContext.zig");
const shader_layout = @import("shader_layout.zig");
const math = @import("math.zig");
const Controller = @import("Controller.zig");


pub const std_options: std.Options = .{
    .logFn = helper.logger,
    .fmt_max_depth = 10,
};

pub fn main() !void {
    try helper.init();
    defer helper.deinit();

    var args: Arguments = try .init();
    defer args.deinit();
    try args.load(false);

    if (!glfw.init()) return error.FaildToInitGlfw;
    defer glfw.terminate();

    var controller: Controller = try .init();
    defer controller.deinit();
    controller.initCamera(.{
        .position = .{0, 0, 0},
        .direction = .{0.2, 1, 0.1},
        .view_up = .{0, 0, 1},
        .fov_v = 90,
    });

    var vk_ctx: VulkanContext = try .init(&controller);
    defer vk_ctx.deinit();

    try buildPipelines(&vk_ctx, args.slangc.value, args.shader_folder.value);

    if (helper.is_debug) std.log.info("entering main loop...", .{});
    defer if (helper.is_debug) std.log.info("main loop exited.", .{});
    while (!vk_ctx.shouldExit()) {
        glfw.pollEvents();

        if (vk_ctx.shouldRecreateSwapchain()) {
            if (helper.is_debug) std.log.info("recreating swapchain...", .{});
            try vk_ctx.recreateSwapchain();
            if (helper.is_debug) std.log.info("swapchain recreated.", .{});
        }

        var may_resources = try vk_ctx.acquireFrame();
        if (may_resources) |*resources| {

            const mouse_move = vk_ctx.glfw_callback.takeMouseMove();
            if (mouse_move.x != 0 or mouse_move.y != 0) {
                controller.rotateCamera(mouse_move, 0.002);
            }

            try resources.beginSettingUniforms();
            resources.setUniform(.init_ray, .{
                .camera = controller.camera,
            });
            resources.endSettingUniforms();

            try resources.drawFrame(.{});
        }
    }
}

const base_shaders = struct {
    pub const utils: []const u8 = @embedFile("shaders/utils.slang");
    pub const init_ray: []const u8 = @embedFile("shaders/init_ray.slang");
    pub const render_ray: []const u8 = @embedFile("shaders/render_ray.slang");
};

fn compileSlangShader(cwd: if (helper.is_windows) []const u8 else std.fs.Dir, slangc: []const u8, stage: shader_layout.Stage, out: []const u8) !void {
    const in = try std.fmt.allocPrint(helper.allocator, "{s}.slang", .{@tagName(stage)});
    defer helper.allocator.free(in);

    cwd.access(in, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            cwd.access("utils.slang", .{}) catch |err2| switch (err2) {
                error.FileNotFound => {
                    const utils_slang = try cwd.createFile("utils.slang", .{});
                    defer utils_slang.close();
                    var writer = utils_slang.writer(&.{});
                    try writer.interface.writeAll(base_shaders.utils);
                    try writer.interface.flush();
                },
                else => return err2,
            };

            const slang = try cwd.createFile(in, .{});
            defer slang.close();
            var writer = slang.writer(&.{});
            try writer.interface.writeAll(stage.getNamedStatic(base_shaders));
            try writer.interface.flush();
        },
        else => return err,
    };

    var args = [_][]const u8 {
        "<<slangc>>", "<<in>>",
        "-o", "<<out>>",
        "-target", "spirv",
        "-profile", "spirv_1_4",
        "-emit-spirv-directly",
        "-fvk-use-entrypoint-name",
        "-entry", "main",
    };

    args[0] = slangc;
    args[1] = in;
    args[3] = out;
    var process: std.process.Child = .init(&args, helper.allocator);
    if (helper.is_windows) {
        process.cwd = cwd;
    } else {
        process.cwd_dir = cwd;
    }

    const shader_compilation = "shader compilation";
    std.log.info("starting {s}:", .{shader_compilation});
    for (args) |arg| std.debug.print("{s} ", .{arg});
    std.debug.print("\n", .{});

    switch (try process.spawnAndWait()) {
        .Exited => |code| {
            if (code == 0) {
                std.log.info("{s} success", .{shader_compilation});
                return;
            }
            std.log.err("{s} exited with {d}", .{shader_compilation, code});
        },
        .Signal => |code| std.log.err("{s} signal with {d}", .{shader_compilation, code}),
        .Stopped => |code| std.log.err("{s} stopped with {d}", .{shader_compilation, code}),
        .Unknown => |code| std.log.err("{s}? code: {d}", .{shader_compilation, code}),
    }
    return error.FailedToCompileShader;
}

fn readShaderCode(file_path: []const u8) ![]align(4) const u8 {
    const file = try helper.cwd.openFile(file_path, .{});
    defer file.close();

    const size = (try file.stat()).size;
    if (size == 0 or size % 4 != 0) {
        std.log.err("spirv shader code must align in 4 bytes, current size: {d}", .{size});
        return error.CorruptedShaderCode;
    }

    const code = try helper.allocator.alignedAlloc(u8, .@"4", size);
    errdefer helper.allocator.free(code);
    var reader = file.reader(&.{});
    try reader.interface.readSliceAll(code);

    return code;
}

fn buildPipelines(vk_ctx: *VulkanContext, slangc: []const u8, shader_folder: ?[]const u8) !void {
    var shader_dir = if (shader_folder) |f| blk: {
        break :blk helper.cwd.openDir(f, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                try helper.cwd.makePath(f);
                break :blk try helper.cwd.openDir(f, .{});
            },
            else => return err,
        };
    } else helper.cwd;
    defer if (shader_folder != null) shader_dir.close();

    for (shader_layout.Stage.all) |stage| {
        const spv_file_name = try std.fmt.allocPrint(helper.allocator, "{s}.spv", .{@tagName(stage)});
        defer helper.allocator.free(spv_file_name);

        const spv_file = shader_dir.openFile(spv_file_name, .{}) catch |err| switch (err) {
            error.FileNotFound => blk: {
                const compile_cwd = if (helper.is_windows) shader_folder else shader_dir;
                try compileSlangShader(compile_cwd, slangc, stage, spv_file_name);
                break :blk try shader_dir.openFile(spv_file_name, .{});
            },
            else => return err,
        };
        defer spv_file.close();
        var reader = spv_file.reader(&.{});

        const stat = try spv_file.stat();
        const code = try helper.allocator.alloc(u32, stat.size / 4);
        defer helper.allocator.free(code);
        try reader.interface.readSliceAll(std.mem.sliceAsBytes(code));

        try vk_ctx.buildPipeline(stage, code);
    }
}
