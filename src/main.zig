const std = @import("std");
const lnpc = @import("linopic");
const ray = @cImport(@cInclude("raylib.h"));
const libc = @cImport({
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

const WIDTH = 60;
const HEIGHT = 30;

var current_example: u8 = 1;
var g: *lnpc.Grid = undefined;
var font_size: u32 = 20;

pub fn main() !void {
    g = lnpc.lnpc_grid(WIDTH, HEIGHT) orelse return;
    defer lnpc.lnpc_nogrid(g);

    const stdin_fd: c_int = 0;
    const stdout = std.io.getStdOut().writer();

    const old_flags = libc.fcntl(stdin_fd, libc.F_GETFL, @as(c_int, 0));
    _ = libc.fcntl(stdin_fd, libc.F_SETFL, old_flags | libc.O_NONBLOCK);
    defer _ = libc.fcntl(stdin_fd, libc.F_SETFL, old_flags);

    try stdout.print("Commands: ex1, ex2, ex3, quit | Cmd+/- to resize\n> ", .{});

    var input_buf: [64]u8 = undefined;
    var input_len: usize = 0;

    setupExample(current_example);

    var w = lnpc.lnpc_window(font_size, g) orelse return;

    while (!lnpc.lnpc_draw(w)) {
        const super = ray.IsKeyDown(ray.KEY_LEFT_SUPER) or ray.IsKeyDown(ray.KEY_RIGHT_SUPER);
        if (super and ray.IsKeyPressed(ray.KEY_EQUAL)) {
            font_size = @min(font_size + 2, 48);
            lnpc.lnpc_nowindow(w);
            w = lnpc.lnpc_window(font_size, g) orelse return;
        }
        if (super and ray.IsKeyPressed(ray.KEY_MINUS)) {
            font_size = @max(font_size -| 2, 8);
            lnpc.lnpc_nowindow(w);
            w = lnpc.lnpc_window(font_size, g) orelse return;
        }

        const n = libc.read(stdin_fd, &input_buf[input_len], input_buf.len - input_len);
        if (n <= 0) continue;
        input_len += @intCast(n);

        while (std.mem.indexOf(u8, input_buf[0..input_len], "\n")) |nl| {
            const cmd = std.mem.trim(u8, input_buf[0..nl], " \t\r");
            if (std.mem.eql(u8, cmd, "quit")) {
                lnpc.lnpc_nowindow(w);
                return;
            }
            if (std.mem.eql(u8, cmd, "ex1")) setupExample(1);
            if (std.mem.eql(u8, cmd, "ex2")) setupExample(2);
            if (std.mem.eql(u8, cmd, "ex3")) setupExample(3);
            std.mem.copyForwards(u8, &input_buf, input_buf[nl + 1 .. input_len]);
            input_len -= nl + 1;
            try stdout.print("> ", .{});
        }
    }
    lnpc.lnpc_nowindow(w);
}

fn clearGrid() void {
    for (0..HEIGHT) |y| {
        for (0..WIDTH) |x| {
            lnpc.lnpc_nobg(g, @intCast(x), @intCast(y));
            lnpc.lnpc_nochar(g, @intCast(x), @intCast(y));
        }
    }
    for (0..256) |i| {
        lnpc.lnpc_noline(g, @intCast(i));
    }
}

fn setupExample(ex: u8) void {
    current_example = ex;
    clearGrid();
    switch (ex) {
        1 => ex1(),
        2 => ex2(),
        3 => ex3(),
        else => {},
    }
}

fn ex1() void {
    _ = lnpc.lnpc_line(g, 10, 10, 50, 10, 64, 0xFF0000);
    _ = lnpc.lnpc_line(g, 10, 10, 50, 10, -64, 0x0000FF);

    const msg = "bendiness: 64 vs -64";
    for (msg, 0..) |c, i| {
        lnpc.lnpc_char(g, @intCast(20 + i), 15, c, 0x000000);
    }
}

fn ex2() void {
    _ = lnpc.lnpc_line(g, 15, 8, 45, 8, 127, 0x00AA00);
    _ = lnpc.lnpc_line(g, 45, 8, 45, 22, 127, 0x00AA00);
    _ = lnpc.lnpc_line(g, 45, 22, 15, 22, 127, 0x00AA00);
    _ = lnpc.lnpc_line(g, 15, 22, 15, 8, 127, 0x00AA00);

    const msg = "rounded rectangle";
    for (msg, 0..) |c, i| {
        lnpc.lnpc_char(g, @intCast(22 + i), 15, c, 0x000000);
    }
}

fn ex3() void {
    for (0..HEIGHT) |y| {
        for (0..WIDTH) |x| {
            const t: f32 = @as(f32, @floatFromInt(y)) / HEIGHT;
            const r: u8 = @intFromFloat(40 + t * 80);
            const b: u8 = @intFromFloat(120 + (1 - t) * 80);
            lnpc.lnpc_bg(g, @intCast(x), @intCast(y), lnpc.rgb(r, 50, b));
        }
    }

    _ = lnpc.lnpc_line(g, 10, 15, 50, 15, 0, 0xFFFFFF);
    _ = lnpc.lnpc_line(g, 10, 15, 50, 15, 50, 0xFFFF00);
    _ = lnpc.lnpc_line(g, 10, 15, 50, 15, 100, 0xFF00FF);
    _ = lnpc.lnpc_line(g, 10, 15, 50, 15, -50, 0x00FFFF);
    _ = lnpc.lnpc_line(g, 10, 15, 50, 15, -100, 0x00FF00);

    const msg = "gradient + multiple curves";
    for (msg, 0..) |c, i| {
        lnpc.lnpc_char(g, @intCast(17 + i), 25, c, 0xFFFFFF);
    }
}
