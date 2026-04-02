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

    if (!glfw.init()) {
        const result = glfw.getError();
        std.log.scoped(.glfw).err("failed to initialize glfw: ({t}) {s}", .{result.code, result.description orelse ""});
        return error.FaildToInitGlfw;
    }
    defer glfw.terminate();

    var controller: Controller = .{
        .camera = .init(.{
            .direction = .{0, 1, 0},
            .view_up = .{0, 0, 1},
            .fov_v = 60,
        }),
        .position = .{0, 0, 0, 0},
        .velocity = .{0, 0, 0},
        .thrust = 0.1,
    };

    var vk_ctx: VulkanContext = try .init(&controller);
    defer vk_ctx.deinit();

    try buildPipelines(&vk_ctx, args.slangc.value, args.shader_folder.value);

    var print_state_failed = false;
    var last_print_state_time = vk_ctx.frame_timestamp;
    helper.stdout.interface.print("\nstate:\n\n\n\n\n", .{}) catch {};

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
            const dt: f32 = @floatCast(@as(f64, @floatFromInt(resources.prev_frame_time)) / std.time.ns_per_s);

            const mouse_move = vk_ctx.glfw_callback.takeMouseMove();
            if (mouse_move[0] != 0 or mouse_move[1] != 0) {
                controller.camera.rotate(mouse_move, 0.002);
            }

            const scroll = vk_ctx.glfw_callback.takeScroll();
            if (scroll != 0) {
                controller.changeThrust(scroll);
            }

            const movement = vk_ctx.glfw_callback.takeMovement();
            if (movement[0] != 0 or movement[1] != 0 or movement[2] != 0) {
                controller.accelerate(movement, dt);
            }

            controller.step(dt);

            if (!print_state_failed and vk_ctx.frame_timestamp - last_print_state_time >= std.time.ns_per_s / 2) {
                if (controller.printState()) {
                    last_print_state_time = vk_ctx.frame_timestamp;
                } else |err| {
                    std.log.warn("failed to print state: {t}", .{err});
                    print_state_failed = true;
                }
            }

            try resources.beginSettingUniforms();
            resources.uniform(.init_ray).* = .{
                .camera = controller.camera.into(),
                .position = controller.position,
                .speed = controller.velocity,
            };
            resources.endSettingUniforms();

            try resources.drawFrame(.{});
        }
    }
}

const base_shaders = struct {
    pub const utils: []const u8 = @embedFile("utils.slang.xz");
    pub const init_ray: []const u8 = @embedFile("init_ray.slang.xz");
    pub const render_ray: []const u8 = @embedFile("render_ray.slang.xz");
};

// null stage for `utils.slang`
fn writeSlangShader(cwd: std.fs.Dir, name: []const u8, stage: ?shader_layout.Stage) !void {
    std.log.debug("extracting shader file {s}", .{name});
    const xz_data = if (stage) |s| s.getNamedStatic(base_shaders) else base_shaders.utils;

    const file = try cwd.createFile(name, .{});
    defer file.close();

    const write_buf = try helper.allocator.alloc(u8, 4096);
    defer helper.allocator.free(write_buf);
    var writer = file.writer(write_buf);

    var xz_reader = std.Io.Reader.fixed(xz_data);
    const old_xz_reader: std.Io.GenericReader(*std.Io.Reader, std.Io.Reader.Error, std.Io.Reader.readSliceShort) = .{ .context = &xz_reader };
    var decompresser = try std.compress.xz.decompress(helper.allocator, old_xz_reader);
    defer decompresser.deinit();

    const old_reader = decompresser.reader();
    var reader = old_reader.adaptToNewApi(&.{});

    _ = try reader.new_interface.streamRemaining(&writer.interface);
    try writer.interface.flush();
}

fn compileSlangShader(cwd: if (helper.is_windows) []const u8 else std.fs.Dir, slangc: []const u8, stage: shader_layout.Stage, out: []const u8) !void {
    const in = try std.fmt.allocPrint(helper.allocator, "{s}.slang", .{@tagName(stage)});
    defer helper.allocator.free(in);

    const cwd_dir = if (helper.is_windows) try helper.cwd.openDir(cwd, .{}) else cwd;

    cwd_dir.access(in, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            cwd_dir.access("utils.slang", .{}) catch |err2| switch (err2) {
                error.FileNotFound => try writeSlangShader(cwd_dir, "utils.slang", null),
                else => return err2,
            };
            try writeSlangShader(cwd_dir, in, stage);
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
    for (args) |arg| helper.stdout.interface.print("{s} ", .{arg}) catch {};
    helper.stdout.interface.print("\n", .{}) catch {};
    helper.stdout.interface.flush() catch {};

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
        std.log.info("building pipeline {s}", .{@tagName(stage)});
        const spv_file_name = try std.fmt.allocPrint(helper.allocator, "{s}.spv", .{@tagName(stage)});
        defer helper.allocator.free(spv_file_name);

        const spv_file = shader_dir.openFile(spv_file_name, .{}) catch |err| switch (err) {
            error.FileNotFound => blk: {
                const compile_cwd = if (helper.is_windows) shader_folder orelse "" else shader_dir;
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
