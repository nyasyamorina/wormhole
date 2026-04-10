const std = @import("std");
const vk = @import("vulkan-zig");
const glfw = @import("glfw");

const Arguments = @import("Arguments.zig");
const helper = @import("helper.zig");
const VulkanContext = @import("VulkanContext.zig");
const shader_layout = @import("shader_layout.zig");
const math = @import("math.zig");
const Controller = @import("Controller.zig");
const GlfwCallback = @import("GlfwCallback.zig");


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

    const time_scale = args.simulation_speed.value / std.time.ns_per_s;
    const position: math.v4f32 = .{0, args.position.value * math.schwarzschild.radius, 0, 0};
    const frame: math.schwarzschild.Frame = if (args.circular.value)
        try .initCircularOrbit(position, .{1, 0, 0})
    else
        try .initAtRest(position);
    var controller: Controller = .{
        .space_time_frame = frame,
        .screen_scale = .init(args.fov_y.value),
        .thrust = 0.1,
    };

    var vk_ctx: VulkanContext = try .init();
    defer vk_ctx.deinit();

    const frame_size = vk_ctx.window.getFramebufferSize();
    var glfw_cb: GlfwCallback = .{ .frame_width = frame_size.width, .frame_height = frame_size.height };
    glfw_cb.setCallbacks(vk_ctx.window);

    try buildPipelines(&vk_ctx, args.slangc.value, args.shader_folder.value);

    var timer = if (helper.is_debug) helper.Timer(&.{.loop, .frame}, 0.87).init else void {};
    var main_loop_timestamp: i128 = std.time.nanoTimestamp();

    var normalize_timestamp = main_loop_timestamp;

    var print_state_failed = false;
    var last_print_state_timestampp = main_loop_timestamp;
    helper.stdout.interface.print("\nstate:\n\x1b[s", .{}) catch {};

    std.log.debug("entering main loop...", .{});
    std.log.debug("main loop exited.", .{});
    main_loop: while (!vk_ctx.window.shouldClose()) {

        if (helper.is_debug) timer.start(.loop);
        glfw.pollEvents();

        const current_timestamp = std.time.nanoTimestamp();
        const time_step = time_scale * @as(f32, @floatFromInt(current_timestamp - main_loop_timestamp));
        main_loop_timestamp = current_timestamp;

        if (glfw_cb.q_pressed) {
            vk_ctx.window.setShouldClose(true);
            continue :main_loop;
        }
        if (glfw_cb.takeResizeInfo()) |extent| {
            try vk_ctx.recreateSwapchain(extent);
            controller.screen_scale.setAspectRatio(extent);
            // to prevent too many times swapchain recreation
            std.Thread.sleep(300 * std.time.ns_per_ms);
        }

        if (glfw_cb.takeMouseMove()) |mouse_move| {
            controller.rotateCamera(mouse_move, 1);
        }
        if (glfw_cb.takeScroll()) |scroll| {
            controller.changeThrust(scroll);
        }

        if (glfw_cb.takeMovement()) |movement| {
            controller.accelerate(movement, time_step);
        }
        controller.step(time_step);

        if (main_loop_timestamp - normalize_timestamp >= 10 * std.time.ns_per_s) {
            controller.space_time_frame.normalizeAxes();
            normalize_timestamp = main_loop_timestamp;
        }

        if (!print_state_failed and main_loop_timestamp - last_print_state_timestampp >= std.time.ns_per_s / 2) {
            if (printStateTick(controller, timer)) {
                last_print_state_timestampp = main_loop_timestamp;
            } else |err| {
                std.log.warn("failed to print state: {t}", .{err});
                print_state_failed = true;
            }
        }

        var may_error: ?anyerror = null;
        var may_resources = vk_ctx.acquireFrame() catch |err| blk: {
            may_error = err;
            break :blk null;
        };
        if (may_resources) |*resources| {
            if (helper.is_debug) timer.start(.frame);

            try resources.setUniform(.{
                .frame = controller.space_time_frame.toUniform(),
                .screen_scale = controller.screen_scale.toUniform(),
                .iter_per_call = args.iter_per_call.value,
            });

            resources.drawFrame(.{
                .n_iter_call = args.n_iter_calls.value,
            }) catch |err| {
                may_error = err;
            };

            if (helper.is_debug) timer.stop(.frame);
        }

        if (may_error) |err| switch (err) {
            error.OutOfDateKHR => {
                const size = vk_ctx.window.getFramebufferSize();
                const extent: vk.Extent2D = .{ .width = @intCast(size.width), .height = @intCast(size.height) };
                try vk_ctx.recreateSwapchain(extent);
                controller.screen_scale.setAspectRatio(extent);
            },
            else => return err,
        };

        if (helper.is_debug) timer.stop(.loop);
    }
}


const base_shaders = struct {
    pub const utils: []const u8 = @embedFile("utils.slang.xz");
    pub const init_ray: []const u8 = @embedFile("init_ray.slang.xz");
    pub const iter_ray: []const u8 = @embedFile("iter_ray.slang.xz");
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
                std.log.debug("{s} success", .{shader_compilation});
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
        std.log.debug("building pipeline {s}", .{@tagName(stage)});
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


fn printStateTick(controller: Controller, timer: anytype) !void {
    try helper.stdout.interface.print("\x1b[u", .{});
    try controller.printState();
    if (helper.is_debug) try timer.report();
    try helper.stdout.interface.flush();
}
