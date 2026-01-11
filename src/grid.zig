const std = @import("std");

const alloc = std.heap.page_allocator;

pub const Color = u32;

pub const Line = struct {
    ax: u32,
    ay: u32,
    bx: u32,
    by: u32,
    bendiness: i8,
    color: Color,
    active: bool,
};

pub const Grid = struct {
    width: u32,
    height: u32,
    chars: []u32,
    fgs: []Color,
    bgs: []Color,
    lines: []Line,
};

pub export fn rgb(r: u8, g: u8, b: u8) Color {
    return @as(u32, r) << 16 | @as(u32, g) << 8 | b;
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
    @memset(lines, Line{ .ax = 0, .ay = 0, .bx = 0, .by = 0, .bendiness = 0, .color = 0, .active = false });
    const grid = alloc.create(Grid) catch {
        alloc.free(chars);
        alloc.free(fgs);
        alloc.free(bgs);
        alloc.free(lines);
        return null;
    };
    grid.* = .{ .width = w, .height = h, .chars = chars, .fgs = fgs, .bgs = bgs, .lines = lines };
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

pub export fn lnpc_line(grid: *Grid, ax: u32, ay: u32, bx: u32, by: u32, bendiness: i8, color: Color) u32 {
    for (grid.lines, 0..) |*line, i| {
        if (!line.active) {
            line.* = .{ .ax = ax, .ay = ay, .bx = bx, .by = by, .bendiness = bendiness, .color = color, .active = true };
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
    try std.testing.expectEqual(@as(Color, 0xFF0000), rgb(255, 0, 0));
    try std.testing.expectEqual(@as(Color, 0x00FF00), rgb(0, 255, 0));
    try std.testing.expectEqual(@as(Color, 0x0000FF), rgb(0, 0, 255));
    try std.testing.expectEqual(@as(Color, 0x123456), rgb(0x12, 0x34, 0x56));
}

test "char" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);

    lnpc_char(g, 5, 5, 'A', 0xFF0000);
    try std.testing.expectEqual(@as(u32, 'A'), g.chars[55]);
    try std.testing.expectEqual(@as(Color, 0xFF0000), g.fgs[55]);

    lnpc_nochar(g, 5, 5);
    try std.testing.expectEqual(@as(u32, 0), g.chars[55]);
}

test "bg" {
    const g = lnpc_grid(10, 10) orelse return error.Failed;
    defer lnpc_nogrid(g);

    try std.testing.expectEqual(@as(Color, 0), g.bgs[0]);

    lnpc_bg(g, 0, 0, 0x6496C8);
    try std.testing.expectEqual(@as(Color, 0x6496C8), g.bgs[0]);

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
