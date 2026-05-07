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
    .fmt_max_depth = 10,
};

pub fn main(init: std.process.Init) !void {
    try helper.init(init.io);
    defer helper.deinit();

    var args: Arguments = try .init();
    defer args.deinit();
    try args.load(init.minimal.args, false);

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
                controller.camera.rotate(mouse_move, 1);
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

            if (!print_state_failed and last_print_state_time.durationTo(vk_ctx.frame_timestamp).nanoseconds >= std.time.ns_per_s / 2) {
                if (controller.printState()) {
                    last_print_state_time = vk_ctx.frame_timestamp;
                } else |err| {
                    std.log.warn("failed to print state: {t}", .{err});
                    print_state_failed = true;
                }
            }

            (try resources.beginSettingUniforms()).* = .{
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
fn writeSlangShader(cwd: std.Io.Dir, name: []const u8, stage: ?shader_layout.Stage) !void {
    std.log.debug("extracting shader file {s}", .{name});
    const xz_data = if (stage) |s| s.getNamedStatic(base_shaders) else base_shaders.utils;

    const file = try cwd.createFile(helper.io, name, .{});
    defer file.close(helper.io);

    const write_buf = try helper.allocator.alloc(u8, 4096);
    defer helper.allocator.free(write_buf);
    var writer = file.writer(helper.io, write_buf);

    var xz_reader = std.Io.Reader.fixed(xz_data);
    var decompresser: std.compress.xz.Decompress = try .init(&xz_reader, helper.allocator, &.{});
    defer decompresser.deinit();

    _ = try decompresser.reader.streamRemaining(&writer.interface);
    try writer.interface.flush();
}

fn compileSlangShader(cwd: std.Io.Dir, slangc: []const u8, stage: shader_layout.Stage, out: []const u8) !void {
    const in = try std.fmt.allocPrint(helper.allocator, "{s}.slang", .{@tagName(stage)});
    defer helper.allocator.free(in);

    cwd.access(helper.io, in, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            cwd.access(helper.io, "utils.slang", .{}) catch |err2| switch (err2) {
                error.FileNotFound => try writeSlangShader(cwd, "utils.slang", null),
                else => return err2,
            };
            try writeSlangShader(cwd, in, stage);
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
    var process = try std.process.spawn(helper.io, .{
        .cwd = .{ .dir = cwd },
        .argv = &args,
        .stdin = .ignore,
    });

    const shader_compilation = "shader compilation";
    std.log.info("starting {s}:", .{shader_compilation});
    for (args) |arg| helper.stdout.interface.print("{s} ", .{arg}) catch {};
    helper.stdout.interface.print("\n", .{}) catch {};
    helper.stdout.interface.flush() catch {};

    switch (try process.wait(helper.io)) {
        .exited => |code| {
            if (code == 0) {
                std.log.info("{s} success", .{shader_compilation});
                return;
            }
            std.log.err("{s} exited with {d}", .{shader_compilation, code});
        },
        .signal => |code| std.log.err("{s} signal with {d}", .{shader_compilation, code}),
        .stopped => |code| std.log.err("{s} stopped with {d}", .{shader_compilation, code}),
        .unknown => |code| std.log.err("{s}? code: {d}", .{shader_compilation, code}),
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
        break :blk helper.cwd.openDir(helper.io, f, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                try helper.cwd.createDirPath(helper.io, f);
                break :blk try helper.cwd.openDir(helper.io, f, .{});
            },
            else => return err,
        };
    } else helper.cwd;
    defer if (shader_folder != null) shader_dir.close(helper.io);

    for (shader_layout.Stage.all) |stage| {
        std.log.info("building pipeline {s}", .{@tagName(stage)});
        const spv_file_name = try std.fmt.allocPrint(helper.allocator, "{s}.spv", .{@tagName(stage)});
        defer helper.allocator.free(spv_file_name);

        const spv_file = shader_dir.openFile(helper.io, spv_file_name, .{}) catch |err| switch (err) {
            error.FileNotFound => blk: {
                try compileSlangShader(shader_dir, slangc, stage, spv_file_name);
                break :blk try shader_dir.openFile(helper.io, spv_file_name, .{});
            },
            else => return err,
        };
        defer spv_file.close(helper.io);
        var reader = spv_file.reader(helper.io, &.{});

        const stat = try spv_file.stat(helper.io);
        const code = try helper.allocator.alloc(u32, stat.size / 4);
        defer helper.allocator.free(code);
        try reader.interface.readSliceAll(std.mem.sliceAsBytes(code));

        try vk_ctx.buildPipeline(stage, code);
    }
}
