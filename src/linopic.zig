const std = @import("std");
const c = @cImport(@cInclude("raylib.h"));
const grid = @import("grid.zig");

pub const Grid = grid.Grid;
pub const Color = grid.Color;
pub const Line = grid.Line;
pub const rgb = grid.rgb;
pub const lnpc_grid = grid.lnpc_grid;
pub const lnpc_nogrid = grid.lnpc_nogrid;
pub const lnpc_bg = grid.lnpc_bg;
pub const lnpc_nobg = grid.lnpc_nobg;
pub const lnpc_char = grid.lnpc_char;
pub const lnpc_nochar = grid.lnpc_nochar;
pub const lnpc_line = grid.lnpc_line;
pub const lnpc_noline = grid.lnpc_noline;

const alloc = std.heap.page_allocator;
const font_data = @embedFile("font.ttf");

pub const Window = struct {
    grid: *Grid,
    cell_width: u32,
    cell_height: u32,
    font: c.Font,
};

pub export fn lnpc_window(font_size: u32, g: *Grid) ?*Window {
    const cell_width = font_size * 6 / 10;
    const cell_height = font_size;

    c.InitWindow(
        @intCast(g.width * cell_width),
        @intCast(g.height * cell_height),
        "linopic",
    );
    c.SetTargetFPS(60);

    const font = c.LoadFontFromMemory(".ttf", font_data, font_data.len, @intCast(font_size), null, 0);
    c.SetTextureFilter(font.texture, c.TEXTURE_FILTER_BILINEAR);

    const window = alloc.create(Window) catch return null;
    window.* = .{
        .grid = g,
        .cell_width = cell_width,
        .cell_height = cell_height,
        .font = font,
    };
    return window;
}

pub export fn lnpc_nowindow(window: ?*Window) void {
    const w = window orelse return;
    c.UnloadFont(w.font);
    c.CloseWindow();
    alloc.destroy(w);
}

pub export fn lnpc_draw(window: *Window) bool {
    const g = window.grid;
    const cw = window.cell_width;
    const ch = window.cell_height;
    const fsz: f32 = @floatFromInt(ch);
    const cwf: f32 = @floatFromInt(cw);
    const chf: f32 = @floatFromInt(ch);

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
        drawBezier(line, cwf, chf);
    }

    return c.WindowShouldClose();
}

fn drawBezier(line: grid.Line, cw: f32, ch: f32) void {
    const ax: f32 = (@as(f32, @floatFromInt(line.ax)) + 0.5) * cw;
    const ay: f32 = (@as(f32, @floatFromInt(line.ay)) + 0.5) * ch;
    const bx: f32 = (@as(f32, @floatFromInt(line.bx)) + 0.5) * cw;
    const by: f32 = (@as(f32, @floatFromInt(line.by)) + 0.5) * ch;

    const dx = bx - ax;
    const dy = by - ay;
    const len = @sqrt(dx * dx + dy * dy);
    if (len == 0) return;

    const nx = -dy / len;
    const ny = dx / len;

    const bend: f32 = @as(f32, @floatFromInt(line.bendiness)) / 127.0;
    const offset = bend * len * 0.5;

    const cx = (ax + bx) / 2 + nx * offset;
    const cy = (ay + by) / 2 + ny * offset;

    const steps: u32 = @max(16, @as(u32, @intFromFloat(len / 4)));
    var prev_x = ax;
    var prev_y = ay;

    for (1..steps + 1) |i| {
        const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        const inv = 1 - t;
        const px = inv * inv * ax + 2 * inv * t * cx + t * t * bx;
        const py = inv * inv * ay + 2 * inv * t * cy + t * t * by;
        c.DrawLineEx(.{ .x = prev_x, .y = prev_y }, .{ .x = px, .y = py }, 2, ray(line.color));
        prev_x = px;
        prev_y = py;
    }
}

fn ray(color: Color) c.Color {
    return .{
        .r = @truncate(color >> 16),
        .g = @truncate(color >> 8),
        .b = @truncate(color),
        .a = 255,
    };
}
