const std = @import("std");
const glfw = @import("mach_glfw");
const gfx = @import("graphics/graphics.zig");
const voxel = @import("voxel.zig");
const procgen = @import("procgen.zig").procgen;
const dotvox = @import("dotvox.zig");
const input = @import("input.zig");

const zmath = @import("zmath");
const clamp = zmath.clamp;

/// Camera uniform data.
const CameraData = extern struct {
    position: zmath.F32x4,
    matrix: zmath.Mat,
    sun_pos: zmath.F32x4,
    subtex: u64,
};

const PlayerAction = enum { Forward, Backward, Right, Left, Up, Down };

pub const App = @This();

window: glfw.Window,
allocator: std.heap.GeneralPurposeAllocator(.{}),

// gl stuff
framebuffer: gfx.Framebuffer,
pipeline: gfx.ComputePipeline,
uniforms: gfx.PersistentMappedBuffer,

// voxel map
voxels: voxel.VoxelMap(512, 8),
models: voxel.VoxelMapPalette(5),

/// camera
old_mouse_x: f64 = 0.0,
old_mouse_y: f64 = 0.0,

position: zmath.F32x4 = zmath.f32x4(256.0, 128.0, 256.0, 0.0),

pitch: f32 = 0.0,
yaw: f32 = 0.0,
cam_mat: zmath.Mat = zmath.identity(),

// input
actions: input.Input(PlayerAction) = .{},

pub fn init() !App {
    const window = glfw.Window.create(1280, 720, "voxl", null, null, .{ .srgb_capable = true }) orelse @panic("Failed to open GLFW window.");
    try gfx.init(window);
    gfx.enableDebug();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    errdefer _ = gpa.deinit();

    var frame = gfx.Framebuffer.init(1280, 720, gfx.TextureFormat.RGBA8);
    errdefer frame.deinit();

    const pipeline = try gfx.ComputePipeline.init(gpa.allocator(), "assets/shaders/draw.comp");

    var uniforms = gfx.PersistentMappedBuffer.init(gfx.BufferType.Uniform, @sizeOf(CameraData), gfx.BufferCreationFlags.MappableWrite | gfx.BufferCreationFlags.MappableRead);

    var voxels = voxel.VoxelMap(512, 8).init(0);
    procgen(512, &voxels, 0.0, 0.0);

    var models = voxel.VoxelMapPalette(5).init();

    try models.load_model("assets/grass.vox", gpa.allocator());
    try models.load_model("assets/grass2.vox", gpa.allocator());
    try models.load_model("assets/grass3.vox", gpa.allocator());
    try models.load_model("assets/grass4.vox", gpa.allocator());
    try models.load_model("assets/grass5.vox", gpa.allocator());

    return .{
        .window = window,
        .allocator = gpa,
        .framebuffer = frame,
        .pipeline = pipeline,
        .uniforms = uniforms,
        .voxels = voxels,
        .models = models,
    };
}

/// Called when the mouse is moved.
pub fn on_mouse_moved(self: *@This(), xpos: f64, ypos: f64) void {
    const delta_x = xpos - self.old_mouse_x;
    const delta_y = ypos - self.old_mouse_y;

    self.pitch = clamp(self.pitch + @as(f32, @floatCast(delta_y)) * 0.001, -std.math.pi / 2.0, std.math.pi / 2.0);
    self.yaw = self.yaw + @as(f32, @floatCast(delta_x)) * 0.001;

    self.cam_mat = zmath.matFromRollPitchYaw(self.pitch, self.yaw, 0.0);

    self.old_mouse_x = xpos;
    self.old_mouse_y = ypos;
}

pub fn update_physics(self: *@This()) void {
    var velocity = zmath.f32x4(0.0, 0.0, 0.0, 0.0);

    if (self.actions.is_pressed(.Forward)) {
        velocity = velocity + zmath.mul(zmath.f32x4(0.0, 0.0, 1.0, 0.0), self.cam_mat) * zmath.f32x4(1.0, 0.0, 1.0, 0.0);
    }

    if (self.actions.is_pressed(.Backward)) {
        velocity = velocity - zmath.mul(zmath.f32x4(0.0, 0.0, 1.0, 0.0), self.cam_mat) * zmath.f32x4(1.0, 0.0, 1.0, 0.0);
    }

    if (self.actions.is_pressed(.Right)) {
        velocity = velocity + zmath.mul(zmath.f32x4(1.0, 0.0, 0.0, 0.0), self.cam_mat) * zmath.f32x4(1.0, 0.0, 1.0, 0.0);
    }

    if (self.actions.is_pressed(.Left)) {
        velocity = velocity - zmath.mul(zmath.f32x4(1.0, 0.0, 0.0, 0.0), self.cam_mat) * zmath.f32x4(1.0, 0.0, 1.0, 0.0);
    }

    if (self.actions.is_pressed(.Up)) {
        velocity = velocity + zmath.f32x4(0.0, 1.6, 0.0, 0.0);
    }

    if (self.actions.is_pressed(.Down)) {
        velocity = velocity - zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    }

    const gravity = zmath.f32x4(0.0, -0.2, 0.0, 0.0);
    var finalPos = self.position + velocity * @as(@Vector(4, f32), @splat(0.2));
    const flooredPos = zmath.floor(finalPos);

    // direction
    if (!self.voxels.is_walkable(@intFromFloat(flooredPos[0]), @intFromFloat(flooredPos[1]), @intFromFloat(flooredPos[2]))) {
        if (self.voxels.is_walkable(@intFromFloat(flooredPos[0]), @intFromFloat(flooredPos[1] + 1), @intFromFloat(flooredPos[2]))) {
            finalPos = self.position + zmath.f32x4(0.0, 1.6, 0.0, 0.0);
        } else {
            finalPos = self.position;
        }
    }

    // gravity
    const afterGrav = finalPos + gravity;
    const flafterGrav = zmath.floor(afterGrav);
    if (self.voxels.get(@intFromFloat(flafterGrav[0]), @intFromFloat(flafterGrav[1]), @intFromFloat(flafterGrav[2])) == 0) {
        finalPos = afterGrav;
    }

    self.uniforms.get(CameraData).*.position = finalPos + zmath.f32x4(0.0, 4.0, 0.0, 0.0);
    self.position = finalPos;
}

/// Called upon window resize.
pub fn on_resize(self: *@This(), width: u32, height: u32) void {
    gfx.resize(width, height);
    self.framebuffer.deinit();
    self.framebuffer = gfx.Framebuffer.init(width, height, gfx.TextureFormat.RGBA8);
}

/// Called upon key down.
pub fn on_key_down(self: *@This(), key: glfw.Key, scancode: i32, mods: glfw.Mods, action: glfw.Action) void {
    _ = mods;
    _ = scancode;
    switch (key) {
        .r => self.reloadShaders(),
        // camera controls
        .w => {
            if (action == .press) {
                self.actions.press(.Forward);
            } else if (action == .release) {
                self.actions.release(.Forward);
            }
        },
        .s => {
            if (action == .press) {
                self.actions.press(.Backward);
            } else if (action == .release) {
                self.actions.release(.Backward);
            }
        },
        .a => {
            if (action == .press) {
                self.actions.press(.Left);
            } else if (action == .release) {
                self.actions.release(.Left);
            }
        },
        .d => {
            if (action == .press) {
                self.actions.press(.Right);
            } else if (action == .release) {
                self.actions.release(.Right);
            }
        },
        .space => {
            if (action == .press) {
                self.actions.press(.Up);
            } else if (action == .release) {
                self.actions.release(.Up);
            }
            //self.velocity = self.velocity + zmath.f32x4(0.0, 1.0, 0.0, 0.0);
        },
        .left_shift => {
            if (action == .press) {
                self.actions.press(.Down);
            } else if (action == .release) {
                self.actions.release(.Down);
            }
            //self.velocity = self.velocity + zmath.f32x4(0.0, -1.0, 0.0, 0.0);
        },
        else => {},
    }
}

/// Main app loop.
pub fn run(self: *@This()) void {
    self.window.setUserPointer(self);

    self.window.setFramebufferSizeCallback((struct {
        pub fn handle_resize(window: glfw.Window, width: u32, height: u32) void {
            const app: *App = window.getUserPointer(App) orelse @panic("Failed to get user pointer.");
            app.on_resize(width, height);
        }
    }).handle_resize);

    self.window.setKeyCallback((struct {
        pub fn handle_key(window: glfw.Window, key: glfw.Key, scancode: i32, action: glfw.Action, mods: glfw.Mods) void {
            const app: *App = window.getUserPointer(App) orelse @panic("Failed to get user pointer.");
            if (action == .press or action == .release) {
                app.on_key_down(key, scancode, mods, action);
            }
        }
    }).handle_key);

    self.window.setCursorPosCallback((struct {
        pub fn handle_mouse_move(window: glfw.Window, xpos: f64, ypos: f64) void {
            const app: *App = window.getUserPointer(App) orelse @panic("Failed to get user pointer.");
            app.on_mouse_moved(xpos, ypos);
        }
    }).handle_mouse_move);

    self.window.setInputModeCursor(glfw.Window.InputModeCursor.disabled);

    while (!self.window.shouldClose()) {
        glfw.pollEvents();
        // app logic
        self.update();
        // render
        self.draw();
        // swap buffers and poll events
        self.window.swapBuffers();
    }
}

pub fn update(self: *@This()) void {
    self.uniforms.get(CameraData).*.matrix = self.cam_mat;
    self.uniforms.get(CameraData).*.sun_pos = zmath.f32x4(400.0, 100.0, 0.0, 0.0);
    self.update_physics();
    self.actions.update();
}

pub fn draw(self: *@This()) void {
    const wsize = self.window.getFramebufferSize();
    self.uniforms.bind(1);
    self.voxels.bind(2);
    self.models.bind(4);

    self.framebuffer.clear(0.0, 0.0, 0.0, 0.0);
    self.framebuffer.color_attachment.bind_image(0, gfx.TextureUsage.Write, null);
    self.pipeline.bind();
    self.pipeline.dispatch(90, 80, 1);
    gfx.clear(0.0, 0.0, 0.0);
    self.framebuffer.blit_to_screen(0, 0, 0, 0, wsize.width, wsize.height);
}

/// Reloads the shaders.
pub fn reloadShaders(self: *@This()) void {
    const pipeline = gfx.ComputePipeline.init(self.allocator.allocator(), "assets/shaders/draw.comp") catch |err| {
        std.log.warn("Failed to reload shaders: {}\n", .{err});
        return;
    };
    self.pipeline.deinit();
    self.pipeline = pipeline;
    std.log.debug("Shaders reloaded", .{});
}

pub fn deinit(self: *@This()) void {
    self.framebuffer.deinit();
    self.window.destroy();
    self.models.deinit(self.allocator.allocator());
    _ = self.allocator.deinit();
}
