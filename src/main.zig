const std = @import("std");
const rl = @import("raylib");
const c = @cImport({
    @cInclude("rlImGui.h");
});
const z = @import("zgui");

const WindowState = struct {
    var width: i32 = 960;
    var height: i32 = 720;
    var padding: i32 = 16;
    var paddedWidth: i32 = undefined;
    var paddedHeight: i32 = undefined;

    pub fn init() void {
        computePaddedDimensions();
    }

    pub fn resize(new_width: i32, new_height: i32) void {
        width = new_width;
        height = new_height;
        computePaddedDimensions();
    }

    pub fn setPadding(new_padding: i32) void {
        padding = new_padding;
        computePaddedDimensions();
    }

    fn computePaddedDimensions() void {
        paddedWidth = width - 2 * padding;
        paddedHeight = height - 2 * padding;
    }
};

const LoadedResource = struct {
    texture: rl.Texture = undefined,
    scale: f32 = 1.0,
    offsetX: f32 = 0.0,
    offsetY: f32 = 0.0,
};
fn loadImage(path: [:0]const u8, resource: *LoadedResource) !void {
    const image = try rl.loadImage(path);
    defer rl.unloadImage(image);

    resource.texture = try rl.loadTextureFromImage(image);

    computeScaleAndOffset(resource);
}
fn computeScaleAndOffset(resource: *LoadedResource) void {
    resource.offsetX = @as(f32, @floatFromInt(WindowState.padding));
    resource.offsetY = @as(f32, @floatFromInt(WindowState.padding));

    // Calculate scaling factor to fit the image within the window with padding
    const windowAspectRatio = @as(f32, @floatFromInt(WindowState.width)) / @as(f32, @floatFromInt(WindowState.height));
    const imageAspectRatio = @as(f32, @floatFromInt(resource.texture.width)) / @as(f32, @floatFromInt(resource.texture.height));

    if (imageAspectRatio > windowAspectRatio) {
        // Image is wider than the window, scale based on width
        resource.scale = @as(f32, @floatFromInt(WindowState.paddedWidth)) / @as(f32, @floatFromInt(resource.texture.width));
        resource.offsetY += (@as(f32, @floatFromInt(WindowState.paddedHeight)) - (@as(f32, @floatFromInt(resource.texture.height)) * resource.scale)) / 2;
    } else {
        // Image is taller than the window, scale based on height
        resource.scale = @as(f32, @floatFromInt(WindowState.paddedHeight)) / @as(f32, @floatFromInt(resource.texture.height));
        resource.offsetX += (@as(f32, @floatFromInt(WindowState.paddedWidth)) - (@as(f32, @floatFromInt(resource.texture.width)) * resource.scale)) / 2;
    }
}

pub fn main() !void {
    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // stdout is for the actual output of your application, for example if you
    // are implementing gzip, then only the compressed bytes should be sent to
    // stdout, not any debugging messages.
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    try bw.flush(); // don't forget to flush!

    // Print current working directory
    var cwd_buf: [1024]u8 = undefined;
    const cwd = try std.process.getCwd(&cwd_buf);
    std.debug.print("Current working directory: {s}\n", .{cwd});

    // Initialize window
    WindowState.init();
    rl.initWindow(WindowState.width, WindowState.height, "zigversion");
    defer rl.closeWindow();
    rl.setWindowState(.{ .window_resizable = true });

    // Initialize imgui backend
    c.rlImGuiSetup(true);
    defer c.rlImGuiShutdown();
    // Initialize zgui
    z.initNoContext(std.heap.c_allocator);
    defer z.deinitNoContext();

    // Get image path from stdin
    var imagePath_buf: [1024]u8 = undefined;
    const stdin = std.io.getStdIn().reader();
    std.debug.print("Enter image path: ", .{});
    const imagePath_input = try stdin.readUntilDelimiterOrEof(&imagePath_buf, '\n') orelse return error.UnexpectedEof;
    imagePath_buf[imagePath_input.len] = 0; // Null terminate string
    const imagePath = imagePath_buf[0..imagePath_input.len :0];

    var resource = LoadedResource{};
    loadImage(imagePath, &resource) catch |err| {
        std.debug.print("Failed to load image: {}\n", .{err});
    };
    defer rl.unloadTexture(resource.texture);
    computeScaleAndOffset(&resource);

    // Load the shader
    const inversionShader: rl.Shader = rl.loadShader(null, "./src/inversion.fs") catch |err| {
        std.debug.print("Failed to load shader: {}\n", .{err});
        return; // Exit the program if the shader fails to load
    };

    // Declare inversion related variables
    const CircleOfInversion = struct {
        var radius: f32 = 100.0;
        var center: [2]f32 = undefined;
    };
    // Initialize center of inversion at the center of the image
    CircleOfInversion.center = .{
        @as(f32, @floatFromInt(@divTrunc(resource.texture.width, 2))),
        @as(f32, @floatFromInt(@divTrunc(resource.texture.height, 2))),
    };

    // Get uniform locations
    const circleCenterLoc = rl.getShaderLocation(inversionShader, "circleCenter");
    const circleRadiusLoc = rl.getShaderLocation(inversionShader, "circleRadius");
    const textureSizeLoc = rl.getShaderLocation(inversionShader, "textureSize");

    // Set initial shader uniforms
    rl.setShaderValue(inversionShader, circleCenterLoc, &CircleOfInversion.center, rl.ShaderUniformDataType.vec2);
    rl.setShaderValue(inversionShader, circleRadiusLoc, &CircleOfInversion.radius, rl.ShaderUniformDataType.float);
    const textureSize = [2]f32{ @floatFromInt(resource.texture.width), @floatFromInt(resource.texture.height) };
    rl.setShaderValue(inversionShader, textureSizeLoc, &textureSize, rl.ShaderUniformDataType.vec2);

    // Set target FPS
    rl.setTargetFPS(60);

    // Initialize variables for shader rendering time measurement
    var total_shadertime_micros: i64 = 0;
    var frame_count: i64 = 0;
    rl.setWindowFocused();
    while (!rl.windowShouldClose()) {
        if (rl.isWindowResized()) {
            WindowState.resize(rl.getScreenWidth(), rl.getScreenHeight());
            computeScaleAndOffset(&resource);
        }

        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.sky_blue);

        // Mark start time
        const start_time = std.time.microTimestamp();

        // Get mouse coordinates
        const mousePos = rl.getMousePosition();
        // Check if mouse position is available
        if (!(mousePos.x == 0 and mousePos.y == 0)) {
            // Adjust them to be relative to the image
            CircleOfInversion.center[0] = (mousePos.x - resource.offsetX) / resource.scale;
            CircleOfInversion.center[1] = (mousePos.y - resource.offsetY) / resource.scale;
            // Set shader uniforms
            rl.setShaderValue(
                inversionShader,
                circleCenterLoc,
                &CircleOfInversion.center,
                rl.ShaderUniformDataType.vec2,
            ); // Center of the circle
            rl.setShaderValue(inversionShader, circleRadiusLoc, &CircleOfInversion.radius, rl.ShaderUniformDataType.float);
        }

        rl.beginShaderMode(inversionShader);
        rl.drawTextureEx(
            resource.texture,
            rl.Vector2{ .x = resource.offsetX, .y = resource.offsetY },
            0.0, // Rotation
            resource.scale, // Scaling factor
            rl.Color.black,
        );
        rl.endShaderMode();

        // Mark end time
        const end_time = std.time.microTimestamp();
        const elapsed_time = end_time - start_time;
        std.debug.print(
            "Shader rendering took {}.{} ms\n",
            .{ @divTrunc(elapsed_time, 1000), @mod(elapsed_time, 1000) },
        );
        total_shadertime_micros += elapsed_time;
        frame_count += 1;

        // Draw imgui
        c.rlImGuiBegin();
        defer c.rlImGuiEnd();

        {
            _ = z.begin("Hello imgui", .{});
            defer z.end();
            const fontSize = z.getFontSize();
            var buf: [64]u8 = undefined;
            const text = std.fmt.bufPrintZ(&buf, "Font size is {d}px", .{fontSize}) catch unreachable;
            _ = z.textUnformatted(text);
        }
    }
    // Log average shader rendering time
    const mean_shadertime_micros = @divTrunc(total_shadertime_micros, frame_count);
    std.debug.print(
        "Average shader rendering time per frame: {}.{} ms\n",
        .{ @divTrunc(mean_shadertime_micros, 1000), @mod(mean_shadertime_micros, 1000) },
    );
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
