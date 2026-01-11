const lnpc = @import("linopic");
const ray = @cImport(@cInclude("raylib.h"));

const WIDTH = 60;
const HEIGHT = 30;

const LineStyle = struct { style: u32, name: []const u8, reverse: bool };

const line_styles = [_]LineStyle{
    .{ .style = 0, .name = "straight", .reverse = false },
    .{ .style = lnpc.LINE_2SEG, .name = "2-seg a->b", .reverse = false },
    .{ .style = lnpc.LINE_2SEG, .name = "2-seg b->a", .reverse = true },
    .{ .style = lnpc.LINE_3SEG, .name = "3-seg a->b", .reverse = false },
    .{ .style = lnpc.LINE_3SEG, .name = "3-seg b->a", .reverse = true },
    .{ .style = lnpc.LINE_2SEG | lnpc.LINE_CORNER_HARD, .name = "2-seg hard a->b", .reverse = false },
    .{ .style = lnpc.LINE_2SEG | lnpc.LINE_CORNER_HARD, .name = "2-seg hard b->a", .reverse = true },
    .{ .style = lnpc.LINE_3SEG | lnpc.LINE_CORNER_HARD, .name = "3-seg hard a->b", .reverse = false },
    .{ .style = lnpc.LINE_3SEG | lnpc.LINE_CORNER_HARD, .name = "3-seg hard b->a", .reverse = true },
};

pub fn main() void {
    const g = lnpc.lnpc_grid(WIDTH, HEIGHT) orelse return;
    defer lnpc.lnpc_nogrid(g);

    const w = lnpc.lnpc_window(20, g) orelse return;
    defer lnpc.lnpc_nowindow(w);

    var selected: usize = 3; // 3-seg a->b (rounded)
    var frame: u32 = 0;

    // Draggable endpoint positions
    var ax: u32 = 10;
    var ay: u32 = 8;
    var bx: u32 = 50;
    var by: u32 = 24;

    // Drag state: 0=none, 1=dragging A, 2=dragging B
    var dragging: u8 = 0;

    while (!lnpc.lnpc_draw(w)) {
        // Mouse input
        const mouse = lnpc.lnpc_mouse(g, 0);
        const mx: u32 = @intCast(@max(0, @min(mouse.x, WIDTH - 1)));
        const my: u32 = @intCast(@max(0, @min(mouse.y, HEIGHT - 1)));

        // Start drag on press
        if (mouse.is_pressed) {
            if (mx == ax and my == ay) {
                dragging = 1;
            } else if (mx == bx and my == by) {
                dragging = 2;
            }
        }

        // Update position while dragging
        if (mouse.is_down and dragging != 0) {
            if (dragging == 1) {
                ax = mx;
                ay = my;
            } else {
                bx = mx;
                by = my;
            }
        }

        // End drag on release
        if (mouse.is_released) {
            dragging = 0;
        }

        // Keyboard input
        if (ray.IsKeyPressed(ray.KEY_UP) or ray.IsKeyPressed(ray.KEY_LEFT)) {
            selected = if (selected == 0) line_styles.len - 1 else selected - 1;
        }
        if (ray.IsKeyPressed(ray.KEY_DOWN) or ray.IsKeyPressed(ray.KEY_RIGHT)) {
            selected = (selected + 1) % line_styles.len;
        }

        // Clear lines
        for (0..64) |i| lnpc.lnpc_noline(g, @intCast(i));

        // Draw gradient background
        for (0..HEIGHT) |y| {
            for (0..WIDTH) |x| {
                const t: f32 = @as(f32, @floatFromInt(y)) / HEIGHT;
                const r: u8 = @intFromFloat(30 + t * 60);
                const b: u8 = @intFromFloat(80 + (1 - t) * 80);
                lnpc.lnpc_bg(g, @intCast(x), @intCast(y), lnpc.rgb(r, 40, b));
            }
        }

        // Mark endpoints
        lnpc.lnpc_bg(g, ax, ay, lnpc.rgb(200, 200, 80));
        lnpc.lnpc_bg(g, bx, by, lnpc.rgb(80, 200, 200));
        lnpc.lnpc_char(g, ax, ay, 'A', lnpc.rgb(0, 0, 0));
        lnpc.lnpc_char(g, bx, by, 'B', lnpc.rgb(0, 0, 0));

        // Title
        const title = "linopic (arrows: cycle, drag: move A/B)";
        for (title, 0..) |ch, i| {
            lnpc.lnpc_char(g, @intCast(10 + i), 2, ch, lnpc.rgb(255, 255, 255));
        }

        // Draw selected line in red
        const sel = line_styles[selected];
        if (sel.reverse) {
            _ = lnpc.lnpc_line(g, bx, by, ax, ay, lnpc.rgb(255, 60, 60), sel.style);
        } else {
            _ = lnpc.lnpc_line(g, ax, ay, bx, by, lnpc.rgb(255, 60, 60), sel.style);
        }

        // Legend
        for (line_styles, 0..) |ls, i| {
            const color = if (i == selected) lnpc.rgb(255, 60, 60) else lnpc.rgb(120, 120, 120);
            const marker: u8 = if (i == selected) '>' else ' ';
            lnpc.lnpc_char(g, 37, @intCast(4 + i), marker, color);
            for (ls.name, 0..) |ch, col| {
                lnpc.lnpc_char(g, @intCast(39 + col), @intCast(4 + i), ch, color);
            }
        }

        frame += 1;
        if (frame == 10) {
            ray.TakeScreenshot("linopic_screenshot.png");
        }
    }
}
