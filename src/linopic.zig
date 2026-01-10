const std = @import("std");
const c = @cImport(@cInclude("raylib.h"));

const font_data = @embedFile("font.ttf");
const alloc = std.heap.page_allocator;

// =============================================================================
// Types
// =============================================================================

pub const Line = u32;

pub const Color = extern struct {
    r: u8,
    g: u8,
    b: u8,
};

const Cell = struct {
    char: u32 = 0,
    fg: Color = .{ .r = 0, .g = 0, .b = 0 },
    bg: ?Color = null,
};

pub const Linopic = struct {
    width: u32,
    height: u32,
    cells: []Cell,
};

pub const Window = struct {
    linopic: *Linopic,
    cell_width: u32,
    cell_height: u32,
    font: c.Font,
};

// =============================================================================
// C ABI
// =============================================================================

pub export fn lnpc_grid(w: u32, h: u32) ?*Linopic {
    const cells = alloc.alloc(Cell, w * h) catch return null;
    @memset(cells, Cell{});
    const linopic = alloc.create(Linopic) catch {
        alloc.free(cells);
        return null;
    };
    linopic.* = .{ .width = w, .height = h, .cells = cells };
    return linopic;
}

pub export fn lnpc_nogrid(linopic: ?*Linopic) void {
    const l = linopic orelse return;
    alloc.free(l.cells);
    alloc.destroy(l);
}

pub export fn lnpc_window(font_size: u32, linopic: *Linopic) ?*Window {
    const cell_width = font_size * 6 / 10;
    const cell_height = font_size;

    c.InitWindow(
        @intCast(linopic.width * cell_width),
        @intCast(linopic.height * cell_height),
        "linopic",
    );

    const font = c.LoadFontFromMemory(".ttf", font_data, font_data.len, @intCast(font_size), null, 0);
    c.SetTextureFilter(font.texture, c.TEXTURE_FILTER_POINT);

    const window = alloc.create(Window) catch return null;
    window.* = .{
        .linopic = linopic,
        .cell_width = cell_width,
        .cell_height = cell_height,
        .font = font,
    };
    return window;
}

pub export fn lnpc_nowindow(window: ?*Window) bool {
    const w = window orelse return false;
    c.UnloadFont(w.font);
    c.CloseWindow();
    alloc.destroy(w);
    return true;
}

pub export fn lnpc_draw(window: *Window) bool {
    const l = window.linopic;
    const cw = window.cell_width;
    const ch = window.cell_height;
    const fsz: f32 = @floatFromInt(ch);

    c.BeginDrawing();
    defer c.EndDrawing();

    c.ClearBackground(c.WHITE);

    for (0..l.height) |y| {
        for (0..l.width) |x| {
            const cell = l.cells[y * l.width + x];
            const px: c_int = @intCast(x * cw);
            const py: c_int = @intCast(y * ch);

            if (cell.bg) |bg| {
                c.DrawRectangle(px, py, @intCast(cw), @intCast(ch), ray(bg));
            }

            if (cell.char != 0) {
                var buf: [5]u8 = undefined;
                const len = std.unicode.utf8Encode(@intCast(cell.char), &buf) catch continue;
                buf[len] = 0;
                c.DrawTextEx(window.font, &buf, .{ .x = @floatFromInt(px), .y = @floatFromInt(py) }, fsz, 0, ray(cell.fg));
            }
        }
    }

    return c.WindowShouldClose();
}

pub export fn lnpc_bg(linopic: *Linopic, x: u32, y: u32, color: Color) void {
    if (x >= linopic.width or y >= linopic.height) return;
    linopic.cells[y * linopic.width + x].bg = color;
}

pub export fn lnpc_nobg(linopic: *Linopic, x: u32, y: u32) void {
    if (x >= linopic.width or y >= linopic.height) return;
    linopic.cells[y * linopic.width + x].bg = null;
}

pub export fn lnpc_char(linopic: *Linopic, x: u32, y: u32, char: u32, color: Color) void {
    if (x >= linopic.width or y >= linopic.height) return;
    linopic.cells[y * linopic.width + x].char = char;
    linopic.cells[y * linopic.width + x].fg = color;
}

pub export fn lnpc_nochar(linopic: *Linopic, x: u32, y: u32) void {
    if (x >= linopic.width or y >= linopic.height) return;
    linopic.cells[y * linopic.width + x].char = 0;
}

// No-op for now
pub export fn lnpc_line(linopic: *Linopic, ax: u32, ay: u32, bx: u32, by: u32, bendiness: i8) Line {
    _ = linopic;
    _ = ax;
    _ = ay;
    _ = bx;
    _ = by;
    _ = bendiness;
    return 0;
}

pub export fn lnpc_noline(linopic: *Linopic, line: Line) void {
    _ = linopic;
    _ = line;
}

pub export fn lnpc_subgrid(parent: *Linopic, child: *Linopic, x: u32, y: u32, w: u32, h: u32) bool {
    _ = parent;
    _ = child;
    _ = x;
    _ = y;
    _ = w;
    _ = h;
    return false;
}

pub export fn lnpc_nosubgrid(parent: *Linopic, child: *Linopic) bool {
    _ = parent;
    _ = child;
    return false;
}

fn ray(color: Color) c.Color {
    return .{ .r = color.r, .g = color.g, .b = color.b, .a = 255 };
}

// =============================================================================
// Tests
// =============================================================================

test "grid create and destroy" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);
    try std.testing.expectEqual(@as(u32, 10), g.width);
    try std.testing.expectEqual(@as(u32, 10), g.height);
}

test "char" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);

    lnpc_char(g, 5, 5, 'A', .{ .r = 255, .g = 0, .b = 0 });
    try std.testing.expectEqual(@as(u32, 'A'), g.cells[55].char);
    try std.testing.expectEqual(@as(u8, 255), g.cells[55].fg.r);

    lnpc_nochar(g, 5, 5);
    try std.testing.expectEqual(@as(u32, 0), g.cells[55].char);
}

test "bg" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);

    try std.testing.expect(g.cells[0].bg == null);

    lnpc_bg(g, 0, 0, .{ .r = 100, .g = 150, .b = 200 });
    try std.testing.expectEqual(@as(u8, 100), g.cells[0].bg.?.r);

    lnpc_nobg(g, 0, 0);
    try std.testing.expect(g.cells[0].bg == null);
}

test "out of bounds" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);

    // Should not crash
    lnpc_char(g, 100, 100, 'X', .{ .r = 0, .g = 0, .b = 0 });
    lnpc_bg(g, 100, 100, .{ .r = 0, .g = 0, .b = 0 });
    lnpc_nochar(g, 100, 100);
    lnpc_nobg(g, 100, 100);
}

test "line no-op" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);

    const line = lnpc_line(g, 0, 0, 5, 5, 0);
    try std.testing.expectEqual(@as(Line, 0), line);
    lnpc_noline(g, line);
}
