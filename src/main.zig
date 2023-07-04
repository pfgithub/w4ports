const std = @import("std");
const ray = @cImport({
    @cInclude("raylib.h");
});
const c = @cImport({
    @cInclude("game.h");
});

const WasmEnv = struct {
    memory: c.wasm_rt_memory_t,
    disk_len: u32 = 0,
    disk: [1024]u8,
};

// next: try WAMR (WebAssembly Micro Runtime)
// this skips compile step, can do jit, and may(?) be easier to embed in 3ds

pub fn main() !void {
    const alloc = std.heap.c_allocator;

    ray.SetConfigFlags(ray.FLAG_WINDOW_RESIZABLE);
    ray.InitWindow(160 * 3 + 10 * 2, 160 * 3 + 10 * 2, "wasm4");
    defer ray.CloseWindow();

    ray.SetTargetFPS(60);

    c.wasm_rt_init();
    defer c.wasm_rt_free();

    var env: WasmEnv = .{
        .memory = undefined,
        .disk_len = 0,
        .disk = undefined,
    };

    c.wasm_rt_allocate_memory(&env.memory, 1, 1, false);
    defer c.wasm_rt_free_memory(&env.memory);

    var game: c.w2c_plctfarmer = undefined;
    c.wasm2c_plctfarmer_instantiate(&game, @ptrCast(&env));
    defer c.wasm2c_plctfarmer_free(&game);

    c.w2c_plctfarmer_start(&game);

    var image_data = try alloc.create([160 * 160 * 3]u8);
    defer alloc.free(image_data);
    for(image_data) |*v| v.* = 0;

    const tex = ray.LoadTextureFromImage(.{
        .data = image_data,
        .width = 160,
        .height = 160,
        .mipmaps = 1,
        .format = ray.PIXELFORMAT_UNCOMPRESSED_R8G8B8,
    });
    defer ray.UnloadTexture(tex);

    while(!ray.WindowShouldClose()) {
        const sw = ray.GetScreenWidth();
        const sh = ray.GetScreenHeight();
        const max_axis = @min(sw, sh);
        var max_render_scale: c_int = 1;
        while(160 * (max_render_scale + 1) <= max_axis) {
            max_render_scale += 1;
        }
        const scale_factor = max_render_scale;
        const scale_factorf: f32 = @floatFromInt(max_render_scale);
        const padding_x = @divFloor(sw - (160 * scale_factor), 2);
        const padding_y = @divFloor(sh - (160 * scale_factor), 2);
        const padding_xf: f32 = @floatFromInt(padding_x);
        const padding_yf: f32 = @floatFromInt(padding_y);

        // pub const MOUSE: *const Mouse = @intToPtr(*const Mouse, 0x1a);
        // x: i16, y: i16, buttons: u8
        const mouse_x = std.math.lossyCast(i16, @divFloor(ray.GetMouseX() - padding_x, scale_factor));
        const mouse_y = std.math.lossyCast(i16, @divFloor(ray.GetMouseY() - padding_y, scale_factor));
        std.mem.writeIntLittle(i16, env.memory.data[0x1A..][0..2], mouse_x);
        std.mem.writeIntLittle(i16, env.memory.data[0x1C..][0..2], mouse_y);
        env.memory.data[0x1E] = 0
            | @as(u8, if(ray.IsMouseButtonDown(ray.MOUSE_BUTTON_LEFT)) 0b001 else 0)
            | @as(u8, if(ray.IsMouseButtonDown(ray.MOUSE_BUTTON_RIGHT)) 0b010 else 0)
            | @as(u8, if(ray.IsMouseButtonDown(ray.MOUSE_BUTTON_MIDDLE)) 0b100 else 0)
        ;

        const BUTTON_1: u8 = 0b00000001;
        const BUTTON_2: u8 = 0b00000010;
        const BUTTON_LEFT: u8 = 0b00010000;
        const BUTTON_RIGHT: u8 = 0b00100000;
        const BUTTON_UP: u8 = 0b01000000;
        const BUTTON_DOWN: u8 = 0b10000000;
        const NONE: u8 = 0;
        env.memory.data[0x16] = 0
            | (if(ray.IsKeyDown(ray.KEY_X) or ray.IsKeyDown(ray.KEY_V) or ray.IsKeyDown(ray.KEY_SPACE) or ray.IsKeyDown(ray.KEY_RIGHT_SHIFT)) BUTTON_1 else NONE)
            | (if(ray.IsKeyDown(ray.KEY_Z) or ray.IsKeyDown(ray.KEY_C) or ray.IsKeyDown(ray.KEY_ENTER) or ray.IsKeyDown(ray.KEY_N)) BUTTON_2 else NONE)
            | (if(ray.IsKeyDown(ray.KEY_LEFT)) BUTTON_LEFT else NONE)
            | (if(ray.IsKeyDown(ray.KEY_RIGHT)) BUTTON_RIGHT else NONE)
            | (if(ray.IsKeyDown(ray.KEY_UP)) BUTTON_UP else NONE)
            | (if(ray.IsKeyDown(ray.KEY_DOWN)) BUTTON_DOWN else NONE)
        ;
        env.memory.data[0x17] = 0
            | (if(ray.IsKeyDown(ray.KEY_TAB) or ray.IsKeyDown(ray.KEY_LEFT_SHIFT)) BUTTON_1 else NONE)
            | (if(ray.IsKeyDown(ray.KEY_Q) or ray.IsKeyDown(ray.KEY_A)) BUTTON_2 else NONE)
            | (if(ray.IsKeyDown(ray.KEY_S)) BUTTON_LEFT else NONE)
            | (if(ray.IsKeyDown(ray.KEY_F)) BUTTON_RIGHT else NONE)
            | (if(ray.IsKeyDown(ray.KEY_E)) BUTTON_UP else NONE)
            | (if(ray.IsKeyDown(ray.KEY_D)) BUTTON_DOWN else NONE)
        ;

        if(ray.IsKeyPressed(ray.KEY_R)) {
            c.wasm2c_plctfarmer_free(&game);
            c.wasm2c_plctfarmer_instantiate(&game, @ptrCast(&env));

            c.w2c_plctfarmer_start(&game);
        }

        c.w2c_plctfarmer_update(&game);

        const rendered_frame = env.memory.data[0xA0..][0..6400];
        const rendered_palette: [4]u32 = .{
            std.mem.readIntLittle(u32, env.memory.data[0x04..][0..4]),
            std.mem.readIntLittle(u32, env.memory.data[0x08..][0..4]),
            std.mem.readIntLittle(u32, env.memory.data[0x0C..][0..4]),
            std.mem.readIntLittle(u32, env.memory.data[0x10..][0..4]),
        };

        for(0..160) |y| {
            for(0..160 / 4) |x| {
                const target_byte = rendered_frame[(y * 160 + x * 4) / 4];
                for(0..4) |seg| {
                    const target_bit = (target_byte >> @intCast(seg * 2)) & 0b11;
                    const target_color = rendered_palette[target_bit];

                    const v = y * 160 + x * 4 + seg;
                    image_data[v * 3 + 0] = @intCast((target_color >> 16) & 0xFF);
                    image_data[v * 3 + 1] = @intCast((target_color >> 8 ) & 0xFF);
                    image_data[v * 3 + 2] = @intCast((target_color >> 0 ) & 0xFF);
                }
            }
        }

        ray.UpdateTexture(tex, image_data);

        ray.BeginDrawing();
        defer ray.EndDrawing();

        ray.ClearBackground(.{.r = 0, .g = 0, .b = 0, .a = 0});
        ray.DrawRectangleV(.{.x = padding_xf - 1, .y = padding_yf - 1}, .{.x = 160 * scale_factorf + 2, .y = 160 * scale_factorf + 2}, .{.r = 255, .g = 255, .b = 255, .a = 255});
        ray.DrawTextureEx(tex, .{.x = padding_xf, .y = padding_yf}, 0, scale_factorf, .{.r = 255, .g = 255, .b = 255, .a = 255});

        ray.DrawFPS(0, 0);
    }
}


// pub const PALETTE: *[4]u32 = @intToPtr(*[4]u32, 0x04);
// pub const DRAW_COLORS: *u16 = @intToPtr(*u16, 0x14);
// pub const GAMEPAD1: *const Gamepad = @intToPtr(*const Gamepad, 0x16);
// pub const GAMEPAD2: *const Gamepad = @intToPtr(*const Gamepad, 0x17);
// pub const GAMEPAD3: *const Gamepad = @intToPtr(*const Gamepad, 0x18);
// pub const GAMEPAD4: *const Gamepad = @intToPtr(*const Gamepad, 0x19);
//
// pub const SYSTEM_FLAGS: *SystemFlags = @intToPtr(*SystemFlags, 0x1f);
// pub const FRAMEBUFFER: *[CANVAS_SIZE * CANVAS_SIZE / 4]u8 = @intToPtr(*[6400]u8, 0xA0);
// pub const CANVAS_SIZE = 160;

// we will support save/load via savestates, so these just have to save into memory along with
// regular updating of the savestate

export fn w2c_env_memory(env: *WasmEnv) *c.wasm_rt_memory_t {
    return &env.memory;
}

export fn w2c_env_diskr(env: *WasmEnv, dest_ptr: u32, size: u32) u32 {
    const read_count = @min(size, env.disk_len);
    for(0..read_count) |i| {
        if(env.memory.size < dest_ptr + i) unreachable;
        env.memory.data[dest_ptr + i] = env.disk[i];
    }
    return read_count;
}

export fn w2c_env_diskw(env: *WasmEnv, src_ptr: u32, size: u32) u32 {
    const write_count = @min(size, env.disk.len);
    for(0..write_count) |i| {
        if(env.memory.size < src_ptr + i) unreachable;
        env.disk[i] = env.memory.data[src_ptr + i];
    }
    env.disk_len = write_count;
    return write_count;
}

export fn w2c_env_line(env: *WasmEnv, x1: u32, y1: u32, x2: u32, y2: u32) void {
    _ = env;
    std.log.info("TODO line {} {} {} {}", .{x1, y1, x2, y2});
}

export fn w2c_env_rect(env: *WasmEnv, x: u32, y: u32, w: u32, h: u32) void {
    _ = env;
    std.log.info("TODO rect {} {} {} {}", .{x, y, w, h});
}

export fn w2c_env_textUtf8(env: *WasmEnv, str: u32, len: u32, x: u32, y: u32) void {
    if(env.memory.size < str + len) unreachable;
    std.log.info("TODO text \"{s}\" {} {}", .{env.memory.data[str..][0..len], x, y});
}

export fn w2c_env_tone(env: *c.struct_w2c_env, frequency: u32, duration: u32, volume: u32, flags: u32) void {
    _ = env;
    std.log.info("TODO tone {} {} {} {}", .{frequency, duration, volume, flags});
}

var wasm_rt_is_initialized_val: bool = false;
export fn wasm_rt_init() void {
    wasm_rt_is_initialized_val = true;
}
export fn wasm_rt_is_initialized() bool {
    return wasm_rt_is_initialized_val;
}
export fn wasm_rt_free() void {
    wasm_rt_is_initialized_val = false;
}
export fn wasm_rt_trap(trap: c.wasm_rt_trap_t) void {
    _ = trap;
    unreachable;
}
export fn wasm_rt_allocate_memory(memory: *c.wasm_rt_memory_t, initial_pages: u32, max_pages: u32, is64: bool) void {
    const alloc = std.heap.c_allocator;
    const data = alloc.alloc(u8, initial_pages * 65536) catch @panic("oom");
    // errdefer alloc.free(data);
    memory.* = .{
        .data = data.ptr,
        .pages = initial_pages,
        .max_pages = max_pages,
        .size = @intCast(data.len),
        .is64 = is64,
    };
}
export fn wasm_rt_free_memory(memory: *c.wasm_rt_memory_t) void {
    const alloc = std.heap.c_allocator;
    alloc.free(memory.data[0..memory.size]);
}
export fn wasm_rt_allocate_funcref_table(table: *c.wasm_rt_funcref_table_t, elements: u32, max_elements: u32) void {
    const alloc = std.heap.c_allocator;
    const data = alloc.alloc(c.wasm_rt_funcref_t, elements) catch @panic("oom");
    //errdefer alloc.free(data);
    table.* = .{
        .data = data.ptr,
        .size = elements,
        .max_size = max_elements,
    };
}
export fn wasm_rt_free_funcref_table(table: *c.wasm_rt_funcref_table_t) void {
    const alloc = std.heap.c_allocator;
    alloc.free(table.data[0..table.size]);
}

// in place of wasm-rt-impl.c:
//
// void wasm_rt_init(void);
// bool wasm_rt_is_initialized(void);
// void wasm_rt_free(void);
// void wasm_rt_trap(wasm_rt_trap_t) __attribute__((noreturn));
// const char* wasm_rt_strerror(wasm_rt_trap_t trap);
// void wasm_rt_allocate_memory(wasm_rt_memory_t*, uint32_t initial_pages, uint32_t max_pages, bool is64);
// uint32_t wasm_rt_grow_memory(wasm_rt_memory_t*, uint32_t pages);
// void wasm_rt_free_memory(wasm_rt_memory_t*);
// void wasm_rt_allocate_funcref_table(wasm_rt_table_t*, uint32_t elements, uint32_t max_elements);
// void wasm_rt_allocate_externref_table(wasm_rt_externref_table_t*, uint32_t elements, uint32_t max_elements);
// void wasm_rt_free_funcref_table(wasm_rt_table_t*);
// void wasm_rt_free_externref_table(wasm_rt_table_t*);
// uint32_t wasm_rt_call_stack_depth; /* on platforms that don't use the signal handler to detect exhaustion */
