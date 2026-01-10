const lnpc = @import("linopic");

pub fn main() void {
    const g = lnpc.lnpc_grid(40, 20) orelse return;
    defer lnpc.lnpc_nogrid(g);

    // "Hello, linopic!"
    const msg = "Hello, linopic!";
    const black = lnpc.Color{ .r = 0, .g = 0, .b = 0 };
    const blue = lnpc.Color{ .r = 40, .g = 40, .b = 80 };
    for (msg, 0..) |char, i| {
        lnpc.lnpc_bg(g, @intCast(2 + i), 2, blue);
        lnpc.lnpc_char(g, @intCast(2 + i), 2, char, black);
    }

    const w = lnpc.lnpc_window(24, g) orelse return;
    defer _ = lnpc.lnpc_nowindow(w);

    while (!lnpc.lnpc_draw(w)) {}
}
