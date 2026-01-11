const std = @import("std");

const alloc = std.heap.page_allocator;

pub const Color = u32;

// LineStyle flags (combinable via bitwise OR)
pub const LINE_2SEG: u32 = 0x00000001; // 2 segment line, run then rise
pub const LINE_3SEG: u32 = 0x00000002; // 3 segment line, run then rise then run
pub const LINE_CORNER_HARD: u32 = 0x00000010; // hard-edges
pub const LINE_CORNER_NONE: u32 = 0x00000020; // no corners, smooth bend
pub const LINE_BIAS_START: u32 = 0x00000100; // bias towards startpoint
pub const LINE_BIAS_END: u32 = 0x0000c000; // bias towards endpoint

pub const MouseEvt = extern struct {
    x: i32,
    y: i32,
    is_down: bool,
    is_pressed: bool,
    is_released: bool,
};

pub const KeyState = extern struct {
    is_down: bool,
    is_pressed: bool,
    is_released: bool,
};

// Key constants
pub const KEY_SHIFT: u8 = 0x01;
pub const KEY_CTRL: u8 = 0x02;
pub const KEY_ALT: u8 = 0x04;
pub const KEY_SUPER: u8 = 0x08;
pub const KEY_ENTER: u8 = 0x10;
pub const KEY_BKSP: u8 = 0x20;
pub const KEY_SPACE: u8 = 0x40;
pub const KEY_ESC: u8 = 0x80;

pub const Line = struct {
    ax: u32,
    ay: u32,
    bx: u32,
    by: u32,
    style: u32,
    color: Color,
    active: bool,
};

pub const Grid = struct {
    width: u32,
    height: u32,
    cell_width: u32,
    cell_height: u32,
    chars: []u32,
    fgs: []Color,
    bgs: []Color,
    lines: []Line,
};

pub export fn rgb(r: u8, g: u8, b: u8) Color {
    return 0xFF000000 | @as(u32, r) << 16 | @as(u32, g) << 8 | b;
}

pub export fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
    return @as(u32, a) << 24 | @as(u32, r) << 16 | @as(u32, g) << 8 | b;
}

pub export fn hex(str: [*:0]const u8) Color {
    var i: usize = 0;
    if (str[0] == '#') i = 1;
    var result: Color = 0;
    var digit_count: usize = 0;
    while (str[i] != 0 and digit_count < 8) : (i += 1) {
        const char = str[i];
        const digit: u8 = if (char >= '0' and char <= '9')
            char - '0'
        else if (char >= 'a' and char <= 'f')
            char - 'a' + 10
        else if (char >= 'A' and char <= 'F')
            char - 'A' + 10
        else
            break;
        result = (result << 4) | digit;
        digit_count += 1;
    }
    // Add full alpha for 6-digit (RGB) hex codes
    if (digit_count == 6) {
        result |= 0xFF000000;
    }
    return result;
}

const MAX_LINES = 256;

pub export fn lnpc_grid(w: u32, h: u32) ?*Grid {
    const n = w * h;
    const chars = alloc.alloc(u32, n) catch return null;
    @memset(chars, 0);
    const fgs = alloc.alloc(Color, n) catch {
        alloc.free(chars);
        return null;
    };
    @memset(fgs, 0);
    const bgs = alloc.alloc(Color, n) catch {
        alloc.free(chars);
        alloc.free(fgs);
        return null;
    };
    @memset(bgs, 0);
    const lines = alloc.alloc(Line, MAX_LINES) catch {
        alloc.free(chars);
        alloc.free(fgs);
        alloc.free(bgs);
        return null;
    };
    @memset(lines, Line{ .ax = 0, .ay = 0, .bx = 0, .by = 0, .style = 0, .color = 0, .active = false });
    const grid = alloc.create(Grid) catch {
        alloc.free(chars);
        alloc.free(fgs);
        alloc.free(bgs);
        alloc.free(lines);
        return null;
    };
    grid.* = .{ .width = w, .height = h, .cell_width = 0, .cell_height = 0, .chars = chars, .fgs = fgs, .bgs = bgs, .lines = lines };
    return grid;
}

pub export fn lnpc_nogrid(grid: ?*Grid) void {
    const g = grid orelse return;
    alloc.free(g.chars);
    alloc.free(g.fgs);
    alloc.free(g.bgs);
    alloc.free(g.lines);
    alloc.destroy(g);
}

pub export fn lnpc_line(grid: *Grid, ax: u32, ay: u32, bx: u32, by: u32, color: Color, style: u32) u32 {
    for (grid.lines, 0..) |*line, i| {
        if (!line.active) {
            line.* = .{ .ax = ax, .ay = ay, .bx = bx, .by = by, .style = style, .color = color, .active = true };
            return @intCast(i);
        }
    }
    return 0xFFFFFFFF;
}

pub export fn lnpc_noline(grid: *Grid, id: u32) void {
    if (id < grid.lines.len) {
        grid.lines[id].active = false;
    }
}

pub export fn lnpc_bg(grid: *Grid, x: u32, y: u32, color: Color) void {
    if (x >= grid.width or y >= grid.height) return;
    grid.bgs[y * grid.width + x] = color;
}

pub export fn lnpc_nobg(grid: *Grid, x: u32, y: u32) void {
    if (x >= grid.width or y >= grid.height) return;
    grid.bgs[y * grid.width + x] = 0;
}

pub export fn lnpc_char(grid: *Grid, x: u32, y: u32, char: u32, color: Color) void {
    if (x >= grid.width or y >= grid.height) return;
    grid.chars[y * grid.width + x] = char;
    grid.fgs[y * grid.width + x] = color;
}

pub export fn lnpc_nochar(grid: *Grid, x: u32, y: u32) void {
    if (x >= grid.width or y >= grid.height) return;
    grid.chars[y * grid.width + x] = 0;
}

test "grid create and destroy" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);
    try std.testing.expectEqual(@as(u32, 10), g.width);
    try std.testing.expectEqual(@as(u32, 10), g.height);
}

test "rgb" {
    try std.testing.expectEqual(@as(Color, 0xFFFF0000), rgb(255, 0, 0));
    try std.testing.expectEqual(@as(Color, 0xFF00FF00), rgb(0, 255, 0));
    try std.testing.expectEqual(@as(Color, 0xFF0000FF), rgb(0, 0, 255));
    try std.testing.expectEqual(@as(Color, 0xFF123456), rgb(0x12, 0x34, 0x56));
}

test "rgba" {
    try std.testing.expectEqual(@as(Color, 0x80FF0000), rgba(255, 0, 0, 0x80));
    try std.testing.expectEqual(@as(Color, 0x00123456), rgba(0x12, 0x34, 0x56, 0x00));
}

test "hex" {
    try std.testing.expectEqual(@as(Color, 0xFFFF0000), hex("FF0000"));
    try std.testing.expectEqual(@as(Color, 0xFFFF0000), hex("#FF0000"));
    try std.testing.expectEqual(@as(Color, 0xAABBCCDD), hex("AABBCCDD"));
}

test "char" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);

    const red = rgb(255, 0, 0);
    lnpc_char(g, 5, 5, 'A', red);
    try std.testing.expectEqual(@as(u32, 'A'), g.chars[55]);
    try std.testing.expectEqual(red, g.fgs[55]);

    lnpc_nochar(g, 5, 5);
    try std.testing.expectEqual(@as(u32, 0), g.chars[55]);
}

test "bg" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);

    try std.testing.expectEqual(@as(Color, 0), g.bgs[0]);

    const blue = rgb(0x64, 0x96, 0xC8);
    lnpc_bg(g, 0, 0, blue);
    try std.testing.expectEqual(blue, g.bgs[0]);

    lnpc_nobg(g, 0, 0);
    try std.testing.expectEqual(@as(Color, 0), g.bgs[0]);
}

test "bounds" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);

    lnpc_char(g, 100, 100, 'X', 0x000000);
    lnpc_bg(g, 100, 100, 0x000000);
    lnpc_nochar(g, 100, 100);
    lnpc_nobg(g, 100, 100);
}
