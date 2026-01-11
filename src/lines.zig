const std = @import("std");
const c = @cImport(@cInclude("raylib.h"));
const grid = @import("grid.zig");

const SEG_2 = grid.LINE_2SEG;
const SEG_3 = grid.LINE_3SEG;
const CORNER_HARD = grid.LINE_CORNER_HARD;

pub fn draw(line: grid.Line, cw: f32, ch: f32) void {
    const x1: f32 = (@as(f32, @floatFromInt(line.ax)) + 0.5) * cw;
    const y1: f32 = (@as(f32, @floatFromInt(line.ay)) + 0.5) * ch;
    const x2: f32 = (@as(f32, @floatFromInt(line.bx)) + 0.5) * cw;
    const y2: f32 = (@as(f32, @floatFromInt(line.by)) + 0.5) * ch;

    const style = line.style;
    const color = ray(line.color);
    const thickness: f32 = 2.0;

    if (style & (SEG_2 | SEG_3) == 0) {
        c.DrawLineEx(.{ .x = x1, .y = y1 }, .{ .x = x2, .y = y2 }, thickness, color);
        return;
    }

    const hard = style & CORNER_HARD != 0;
    const r: f32 = if (hard) 0 else @min(@abs(x2 - x1), @abs(y2 - y1)) * 0.2;

    if (style & SEG_2 != 0) {
        draw2Seg(x1, y1, x2, y2, r, thickness, color);
    } else {
        draw3Seg(x1, y1, x2, y2, r, thickness, color);
    }
}

fn draw2Seg(x1: f32, y1: f32, x2: f32, y2: f32, r: f32, thickness: f32, color: c.Color) void {
    const cx = x2;
    const cy = y1;

    if (r > 0) {
        const rx = if (x2 > x1) -r else r;
        const ry = if (y2 > y1) r else -r;
        c.DrawLineEx(.{ .x = x1, .y = y1 }, .{ .x = cx + rx, .y = cy }, thickness, color);
        arc(cx + rx, cy, cx, cy + ry, cx + rx, cy + ry, thickness, color);
        c.DrawLineEx(.{ .x = cx, .y = cy + ry }, .{ .x = x2, .y = y2 }, thickness, color);
    } else {
        c.DrawLineEx(.{ .x = x1, .y = y1 }, .{ .x = cx, .y = cy }, thickness, color);
        c.DrawLineEx(.{ .x = cx, .y = cy }, .{ .x = x2, .y = y2 }, thickness, color);
    }
}

fn draw3Seg(x1: f32, y1: f32, x2: f32, y2: f32, r: f32, thickness: f32, color: c.Color) void {
    // 3-segment: horizontal, vertical, horizontal (matches 2-seg pattern)
    const mid_x = (x1 + x2) / 2;

    if (r > 0) {
        const sx1: f32 = if (mid_x > x1) 1 else -1;
        const sy: f32 = if (y2 > y1) 1 else -1;
        const sx2: f32 = if (x2 > mid_x) 1 else -1;

        // First corner at (mid_x, y1)
        const c1x = mid_x - sx1 * r;
        const c1y = y1 + sy * r;
        const h1_end = mid_x - sx1 * r;
        const v_start = y1 + sy * r;

        // Second corner at (mid_x, y2)
        const c2x = mid_x + sx2 * r;
        const c2y = y2 - sy * r;
        const v_end = y2 - sy * r;
        const h2_start = mid_x + sx2 * r;

        c.DrawLineEx(.{ .x = x1, .y = y1 }, .{ .x = h1_end, .y = y1 }, thickness, color);
        arc(h1_end, y1, mid_x, v_start, c1x, c1y, thickness, color);
        c.DrawLineEx(.{ .x = mid_x, .y = v_start }, .{ .x = mid_x, .y = v_end }, thickness, color);
        arc(mid_x, v_end, h2_start, y2, c2x, c2y, thickness, color);
        c.DrawLineEx(.{ .x = h2_start, .y = y2 }, .{ .x = x2, .y = y2 }, thickness, color);
    } else {
        c.DrawLineEx(.{ .x = x1, .y = y1 }, .{ .x = mid_x, .y = y1 }, thickness, color);
        c.DrawLineEx(.{ .x = mid_x, .y = y1 }, .{ .x = mid_x, .y = y2 }, thickness, color);
        c.DrawLineEx(.{ .x = mid_x, .y = y2 }, .{ .x = x2, .y = y2 }, thickness, color);
    }
}

fn arc(sx: f32, sy: f32, ex: f32, ey: f32, cx: f32, cy: f32, thickness: f32, color: c.Color) void {
    const pi = std.math.pi;
    const start = std.math.atan2(sy - cy, sx - cx);
    const end = std.math.atan2(ey - cy, ex - cx);
    var sweep = end - start;
    if (sweep > pi) sweep -= 2 * pi;
    if (sweep < -pi) sweep += 2 * pi;

    const r = @sqrt((sx - cx) * (sx - cx) + (sy - cy) * (sy - cy));
    var px = sx;
    var py = sy;

    for (1..9) |i| {
        const t = @as(f32, @floatFromInt(i)) / 8.0;
        const a = start + t * sweep;
        const nx = cx + r * @cos(a);
        const ny = cy + r * @sin(a);
        c.DrawLineEx(.{ .x = px, .y = py }, .{ .x = nx, .y = ny }, thickness, color);
        px = nx;
        py = ny;
    }
}

fn ray(color: grid.Color) c.Color {
    return .{
        .r = @truncate(color >> 16),
        .g = @truncate(color >> 8),
        .b = @truncate(color),
        .a = @truncate(color >> 24),
    };
}
