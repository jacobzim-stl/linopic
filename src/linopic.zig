const std = @import("std");
const c = @cImport(@cInclude("raylib.h"));
const grid = @import("grid.zig");
const lines = @import("lines.zig");

pub const Grid = grid.Grid;
pub const Color = grid.Color;
pub const Line = grid.Line;
pub const MouseEvt = grid.MouseEvt;
pub const KeyState = grid.KeyState;
// LineStyle flags
pub const LINE_2SEG = grid.LINE_2SEG;
pub const LINE_3SEG = grid.LINE_3SEG;
pub const LINE_CORNER_HARD = grid.LINE_CORNER_HARD;
pub const LINE_CORNER_NONE = grid.LINE_CORNER_NONE;
pub const LINE_BIAS_START = grid.LINE_BIAS_START;
pub const LINE_BIAS_END = grid.LINE_BIAS_END;
// Key constants
pub const KEY_SHIFT = grid.KEY_SHIFT;
pub const KEY_CTRL = grid.KEY_CTRL;
pub const KEY_ALT = grid.KEY_ALT;
pub const KEY_SUPER = grid.KEY_SUPER;
pub const KEY_ENTER = grid.KEY_ENTER;
pub const KEY_BKSP = grid.KEY_BKSP;
pub const KEY_SPACE = grid.KEY_SPACE;
pub const KEY_ESC = grid.KEY_ESC;
pub const rgb = grid.rgb;
pub const rgba = grid.rgba;
pub const hex = grid.hex;
pub const lnpc_grid = grid.lnpc_grid;
pub const lnpc_nogrid = grid.lnpc_nogrid;
pub const lnpc_bg = grid.lnpc_bg;
pub const lnpc_nobg = grid.lnpc_nobg;
pub const lnpc_char = grid.lnpc_char;
pub const lnpc_nochar = grid.lnpc_nochar;
pub const lnpc_line = grid.lnpc_line;
pub const lnpc_noline = grid.lnpc_noline;

const alloc = std.heap.page_allocator;
const font_data = @embedFile("DepartureMono-Regular.otf");

pub const Window = struct {
    grid: *Grid,
    cell_width: u32,
    cell_height: u32,
    font: c.Font,
    font_size: u32,
    baseline_offset: f32,
};

pub export fn lnpc_window(font_size: u32, g: *Grid) ?*Window {
    // Initialize window
    c.SetConfigFlags(c.FLAG_WINDOW_HIGHDPI | c.FLAG_MSAA_4X_HINT);
    c.InitWindow(
        @intCast(g.width * font_size * 6 / 10),
        @intCast(g.height * font_size),
        "linopic",
    );
    c.SetTargetFPS(60);

    // Load font at 2x size for better glyph quality, then render at target size
    const internal_size: c_int = @intCast(font_size * 2);
    const font = c.LoadFontFromMemory(".otf", font_data, font_data.len, internal_size, null, 0);

    // Calculate cell dimensions based on requested font size (not internal size)
    const scale_factor: f32 = @as(f32, @floatFromInt(font_size)) / @as(f32, @floatFromInt(font.baseSize));
    const glyph_info = c.GetGlyphInfo(font, 'M');
    const raw_advance: f32 = if (glyph_info.advanceX > 0) @floatFromInt(glyph_info.advanceX) else @as(f32, @floatFromInt(font.baseSize)) * 0.6;
    const cell_width: u32 = @intFromFloat(raw_advance * scale_factor);
    const cell_height: u32 = font_size;

    // Resize window to match cell dimensions
    c.SetWindowSize(@intCast(g.width * cell_width), @intCast(g.height * cell_height));

    // Store cell dimensions on grid for mouse coordinate conversion
    g.cell_width = cell_width;
    g.cell_height = cell_height;

    // Use trilinear filtering for smooth downscaled text
    c.SetTextureFilter(font.texture, c.TEXTURE_FILTER_TRILINEAR);

    const window = alloc.create(Window) catch return null;
    window.* = .{
        .grid = g,
        .cell_width = cell_width,
        .cell_height = cell_height,
        .font = font,
        .font_size = font_size,
        .baseline_offset = 0,
    };
    return window;
}

pub export fn lnpc_nowindow(window: ?*Window) void {
    const w = window orelse return;
    c.UnloadFont(w.font);
    c.CloseWindow();
    alloc.destroy(w);
}

pub export fn lnpc_mouse(g: *Grid, button: c_int) grid.MouseEvt {
    const cw = g.cell_width;
    const ch = g.cell_height;
    const mouse_x = c.GetMouseX();
    const mouse_y = c.GetMouseY();

    const ray_button: c_int = switch (button) {
        0 => c.MOUSE_BUTTON_LEFT,
        1 => c.MOUSE_BUTTON_RIGHT,
        2 => c.MOUSE_BUTTON_MIDDLE,
        else => c.MOUSE_BUTTON_LEFT,
    };

    return .{
        .x = if (cw > 0) @divFloor(mouse_x, @as(c_int, @intCast(cw))) else 0,
        .y = if (ch > 0) @divFloor(mouse_y, @as(c_int, @intCast(ch))) else 0,
        .is_down = c.IsMouseButtonDown(ray_button),
        .is_pressed = c.IsMouseButtonPressed(ray_button),
        .is_released = c.IsMouseButtonReleased(ray_button),
    };
}

pub export fn lnpc_key(key: u8) grid.KeyState {
    const ray_key: c_int = switch (key) {
        grid.KEY_SHIFT => c.KEY_LEFT_SHIFT,
        grid.KEY_CTRL => c.KEY_LEFT_CONTROL,
        grid.KEY_ALT => c.KEY_LEFT_ALT,
        grid.KEY_SUPER => c.KEY_LEFT_SUPER,
        grid.KEY_ENTER => c.KEY_ENTER,
        grid.KEY_BKSP => c.KEY_BACKSPACE,
        grid.KEY_SPACE => c.KEY_SPACE,
        grid.KEY_ESC => c.KEY_ESCAPE,
        else => @as(c_int, key),
    };

    return .{
        .is_down = c.IsKeyDown(ray_key),
        .is_pressed = c.IsKeyPressed(ray_key),
        .is_released = c.IsKeyReleased(ray_key),
    };
}

pub export fn lnpc_draw(window: *Window) bool {
    const g = window.grid;
    const cw = window.cell_width;
    const ch = window.cell_height;
    const cwf: f32 = @floatFromInt(cw);
    const chf: f32 = @floatFromInt(ch);
    // Render at requested font size (font is loaded at 2x for quality)
    const fsz: f32 = @floatFromInt(window.font_size);

    c.BeginDrawing();
    defer c.EndDrawing();

    c.ClearBackground(c.WHITE);

    for (0..g.height) |y| {
        for (0..g.width) |x| {
            const i = y * g.width + x;
            const px: c_int = @intCast(x * cw);
            const py: c_int = @intCast(y * ch);

            const bg = g.bgs[i];
            if (bg != 0) {
                c.DrawRectangle(px, py, @intCast(cw), @intCast(ch), ray(bg));
            }

            const char = g.chars[i];
            if (char != 0) {
                var buf: [5]u8 = undefined;
                const len = std.unicode.utf8Encode(@intCast(char), &buf) catch continue;
                buf[len] = 0;
                c.DrawTextEx(window.font, &buf, .{ .x = @floatFromInt(px), .y = @floatFromInt(py) }, fsz, 0, ray(g.fgs[i]));
            }
        }
    }

    for (g.lines) |line| {
        if (!line.active) continue;
        lines.draw(line, cwf, chf);
    }

    return c.WindowShouldClose();
}

fn ray(color: Color) c.Color {
    return .{
        .r = @truncate(color >> 16),
        .g = @truncate(color >> 8),
        .b = @truncate(color),
        .a = @truncate(color >> 24),
    };
}
