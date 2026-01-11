const std = @import("std");
const lnpc = @import("linopic");
const ray = @cImport(@cInclude("raylib.h"));
const libc = @cImport({
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
});

const WIDTH = 120;
const HEIGHT = 40;
const DIVIDER = 60;
const GUTTER = 4;
const MAX_LINES = 256;
const MAX_LINE_LEN = 256;

const Theme = struct {
    bg: lnpc.Color = 0x1e1e2e,
    fg: lnpc.Color = 0xcdd6f4,
    gutter_bg: lnpc.Color = 0x181825,
    gutter_fg: lnpc.Color = 0x6c7086,
    divider: lnpc.Color = 0x313244,
    cursor_line: lnpc.Color = 0x2a2b3d,
    keyword: lnpc.Color = 0xcba6f7,
    string: lnpc.Color = 0xa6e3a1,
    comment: lnpc.Color = 0x6c7086,
    number: lnpc.Color = 0xfab387,
    output_bg: lnpc.Color = 0x11111b,
    status_bg: lnpc.Color = 0x313244,
    status_fg: lnpc.Color = 0xcdd6f4,
};

const theme = Theme{};

var g: *lnpc.Grid = undefined;
var cursor_x: u32 = 0;
var cursor_y: u32 = 0;

var lines: [MAX_LINES][MAX_LINE_LEN]u8 = undefined;
var line_lens: [MAX_LINES]u32 = [_]u32{0} ** MAX_LINES;
var line_count: u32 = 1;

var dbg_show_cells: bool = false;

const sample_output =
    \\> zig build run
    \\hello: 84
    \\
    \\[Process exited 0]
;

pub fn main() !void {
    g = lnpc.lnpc_grid(WIDTH, HEIGHT) orelse return;
    defer lnpc.lnpc_nogrid(g);

    initBuffer();

    const stdin_fd: c_int = 0;
    const stdout = std.io.getStdOut().writer();

    const old_flags = libc.fcntl(stdin_fd, libc.F_GETFL, @as(c_int, 0));
    _ = libc.fcntl(stdin_fd, libc.F_SETFL, old_flags | libc.O_NONBLOCK);
    defer _ = libc.fcntl(stdin_fd, libc.F_SETFL, old_flags);

    try stdout.print("Commands: dbg_showcells, quit\n> ", .{});

    var repl_buf: [64]u8 = undefined;
    var repl_len: usize = 0;

    const w = lnpc.lnpc_window(18, g) orelse return;
    defer lnpc.lnpc_nowindow(w);

    while (!lnpc.lnpc_draw(w)) {
        handleInput();
        render();

        const n = libc.read(stdin_fd, &repl_buf[repl_len], repl_buf.len - repl_len);
        if (n > 0) {
            repl_len += @intCast(n);
            while (std.mem.indexOf(u8, repl_buf[0..repl_len], "\n")) |nl| {
                const cmd = std.mem.trim(u8, repl_buf[0..nl], " \t\r");
                handleCommand(cmd);
                std.mem.copyForwards(u8, &repl_buf, repl_buf[nl + 1 .. repl_len]);
                repl_len -= nl + 1;
                stdout.print("> ", .{}) catch {};
            }
        }
    }
}

fn handleCommand(cmd: []const u8) void {
    if (std.mem.eql(u8, cmd, "dbg_showcells")) {
        dbg_show_cells = !dbg_show_cells;
        setupCellGrid();
    } else if (std.mem.eql(u8, cmd, "quit")) {
        std.process.exit(0);
    }
}

fn setupCellGrid() void {
    for (0..256) |i| lnpc.lnpc_noline(g, @intCast(i));

    if (!dbg_show_cells) return;

    var line_idx: u32 = 0;
    for (0..HEIGHT + 1) |y| {
        if (line_idx >= 256) break;
        _ = lnpc.lnpc_line(g, 0, @intCast(y), WIDTH - 1, @intCast(y), 0, 0x444444);
        line_idx += 1;
    }
    for (0..WIDTH + 1) |x| {
        if (line_idx >= 256) break;
        _ = lnpc.lnpc_line(g, @intCast(x), 0, @intCast(x), HEIGHT - 1, 0, 0x444444);
        line_idx += 1;
    }
}

fn initBuffer() void {
    const initial =
        \\fn main() void {
        \\    const x = 42;
        \\    const msg = "hello";
        \\
        \\    // compute result
        \\    std.debug.print("{s}: {}\n", .{
        \\        msg,
        \\        x * 2,
        \\    });
        \\}
    ;
    var src = std.mem.splitScalar(u8, initial, '\n');
    line_count = 0;
    while (src.next()) |line| : (line_count += 1) {
        if (line_count >= MAX_LINES) break;
        const len = @min(line.len, MAX_LINE_LEN);
        @memcpy(lines[line_count][0..len], line[0..len]);
        line_lens[line_count] = @intCast(len);
    }
}

fn handleInput() void {
    if (ray.IsKeyPressed(ray.KEY_UP)) {
        if (cursor_y > 0) cursor_y -= 1;
        cursor_x = @min(cursor_x, line_lens[cursor_y]);
    }
    if (ray.IsKeyPressed(ray.KEY_DOWN)) {
        if (cursor_y + 1 < line_count) cursor_y += 1;
        cursor_x = @min(cursor_x, line_lens[cursor_y]);
    }
    if (ray.IsKeyPressed(ray.KEY_LEFT)) {
        if (cursor_x > 0) {
            cursor_x -= 1;
        } else if (cursor_y > 0) {
            cursor_y -= 1;
            cursor_x = line_lens[cursor_y];
        }
    }
    if (ray.IsKeyPressed(ray.KEY_RIGHT)) {
        if (cursor_x < line_lens[cursor_y]) {
            cursor_x += 1;
        } else if (cursor_y + 1 < line_count) {
            cursor_y += 1;
            cursor_x = 0;
        }
    }
    if (ray.IsKeyPressed(ray.KEY_HOME)) cursor_x = 0;
    if (ray.IsKeyPressed(ray.KEY_END)) cursor_x = line_lens[cursor_y];

    if (ray.IsKeyPressed(ray.KEY_ENTER)) insertNewline();
    if (ray.IsKeyPressed(ray.KEY_BACKSPACE)) backspace();
    if (ray.IsKeyPressed(ray.KEY_DELETE)) delete();

    const char = ray.GetCharPressed();
    if (char >= 32 and char < 127) insertChar(@intCast(char));
}

fn insertChar(c: u8) void {
    const len = line_lens[cursor_y];
    if (len >= MAX_LINE_LEN - 1) return;
    const line = &lines[cursor_y];
    var i = len;
    while (i > cursor_x) : (i -= 1) {
        line[i] = line[i - 1];
    }
    line[cursor_x] = c;
    line_lens[cursor_y] += 1;
    cursor_x += 1;
}

fn insertNewline() void {
    if (line_count >= MAX_LINES) return;
    var i = line_count;
    while (i > cursor_y + 1) : (i -= 1) {
        lines[i] = lines[i - 1];
        line_lens[i] = line_lens[i - 1];
    }
    const old_len = line_lens[cursor_y];
    const new_line_len = old_len - cursor_x;
    @memcpy(lines[cursor_y + 1][0..new_line_len], lines[cursor_y][cursor_x..old_len]);
    line_lens[cursor_y + 1] = new_line_len;
    line_lens[cursor_y] = cursor_x;
    line_count += 1;
    cursor_y += 1;
    cursor_x = 0;
}

fn backspace() void {
    if (cursor_x > 0) {
        const line = &lines[cursor_y];
        const len = line_lens[cursor_y];
        var i = cursor_x - 1;
        while (i < len - 1) : (i += 1) {
            line[i] = line[i + 1];
        }
        line_lens[cursor_y] -= 1;
        cursor_x -= 1;
    } else if (cursor_y > 0) {
        const prev_len = line_lens[cursor_y - 1];
        const curr_len = line_lens[cursor_y];
        if (prev_len + curr_len <= MAX_LINE_LEN) {
            @memcpy(lines[cursor_y - 1][prev_len..][0..curr_len], lines[cursor_y][0..curr_len]);
            line_lens[cursor_y - 1] += curr_len;
        }
        var i = cursor_y;
        while (i < line_count - 1) : (i += 1) {
            lines[i] = lines[i + 1];
            line_lens[i] = line_lens[i + 1];
        }
        line_count -= 1;
        cursor_y -= 1;
        cursor_x = prev_len;
    }
}

fn delete() void {
    const len = line_lens[cursor_y];
    if (cursor_x < len) {
        const line = &lines[cursor_y];
        var i = cursor_x;
        while (i < len - 1) : (i += 1) {
            line[i] = line[i + 1];
        }
        line_lens[cursor_y] -= 1;
    } else if (cursor_y + 1 < line_count) {
        const next_len = line_lens[cursor_y + 1];
        if (len + next_len <= MAX_LINE_LEN) {
            @memcpy(lines[cursor_y][len..][0..next_len], lines[cursor_y + 1][0..next_len]);
            line_lens[cursor_y] += next_len;
        }
        var i = cursor_y + 1;
        while (i < line_count - 1) : (i += 1) {
            lines[i] = lines[i + 1];
            line_lens[i] = line_lens[i + 1];
        }
        line_count -= 1;
    }
}

fn render() void {
    drawEditorPane();
    drawDivider();
    drawOutputPane();
    drawStatusBar();
}

fn drawEditorPane() void {
    for (0..HEIGHT - 1) |y| {
        for (0..GUTTER) |x| {
            lnpc.lnpc_bg(g, @intCast(x), @intCast(y), theme.gutter_bg);
            lnpc.lnpc_nochar(g, @intCast(x), @intCast(y));
        }
        for (GUTTER..DIVIDER) |x| {
            const bg = if (y == cursor_y) theme.cursor_line else theme.bg;
            lnpc.lnpc_bg(g, @intCast(x), @intCast(y), bg);
            lnpc.lnpc_nochar(g, @intCast(x), @intCast(y));
        }
    }

    for (0..line_count) |y| {
        if (y >= HEIGHT - 1) break;
        drawLineNumber(@intCast(y));
        drawCodeLine(lines[y][0..line_lens[y]], @intCast(y));
    }

    drawCursor();
}

fn drawLineNumber(y: u32) void {
    var buf: [4]u8 = undefined;
    const num = std.fmt.bufPrint(&buf, "{d:>3}", .{y + 1}) catch return;
    for (num, 0..) |c, i| {
        lnpc.lnpc_char(g, @intCast(i), y, c, theme.gutter_fg);
    }
}

fn drawCodeLine(line: []const u8, y: u32) void {
    var x: u32 = GUTTER;
    var i: usize = 0;
    while (i < line.len and x < DIVIDER) {
        const color = tokenColor(line, i);
        const c = line[i];
        lnpc.lnpc_char(g, x, y, c, color);
        x += 1;
        i += 1;
    }
}

fn tokenColor(line: []const u8, pos: usize) lnpc.Color {
    if (pos + 2 <= line.len and std.mem.eql(u8, line[pos..][0..2], "//")) return theme.comment;
    if (pos > 0 and line[pos - 1] != ' ' and line[pos - 1] != '(' and line[pos - 1] != '{') {
        var j = pos;
        while (j > 0 and line[j - 1] != ' ' and line[j - 1] != '(' and line[j - 1] != '{') j -= 1;
        if (isKeyword(line[j..pos])) return theme.keyword;
    }
    if (isKeywordStart(line, pos)) return theme.keyword;
    if (line[pos] == '"') return theme.string;
    if (pos > 0 and hasOpenQuote(line[0..pos])) return theme.string;
    if (std.ascii.isDigit(line[pos])) return theme.number;
    return theme.fg;
}

fn isKeywordStart(line: []const u8, pos: usize) bool {
    const keywords = [_][]const u8{ "fn", "const", "var", "if", "else", "while", "for", "return", "void", "struct" };
    for (keywords) |kw| {
        if (pos + kw.len <= line.len and std.mem.eql(u8, line[pos..][0..kw.len], kw)) {
            if (pos + kw.len == line.len or !std.ascii.isAlphanumeric(line[pos + kw.len])) {
                if (pos == 0 or !std.ascii.isAlphanumeric(line[pos - 1])) return true;
            }
        }
    }
    return false;
}

fn isKeyword(slice: []const u8) bool {
    const keywords = [_][]const u8{ "fn", "const", "var", "if", "else", "while", "for", "return", "void", "struct" };
    for (keywords) |kw| {
        if (std.mem.eql(u8, slice, kw)) return true;
    }
    return false;
}

fn hasOpenQuote(slice: []const u8) bool {
    var count: u32 = 0;
    for (slice) |c| {
        if (c == '"') count += 1;
    }
    return count % 2 == 1;
}

fn drawCursor() void {
    const x = GUTTER + cursor_x;
    const y = cursor_y;
    if (x < DIVIDER and y < HEIGHT - 1) {
        lnpc.lnpc_bg(g, x, y, theme.fg);
        const char = g.chars[y * WIDTH + x];
        if (char != 0) {
            lnpc.lnpc_char(g, x, y, char, theme.bg);
        }
    }
}

fn drawDivider() void {
    for (0..HEIGHT) |y| {
        lnpc.lnpc_bg(g, DIVIDER, @intCast(y), theme.divider);
        lnpc.lnpc_char(g, DIVIDER, @intCast(y), 0x2502, theme.divider);
    }
}

fn drawOutputPane() void {
    for (0..HEIGHT - 1) |y| {
        for (DIVIDER + 1..WIDTH) |x| {
            lnpc.lnpc_bg(g, @intCast(x), @intCast(y), theme.output_bg);
            lnpc.lnpc_nochar(g, @intCast(x), @intCast(y));
        }
    }

    var output_lines = std.mem.splitScalar(u8, sample_output, '\n');
    var y: u32 = 0;
    while (output_lines.next()) |line| : (y += 1) {
        if (y >= HEIGHT - 1) break;
        var x: u32 = DIVIDER + 2;
        for (line) |c| {
            if (x >= WIDTH) break;
            lnpc.lnpc_char(g, x, y, c, theme.fg);
            x += 1;
        }
    }
}

fn drawStatusBar() void {
    const y = HEIGHT - 1;
    for (0..WIDTH) |x| {
        lnpc.lnpc_bg(g, @intCast(x), y, theme.status_bg);
        lnpc.lnpc_nochar(g, @intCast(x), y);
    }

    const left = " editor.zig";
    for (left, 0..) |c, i| {
        lnpc.lnpc_char(g, @intCast(i), y, c, theme.status_fg);
    }

    var buf: [32]u8 = undefined;
    const right = std.fmt.bufPrint(&buf, "Ln {}, Col {} ", .{ cursor_y + 1, cursor_x + 1 }) catch return;
    const start = WIDTH - right.len;
    for (right, 0..) |c, i| {
        lnpc.lnpc_char(g, @intCast(start + i), y, c, theme.status_fg);
    }
}
