const std = @import("std");
const lnpc = @import("linopic");
const ray = @cImport(@cInclude("raylib.h"));

// =============================================================================
// Constants
// =============================================================================

const WIDTH = 60;
const HEIGHT = 30;
const MAX_MODULES = 256;
const MAX_CONNECTIONS = 256;
const MAX_SUBGRIDS = 64;
const MAX_NAV_DEPTH = 16;
const SAMPLE_RATE = 44100;
const BUFFER_SIZE = 512;

// =============================================================================
// Types
// =============================================================================

const ModuleType = enum(u8) {
    knob, // [K] - constant value (primitive)
    osc, // [W] - oscillator
    filter, // [F] - low-pass filter
    amp, // [A] - amplifier/VCA
    mixer, // [+] - sum inputs
    output, // [O] - audio output
    lfo, // [L] - low-frequency oscillator
    tempo, // [T] - clock/BPM (primitive)
    gate, // [G] - gate/comparator (threshold trigger)
    port, // [.] - exposes to parent level
    composite, // [C] - container with subgrid

    fn toChar(self: ModuleType) u32 {
        return switch (self) {
            .knob => 'K',
            .osc => 'W',
            .filter => 'F',
            .amp => 'A',
            .mixer => '+',
            .output => 'O',
            .lfo => 'L',
            .tempo => 'T',
            .gate => 'G',
            .port => 0x2022, // bullet
            .composite => 'C',
        };
    }

    fn fromChar(c: u8) ?ModuleType {
        return switch (c) {
            'k', 'K' => .knob,
            'w', 'W' => .osc,
            'f', 'F' => .filter,
            'a', 'A' => .amp,
            '+' => .mixer,
            'o', 'O' => .output,
            'l', 'L' => .lfo,
            't', 'T' => .tempo,
            'g', 'G' => .gate,
            '.' => .port,
            'c', 'C' => .composite,
            else => null,
        };
    }

    fn isPrimitive(self: ModuleType) bool {
        return switch (self) {
            .knob, .tempo => true,
            else => false,
        };
    }

    fn name(self: ModuleType) []const u8 {
        return switch (self) {
            .knob => "knob",
            .osc => "oscillator",
            .filter => "filter",
            .amp => "amplifier",
            .mixer => "mixer",
            .output => "output",
            .lfo => "lfo",
            .tempo => "tempo",
            .gate => "gate",
            .port => "port",
            .composite => "composite",
        };
    }
};

const PortType = enum(u8) {
    audio_in, // red - audio input
    audio_out, // white - audio output
    ctrl_a, // cyan
    ctrl_b, // magenta
    ctrl_c, // green
    ctrl_d, // yellow

    fn toColor(self: PortType) lnpc.Color {
        return switch (self) {
            .audio_in => 0xFFFF4444, // red
            .audio_out => 0xFFEEEEEE, // white
            .ctrl_a => 0xFF44DDDD, // cyan
            .ctrl_b => 0xFFDD44DD, // magenta
            .ctrl_c => 0xFF44DD44, // green
            .ctrl_d => 0xFFDDDD44, // yellow
        };
    }

    fn name(self: PortType) []const u8 {
        return switch (self) {
            .audio_in => "in",
            .audio_out => "out",
            .ctrl_a => "A",
            .ctrl_b => "B",
            .ctrl_c => "C",
            .ctrl_d => "D",
        };
    }

    fn next(self: PortType) PortType {
        return @enumFromInt((@intFromEnum(self) + 1) % 6);
    }

    fn prev(self: PortType) PortType {
        return @enumFromInt((@intFromEnum(self) + 5) % 6);
    }
};

const Cell = struct {
    module_type: ?ModuleType = null,
    port_type: PortType = .audio_out,
    value: u8 = 128, // for primitives: the actual value
    subgrid_id: ?u16 = null, // for composite modules
};

const Connection = struct {
    src_x: u32,
    src_y: u32,
    dst_x: u32,
    dst_y: u32,
    line_id: u32 = 0xFFFFFFFF,
};

const SubGrid = struct {
    cells: [WIDTH * HEIGHT]Cell,
    connections: [MAX_CONNECTIONS]Connection,
    connection_count: u32,
    parent_id: ?u16, // null = root
    entry_x: u32, // position in parent where we entered
    entry_y: u32,
    name: [32]u8,
    name_len: u8,

    // DSP state for modules in this grid
    osc_phases: [WIDTH * HEIGHT]f32,
    lfo_phases: [WIDTH * HEIGHT]f32,
    filter_states: [WIDTH * HEIGHT]f32,

    fn init(parent: ?u16) SubGrid {
        var sg = SubGrid{
            .cells = [_]Cell{.{}} ** (WIDTH * HEIGHT),
            .connections = undefined,
            .connection_count = 0,
            .parent_id = parent,
            .entry_x = 0,
            .entry_y = 0,
            .name = [_]u8{0} ** 32,
            .name_len = 0,
            .osc_phases = [_]f32{0} ** (WIDTH * HEIGHT),
            .lfo_phases = [_]f32{0} ** (WIDTH * HEIGHT),
            .filter_states = [_]f32{0} ** (WIDTH * HEIGHT),
        };
        for (&sg.connections) |*conn| {
            conn.line_id = 0xFFFFFFFF;
        }
        return sg;
    }

    fn cellAt(self: *SubGrid, x: u32, y: u32) *Cell {
        return &self.cells[y * WIDTH + x];
    }

    fn addConnection(self: *SubGrid, _: *lnpc.Grid, src_x: u32, src_y: u32, dst_x: u32, dst_y: u32) void {
        if (self.connection_count >= MAX_CONNECTIONS) return;

        const src_cell = self.cellAt(src_x, src_y);
        const color = if (src_cell.module_type != null and src_cell.module_type.?.isPrimitive())
            primitiveValueColor(src_cell.value)
        else
            src_cell.port_type.toColor();

        const line_id = lnpc.lnpc_line(gfx, src_x, src_y, dst_x, dst_y, color, lnpc.LINE_3SEG);

        self.connections[self.connection_count] = .{
            .src_x = src_x,
            .src_y = src_y,
            .dst_x = dst_x,
            .dst_y = dst_y,
            .line_id = line_id,
        };
        self.connection_count += 1;
    }

    fn removeConnection(self: *SubGrid, _: *lnpc.Grid, idx: u32) void {
        if (idx >= self.connection_count) return;
        if (self.connections[idx].line_id != 0xFFFFFFFF) {
            lnpc.lnpc_noline(gfx, self.connections[idx].line_id);
        }
        // Shift remaining
        var i = idx;
        while (i < self.connection_count - 1) : (i += 1) {
            self.connections[i] = self.connections[i + 1];
        }
        self.connection_count -= 1;
    }

    fn findConnectionAt(self: *SubGrid, x: u32, y: u32) ?u32 {
        for (0..self.connection_count) |i| {
            const conn = &self.connections[i];
            if ((conn.src_x == x and conn.src_y == y) or (conn.dst_x == x and conn.dst_y == y)) {
                return @intCast(i);
            }
        }
        return null;
    }

    fn clearCell(self: *SubGrid, _: *lnpc.Grid, x: u32, y: u32) void {
        // Remove connections involving this cell
        var i: u32 = 0;
        while (i < self.connection_count) {
            const conn = &self.connections[i];
            if ((conn.src_x == x and conn.src_y == y) or (conn.dst_x == x and conn.dst_y == y)) {
                self.removeConnection(gfx, i);
            } else {
                i += 1;
            }
        }
        self.cells[y * WIDTH + x] = .{};
    }

    fn clearAllLines(self: *SubGrid, _: *lnpc.Grid) void {
        for (0..self.connection_count) |i| {
            if (self.connections[i].line_id != 0xFFFFFFFF) {
                lnpc.lnpc_noline(gfx, self.connections[i].line_id);
                self.connections[i].line_id = 0xFFFFFFFF;
            }
        }
    }

    fn recreateAllLines(self: *SubGrid, _: *lnpc.Grid) void {
        for (0..self.connection_count) |i| {
            const conn = &self.connections[i];
            const src_cell = self.cellAt(conn.src_x, conn.src_y);
            const color = if (src_cell.module_type != null and src_cell.module_type.?.isPrimitive())
                primitiveValueColor(src_cell.value)
            else
                src_cell.port_type.toColor();

            conn.line_id = lnpc.lnpc_line(gfx, conn.src_x, conn.src_y, conn.dst_x, conn.dst_y, color, lnpc.LINE_3SEG);
        }
    }
};

const UIState = enum {
    idle,
    dragging_connection,
    dragging_value,
    menu_open,
};

// =============================================================================
// Global State
// =============================================================================

var gfx: *lnpc.Grid = undefined;
var subgrids: [MAX_SUBGRIDS]SubGrid = undefined;
var subgrid_count: u16 = 0;

// Navigation stack
var nav_stack: [MAX_NAV_DEPTH]u16 = undefined;
var nav_depth: u16 = 0;

fn currentGrid() *SubGrid {
    return &subgrids[nav_stack[nav_depth]];
}

var ui_state: UIState = .idle;
var cursor_x: u32 = 0;
var cursor_y: u32 = 0;
var drag_start_x: u32 = 0;
var drag_start_y: u32 = 0;
var drag_start_value: u8 = 0;
var drag_start_mouse_y: i32 = 0;

var menu_filter: [32]u8 = [_]u8{0} ** 32;
var menu_filter_len: u32 = 0;
var menu_selection: u32 = 0;

// Audio
var audio_stream: ray.AudioStream = undefined;
var audio_initialized: bool = false;
var audio_output_buffer: [BUFFER_SIZE * 2]f32 = [_]f32{0} ** (BUFFER_SIZE * 2);

// Tempo visual state (for blinking)
var tempo_phase: f32 = 0;
var tempo_beat: bool = false;

// =============================================================================
// Color Helpers
// =============================================================================

fn primitiveValueColor(value: u8) lnpc.Color {
    const v = value;
    return 0xFF000000 | @as(u32, v / 3) << 16 | @as(u32, v / 3) << 8 | @as(u32, v);
}

fn oscWaveformColor(value: u8) lnpc.Color {
    return switch (value >> 6) {
        0 => 0xFFFF6666, // red - sine
        1 => 0xFFFFFF66, // yellow - saw
        2 => 0xFF66FF66, // green - square
        3 => 0xFF66FFFF, // cyan - triangle
        else => 0xFFFFFFFF,
    };
}

// =============================================================================
// Subgrid Management
// =============================================================================

fn createSubgrid(parent: ?u16) u16 {
    if (subgrid_count >= MAX_SUBGRIDS) return 0;
    const id = subgrid_count;
    subgrids[id] = SubGrid.init(parent);
    subgrid_count += 1;
    return id;
}

fn zoomIn(x: u32, y: u32) void {
    const sg = currentGrid();
    const cell = sg.cellAt(x, y);

    if (cell.module_type) |mod_type| {
        if (mod_type == .composite) {
            // Create subgrid if doesn't exist
            if (cell.subgrid_id == null) {
                cell.subgrid_id = createSubgrid(nav_stack[nav_depth]);
                subgrids[cell.subgrid_id.?].entry_x = x;
                subgrids[cell.subgrid_id.?].entry_y = y;
            }

            // Clear lines from current view
            sg.clearAllLines(gfx);

            // Push onto nav stack
            if (nav_depth < MAX_NAV_DEPTH - 1) {
                nav_depth += 1;
                nav_stack[nav_depth] = cell.subgrid_id.?;

                // Recreate lines for new view
                currentGrid().recreateAllLines(gfx);
            }
        }
    }
}

fn zoomOut() void {
    if (nav_depth > 0) {
        // Clear lines from current view
        currentGrid().clearAllLines(gfx);

        nav_depth -= 1;

        // Recreate lines for parent view
        currentGrid().recreateAllLines(gfx);
    }
}

// =============================================================================
// Input Handling
// =============================================================================

fn handleInput() void {
    const mouse = lnpc.lnpc_mouse(gfx, 0);
    const mx: u32 = @intCast(@max(0, @min(mouse.x, @as(i32, WIDTH - 1))));
    const my: u32 = @intCast(@max(0, @min(mouse.y, @as(i32, HEIGHT - 2)))); // -2 for status bar

    // Only update cursor from mouse if mouse moved or button pressed
    if (mouse.is_pressed or mouse.is_down) {
        cursor_x = mx;
        cursor_y = my;
    }

    switch (ui_state) {
        .idle => handleIdleInput(mouse, mx, my),
        .dragging_connection => handleDragConnection(mouse, mx, my),
        .dragging_value => handleDragValue(mouse),
        .menu_open => handleMenuInput(mx, my),
    }
}

fn handleIdleInput(mouse: lnpc.MouseEvt, mx: u32, my: u32) void {
    const sg = currentGrid();
    const cell = sg.cellAt(mx, my);

    // Left click - start drag
    if (mouse.is_pressed) {
        if (cell.module_type) |mod_type| {
            // Shift+drag = create connection
            // Regular drag on primitive = change value
            if (ray.IsKeyDown(ray.KEY_LEFT_SHIFT)) {
                ui_state = .dragging_connection;
                drag_start_x = mx;
                drag_start_y = my;
            } else if (mod_type.isPrimitive() or mod_type == .lfo or mod_type == .osc or mod_type == .amp) {
                // Value drag for primitives, LFO (rate), OSC (freq), amp (base gain)
                ui_state = .dragging_value;
                drag_start_x = mx;
                drag_start_y = my;
                drag_start_value = cell.value;
                drag_start_mouse_y = mouse.y;
            } else {
                // Other modules: start connection
                ui_state = .dragging_connection;
                drag_start_x = mx;
                drag_start_y = my;
            }
        }
    }

    // Right click - menu or delete connection
    const right_mouse = lnpc.lnpc_mouse(gfx, 1);
    if (right_mouse.is_pressed) {
        if (sg.findConnectionAt(mx, my)) |idx| {
            sg.removeConnection(gfx, idx);
        } else {
            ui_state = .menu_open;
            menu_filter_len = 0;
            menu_selection = 0;
        }
    }

    // Keyboard shortcuts
    handleKeyboardShortcuts(mx, my);
}

fn handleDragConnection(mouse: lnpc.MouseEvt, mx: u32, my: u32) void {
    if (mouse.is_released) {
        const sg = currentGrid();
        const dst_cell = sg.cellAt(mx, my);

        if (dst_cell.module_type != null and (mx != drag_start_x or my != drag_start_y)) {
            sg.addConnection(gfx, drag_start_x, drag_start_y, mx, my);
        }
        ui_state = .idle;
    }
}

fn handleDragValue(mouse: lnpc.MouseEvt) void {
    const sg = currentGrid();
    const cell = sg.cellAt(drag_start_x, drag_start_y);
    const delta = drag_start_mouse_y - mouse.y;

    // All modules: value is 0-255, controls main property (freq, rate, cutoff, gain, etc.)
    const nv = @as(i32, drag_start_value) + delta * 2;
    const new_value: u8 = @intCast(@max(0, @min(255, nv)));

    // Update ALL contiguous cells of the same module type (they share value)
    const mod_type = cell.module_type orelse return;
    updateContiguousValue(sg, drag_start_x, drag_start_y, mod_type, new_value);

    if (mouse.is_released) {
        ui_state = .idle;
    }
}

fn updateContiguousValue(sg: *SubGrid, start_x: u32, start_y: u32, mod_type: ModuleType, value: u8) void {
    var visited: [WIDTH * HEIGHT]bool = [_]bool{false} ** (WIDTH * HEIGHT);
    var stack: [64]struct { x: u32, y: u32 } = undefined;
    var stack_len: usize = 1;
    stack[0] = .{ .x = start_x, .y = start_y };

    while (stack_len > 0) {
        stack_len -= 1;
        const pos = stack[stack_len];
        const idx = pos.y * WIDTH + pos.x;
        if (visited[idx]) continue;
        visited[idx] = true;

        const cell = sg.cellAt(pos.x, pos.y);
        if (cell.module_type != mod_type) continue;

        cell.value = value;

        if (stack_len < 60) {
            if (pos.x > 0) {
                stack[stack_len] = .{ .x = pos.x - 1, .y = pos.y };
                stack_len += 1;
            }
            if (pos.x < WIDTH - 1) {
                stack[stack_len] = .{ .x = pos.x + 1, .y = pos.y };
                stack_len += 1;
            }
            if (pos.y > 0) {
                stack[stack_len] = .{ .x = pos.x, .y = pos.y - 1 };
                stack_len += 1;
            }
            if (pos.y < HEIGHT - 1) {
                stack[stack_len] = .{ .x = pos.x, .y = pos.y + 1 };
                stack_len += 1;
            }
        }
    }
}

fn handleMenuInput(mx: u32, my: u32) void {
    const char = ray.GetCharPressed();
    if (char >= 32 and char < 127 and menu_filter_len < 31) {
        menu_filter[menu_filter_len] = @intCast(char);
        menu_filter_len += 1;
    }

    if (ray.IsKeyPressed(ray.KEY_BACKSPACE) and menu_filter_len > 0) {
        menu_filter_len -= 1;
    }

    if (ray.IsKeyPressed(ray.KEY_ESCAPE)) {
        ui_state = .idle;
    }

    if (ray.IsKeyPressed(ray.KEY_ENTER)) {
        if (getFilteredModuleType(menu_selection)) |mod_type| {
            const sg = currentGrid();
            const cell = sg.cellAt(mx, my);
            cell.module_type = mod_type;
            cell.port_type = .audio_out;
            cell.value = 128;
        }
        ui_state = .idle;
    }

    if (ray.IsKeyPressed(ray.KEY_UP) and menu_selection > 0) {
        menu_selection -= 1;
    }
    if (ray.IsKeyPressed(ray.KEY_DOWN)) {
        menu_selection += 1;
    }
}

fn handleKeyboardShortcuts(mx: u32, my: u32) void {
    const sg = currentGrid();
    var cell = sg.cellAt(mx, my);

    // Shift+Up/Down adjusts value of any cell
    if (ray.IsKeyDown(ray.KEY_LEFT_SHIFT)) {
        if (ray.IsKeyPressed(ray.KEY_UP) or ray.IsKeyPressedRepeat(ray.KEY_UP)) {
            cell.value = if (cell.value < 250) cell.value + 5 else 255;
        }
        if (ray.IsKeyPressed(ray.KEY_DOWN) or ray.IsKeyPressedRepeat(ray.KEY_DOWN)) {
            cell.value = if (cell.value > 5) cell.value - 5 else 0;
        }
    } else {
        // Arrow keys move cursor (not on primitives, those use arrows for value)
        const on_primitive = cell.module_type != null and cell.module_type.?.isPrimitive();

        if (!on_primitive) {
            if (ray.IsKeyPressed(ray.KEY_UP) or ray.IsKeyPressedRepeat(ray.KEY_UP)) {
                if (cursor_y > 0) cursor_y -= 1;
            }
            if (ray.IsKeyPressed(ray.KEY_DOWN) or ray.IsKeyPressedRepeat(ray.KEY_DOWN)) {
                if (cursor_y < HEIGHT - 2) cursor_y += 1;
            }
            if (ray.IsKeyPressed(ray.KEY_LEFT) or ray.IsKeyPressedRepeat(ray.KEY_LEFT)) {
                if (cursor_x > 0) cursor_x -= 1;
            }
            if (ray.IsKeyPressed(ray.KEY_RIGHT) or ray.IsKeyPressedRepeat(ray.KEY_RIGHT)) {
                if (cursor_x < WIDTH - 1) cursor_x += 1;
            }
            // Update cell reference after cursor move
            cell = sg.cellAt(cursor_x, cursor_y);
        } else {
            // On primitive: up/down adjust value
            if (ray.IsKeyPressed(ray.KEY_UP) or ray.IsKeyPressedRepeat(ray.KEY_UP)) {
                cell.value = if (cell.value < 250) cell.value + 5 else 255;
            }
            if (ray.IsKeyPressed(ray.KEY_DOWN) or ray.IsKeyPressedRepeat(ray.KEY_DOWN)) {
                cell.value = if (cell.value > 5) cell.value - 5 else 0;
            }
            // Left/right still move cursor
            if (ray.IsKeyPressed(ray.KEY_LEFT) or ray.IsKeyPressedRepeat(ray.KEY_LEFT)) {
                if (cursor_x > 0) cursor_x -= 1;
            }
            if (ray.IsKeyPressed(ray.KEY_RIGHT) or ray.IsKeyPressedRepeat(ray.KEY_RIGHT)) {
                if (cursor_x < WIDTH - 1) cursor_x += 1;
            }
        }
    }

    // Direct module placement (only if cell is empty and not pressing modifiers)
    if (!ray.IsKeyDown(ray.KEY_LEFT_CONTROL) and !ray.IsKeyDown(ray.KEY_LEFT_SHIFT)) {
        const char = ray.GetCharPressed();
        if (char > 0) {
            if (ModuleType.fromChar(@intCast(char))) |mod_type| {
                const current_cell = sg.cellAt(cursor_x, cursor_y);
                if (current_cell.module_type == null) {
                    current_cell.module_type = mod_type;
                    current_cell.port_type = .audio_out;
                    current_cell.value = 128;
                }
            }
        }
    }

    // Delete/Backspace clears cell
    if (ray.IsKeyPressed(ray.KEY_DELETE) or ray.IsKeyPressed(ray.KEY_BACKSPACE)) {
        sg.clearCell(gfx, cursor_x, cursor_y);
    }

    // Tab cycles port type, Shift+Tab cycles reverse
    if (ray.IsKeyPressed(ray.KEY_TAB)) {
        const current_cell = sg.cellAt(cursor_x, cursor_y);
        if (current_cell.module_type) |mod_type| {
            const reverse = ray.IsKeyDown(ray.KEY_LEFT_SHIFT);
            if (mod_type == .osc or mod_type == .lfo) {
                // Cycle through waveform colors: cyan <-> magenta <-> green <-> yellow
                current_cell.port_type = if (reverse) switch (current_cell.port_type) {
                    .ctrl_a => .ctrl_d,
                    .ctrl_b => .ctrl_a,
                    .ctrl_c => .ctrl_b,
                    .ctrl_d => .ctrl_c,
                    else => .ctrl_d,
                } else switch (current_cell.port_type) {
                    .ctrl_a => .ctrl_b,
                    .ctrl_b => .ctrl_c,
                    .ctrl_c => .ctrl_d,
                    .ctrl_d => .ctrl_a,
                    else => .ctrl_a,
                };
            } else if (!mod_type.isPrimitive()) {
                current_cell.port_type = if (reverse) current_cell.port_type.prev() else current_cell.port_type.next();
            }
        }
    }

    // Enter to zoom into composite
    if (ray.IsKeyPressed(ray.KEY_ENTER)) {
        const current_cell = sg.cellAt(cursor_x, cursor_y);
        if (current_cell.module_type == .composite) {
            zoomIn(cursor_x, cursor_y);
        }
    }

    // ESC to zoom out (only when not in menu)
    if (ray.IsKeyPressed(ray.KEY_ESCAPE)) {
        if (ui_state == .idle and nav_depth > 0) {
            zoomOut();
        }
    }

    // Ctrl+M opens menu
    if (ray.IsKeyDown(ray.KEY_LEFT_CONTROL) and ray.IsKeyPressed(ray.KEY_M)) {
        ui_state = .menu_open;
        menu_filter_len = 0;
        menu_selection = 0;
    }
}

fn getFilteredModuleType(index: u32) ?ModuleType {
    const all_types = [_]ModuleType{ .knob, .osc, .filter, .amp, .mixer, .output, .lfo, .tempo, .gate, .port, .composite };
    const filter_slice = menu_filter[0..menu_filter_len];

    var count: u32 = 0;
    for (all_types) |t| {
        const type_name = t.name();
        if (menu_filter_len == 0 or std.mem.indexOf(u8, type_name, filter_slice) != null) {
            if (count == index) return t;
            count += 1;
        }
    }
    return null;
}

// =============================================================================
// Rendering
// =============================================================================

fn render() void {
    const sg = currentGrid();

    // Clear
    for (0..HEIGHT) |y| {
        for (0..WIDTH) |x| {
            lnpc.lnpc_bg(gfx, @intCast(x), @intCast(y), 0xFF1a1a2e);
            lnpc.lnpc_nochar(gfx, @intCast(x), @intCast(y));
        }
    }

    // Draw cells
    for (0..HEIGHT - 1) |y| {
        for (0..WIDTH) |x| {
            const cell = sg.cellAt(@intCast(x), @intCast(y));
            if (cell.module_type) |mod_type| {
                // All modules render by port type color (primitives use value-based color)
                var bg: lnpc.Color = if (mod_type.isPrimitive())
                    primitiveValueColor(cell.value)
                else
                    cell.port_type.toColor();

                var fg: lnpc.Color = if (mod_type.isPrimitive()) 0xFFFFFFFF else 0xFF000000;

                // Tempo blinking
                if (mod_type == .tempo and tempo_beat) {
                    bg = 0xFFFFFF00; // bright yellow on beat
                    fg = 0xFF000000;
                }

                lnpc.lnpc_bg(gfx, @intCast(x), @intCast(y), bg);
                lnpc.lnpc_char(gfx, @intCast(x), @intCast(y), mod_type.toChar(), fg);
            }
        }
    }

    // Cursor highlight
    const cursor_cell = sg.cellAt(cursor_x, cursor_y);
    const base_bg = if (cursor_cell.module_type) |mod_type|
        (if (mod_type.isPrimitive()) primitiveValueColor(cursor_cell.value) else if (mod_type == .osc) oscWaveformColor(cursor_cell.value) else cursor_cell.port_type.toColor())
    else
        @as(lnpc.Color, 0xFF1a1a2e);

    const r = @as(u8, @truncate(base_bg >> 16)) +| 40;
    const gr = @as(u8, @truncate(base_bg >> 8)) +| 40;
    const b = @as(u8, @truncate(base_bg)) +| 40;
    lnpc.lnpc_bg(gfx, cursor_x, cursor_y, 0xFF000000 | @as(u32, r) << 16 | @as(u32, gr) << 8 | b);

    // Drag preview
    if (ui_state == .dragging_connection) {
        lnpc.lnpc_bg(gfx, drag_start_x, drag_start_y, 0xFFFFFF00);
    }

    // Value drag feedback - show big value display
    if (ui_state == .dragging_value) {
        const drag_cell = sg.cellAt(drag_start_x, drag_start_y);

        // Highlight the cell being edited
        lnpc.lnpc_bg(gfx, drag_start_x, drag_start_y, 0xFFFFFFFF);
        if (drag_cell.module_type) |mod_type| {
            lnpc.lnpc_char(gfx, drag_start_x, drag_start_y, mod_type.toChar(), 0xFF000000);

            // Build display string with raw value + interpreted value
            var buf: [24]u8 = undefined;
            const display_str = switch (mod_type) {
                .tempo => blk: {
                    const bpm = 40.0 + @as(f32, @floatFromInt(drag_cell.value)) / 255.0 * 160.0;
                    break :blk std.fmt.bufPrint(&buf, "{d:>3} ({d:.0}bpm)", .{ drag_cell.value, bpm }) catch "???";
                },
                .lfo => blk: {
                    const hz = 0.1 + @as(f32, @floatFromInt(drag_cell.value)) / 255.0 * 19.9;
                    break :blk std.fmt.bufPrint(&buf, "{d:>3} ({d:.1}Hz)", .{ drag_cell.value, hz }) catch "???";
                },
                .knob => blk: {
                    const norm = @as(f32, @floatFromInt(drag_cell.value)) / 255.0;
                    break :blk std.fmt.bufPrint(&buf, "{d:>3} ({d:.0}%)", .{ drag_cell.value, norm * 100 }) catch "???";
                },
                .osc => blk: {
                    const freq = 55.0 * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(drag_cell.value)) / 64.0);
                    break :blk std.fmt.bufPrint(&buf, "{d:>3} ({d:.0}Hz)", .{ drag_cell.value, freq }) catch "???";
                },
                .amp => blk: {
                    const gain_pct = @as(f32, @floatFromInt(drag_cell.value)) / 255.0 * 100.0;
                    break :blk std.fmt.bufPrint(&buf, "gain {d:.0}%", .{gain_pct}) catch "???";
                },
                else => std.fmt.bufPrint(&buf, "{d:>3}", .{drag_cell.value}) catch "???",
            };

            const overlay_x = if (drag_start_x < WIDTH - display_str.len - 2) drag_start_x + 2 else if (drag_start_x > display_str.len + 2) drag_start_x - display_str.len - 2 else 1;
            const overlay_y = drag_start_y;

            // Draw value box
            for (0..display_str.len + 2) |i| {
                lnpc.lnpc_bg(gfx, @intCast(overlay_x + i), overlay_y, 0xFF000000);
            }
            for (display_str, 0..) |c, i| {
                lnpc.lnpc_char(gfx, @intCast(overlay_x + 1 + i), overlay_y, c, 0xFFFFFFFF);
            }
        }
    }

    // Menu
    if (ui_state == .menu_open) {
        drawMenu();
    }

    // Breadcrumb (navigation path)
    drawBreadcrumb();

    // Status bar
    drawStatusBar();
}

fn drawMenu() void {
    const menu_x: u32 = 2;
    const menu_y: u32 = 2;
    const menu_w: u32 = 24;
    const menu_h: u32 = 14;

    for (menu_y..menu_y + menu_h) |y| {
        for (menu_x..menu_x + menu_w) |x| {
            lnpc.lnpc_bg(gfx, @intCast(x), @intCast(y), 0xFF2a2a4e);
            lnpc.lnpc_nochar(gfx, @intCast(x), @intCast(y));
        }
    }

    const filter_label = "Filter: ";
    for (filter_label, 0..) |c, i| {
        lnpc.lnpc_char(gfx, @intCast(menu_x + i), menu_y, c, 0xFF888888);
    }
    for (0..menu_filter_len) |i| {
        lnpc.lnpc_char(gfx, @intCast(menu_x + filter_label.len + i), menu_y, menu_filter[i], 0xFFFFFFFF);
    }

    const all_types = [_]ModuleType{ .knob, .osc, .filter, .amp, .mixer, .output, .lfo, .tempo, .gate, .port, .composite };
    const filter_slice = menu_filter[0..menu_filter_len];

    var row: u32 = 0;
    for (all_types) |t| {
        const type_name = t.name();
        if (menu_filter_len == 0 or std.mem.indexOf(u8, type_name, filter_slice) != null) {
            const y = menu_y + 2 + row;
            if (y >= menu_y + menu_h) break;

            const is_selected = row == menu_selection;
            const fg: lnpc.Color = if (is_selected) 0xFF000000 else 0xFFCCCCCC;
            if (is_selected) {
                for (menu_x..menu_x + menu_w) |x| {
                    lnpc.lnpc_bg(gfx, @intCast(x), y, 0xFFFFFFFF);
                }
            }

            lnpc.lnpc_char(gfx, menu_x + 1, y, '[', fg);
            lnpc.lnpc_char(gfx, menu_x + 2, y, t.toChar(), fg);
            lnpc.lnpc_char(gfx, menu_x + 3, y, ']', fg);

            for (type_name, 0..) |c, i| {
                if (menu_x + 5 + i < menu_x + menu_w - 1) {
                    lnpc.lnpc_char(gfx, @intCast(menu_x + 5 + i), y, c, fg);
                }
            }

            row += 1;
        }
    }
}

fn drawBreadcrumb() void {
    if (nav_depth == 0) return;

    var x_pos: u32 = 1;
    const y: u32 = 0;

    // Draw breadcrumb background
    for (0..WIDTH) |x| {
        lnpc.lnpc_bg(gfx, @intCast(x), y, 0xFF333355);
    }

    const prefix = ">> ";
    for (prefix) |c| {
        lnpc.lnpc_char(gfx, x_pos, y, c, 0xFFAAAAFF);
        x_pos += 1;
    }

    // Show path
    for (0..nav_depth + 1) |i| {
        if (i > 0) {
            lnpc.lnpc_char(gfx, x_pos, y, '/', 0xFF666688);
            x_pos += 1;
        }

        if (i == 0) {
            const root = "root";
            for (root) |c| {
                lnpc.lnpc_char(gfx, x_pos, y, c, 0xFFCCCCCC);
                x_pos += 1;
            }
        } else {
            const sg = &subgrids[nav_stack[i]];
            var buf: [16]u8 = undefined;
            const pos_str = std.fmt.bufPrint(&buf, "({d},{d})", .{ sg.entry_x, sg.entry_y }) catch continue;
            for (pos_str) |c| {
                lnpc.lnpc_char(gfx, x_pos, y, c, 0xFFCCCCCC);
                x_pos += 1;
            }
        }
    }

    const hint = " [ESC to go back]";
    for (hint) |c| {
        if (x_pos < WIDTH - 1) {
            lnpc.lnpc_char(gfx, x_pos, y, c, 0xFF666688);
            x_pos += 1;
        }
    }
}

fn drawStatusBar() void {
    const y = HEIGHT - 1;
    for (0..WIDTH) |x| {
        lnpc.lnpc_bg(gfx, @intCast(x), y, 0xFF333355);
        lnpc.lnpc_nochar(gfx, @intCast(x), y);
    }

    const sg = currentGrid();

    // Mode and info display
    var buf: [64]u8 = undefined;
    var x_off: u32 = 1;

    switch (ui_state) {
        .idle => {
            // Count modules and show connection count instead of useless "IDLE"
            const conn_str = std.fmt.bufPrint(&buf, "{d} wires", .{sg.connection_count}) catch "0 wires";
            for (conn_str) |c| {
                lnpc.lnpc_char(gfx, x_off, y, c, 0xFF88AAFF);
                x_off += 1;
            }
        },
        .dragging_connection => {
            const conn = "CONNECT";
            for (conn) |c| {
                lnpc.lnpc_char(gfx, x_off, y, c, 0xFFFFFF44);
                x_off += 1;
            }
        },
        .dragging_value => {
            const drag_cell = sg.cellAt(drag_start_x, drag_start_y);
            const val_str = std.fmt.bufPrint(&buf, "VALUE: {d}", .{drag_cell.value}) catch "VALUE";
            for (val_str) |c| {
                lnpc.lnpc_char(gfx, x_off, y, c, 0xFF88FF88);
                x_off += 1;
            }
        },
        .menu_open => {
            const menu = "MENU";
            for (menu) |c| {
                lnpc.lnpc_char(gfx, x_off, y, c, 0xFFFFFFFF);
                x_off += 1;
            }
        },
    }

    // Position - add padding after mode indicator
    x_off += 2;
    const pos = std.fmt.bufPrint(&buf, "({d},{d})", .{ cursor_x, cursor_y }) catch return;
    for (pos) |c| {
        lnpc.lnpc_char(gfx, x_off, y, c, 0xFFAAAAAA);
        x_off += 1;
    }

    // Cell info
    const cell = sg.cellAt(cursor_x, cursor_y);
    x_off += 2;

    if (cell.module_type) |mod_type| {
        lnpc.lnpc_char(gfx, x_off, y, '[', 0xFFAAAAAA);
        x_off += 1;
        lnpc.lnpc_char(gfx, x_off, y, mod_type.toChar(), 0xFFFFFFFF);
        x_off += 1;
        lnpc.lnpc_char(gfx, x_off, y, ']', 0xFFAAAAAA);
        x_off += 2;

        const type_name = mod_type.name();
        for (type_name) |c| {
            lnpc.lnpc_char(gfx, x_off, y, c, 0xFFAAAAAA);
            x_off += 1;
        }

        if (mod_type.isPrimitive()) {
            const val = std.fmt.bufPrint(&buf, " ={d}", .{cell.value}) catch return;
            for (val) |c| {
                lnpc.lnpc_char(gfx, x_off, y, c, 0xFF88FF88);
                x_off += 1;
            }
            // Show BPM for tempo
            if (mod_type == .tempo) {
                const bpm = 40.0 + @as(f32, @floatFromInt(cell.value)) / 255.0 * 160.0;
                const bpm_str = std.fmt.bufPrint(&buf, " ({d:.0}bpm)", .{bpm}) catch "";
                for (bpm_str) |c| {
                    lnpc.lnpc_char(gfx, x_off, y, c, 0xFFFFFF44);
                    x_off += 1;
                }
            }
        } else if (mod_type == .osc or mod_type == .lfo) {
            // Check if multi-cell mode (has white cell anywhere in contiguous group)
            var has_white_in_group = cell.port_type == .audio_out;
            if (!has_white_in_group) {
                var visited: [WIDTH * HEIGHT]bool = [_]bool{false} ** (WIDTH * HEIGHT);
                var stack: [64]struct { px: u32, py: u32 } = undefined;
                var stack_len: usize = 1;
                stack[0] = .{ .px = cursor_x, .py = cursor_y };

                while (stack_len > 0 and !has_white_in_group) {
                    stack_len -= 1;
                    const p = stack[stack_len];
                    const vi = p.py * WIDTH + p.px;
                    if (visited[vi]) continue;
                    visited[vi] = true;

                    const check_cell = sg.cellAt(p.px, p.py);
                    if (check_cell.module_type != mod_type) continue;

                    if (check_cell.port_type == .audio_out) {
                        has_white_in_group = true;
                        break;
                    }

                    if (stack_len < 60) {
                        if (p.px > 0) {
                            stack[stack_len] = .{ .px = p.px - 1, .py = p.py };
                            stack_len += 1;
                        }
                        if (p.px < WIDTH - 1) {
                            stack[stack_len] = .{ .px = p.px + 1, .py = p.py };
                            stack_len += 1;
                        }
                        if (p.py > 0) {
                            stack[stack_len] = .{ .px = p.px, .py = p.py - 1 };
                            stack_len += 1;
                        }
                        if (p.py < HEIGHT - 1) {
                            stack[stack_len] = .{ .px = p.px, .py = p.py + 1 };
                            stack_len += 1;
                        }
                    }
                }
            }

            x_off += 1;
            const port_color = cell.port_type.toColor();

            if (has_white_in_group) {
                // Multi-cell mode: show parameter name
                const param_name: []const u8 = switch (cell.port_type) {
                    .ctrl_a => if (mod_type == .osc) "freq" else "rate",
                    .ctrl_b => "waveform",
                    .ctrl_c => "phase",
                    .ctrl_d => "amplitude",
                    .audio_out => "output",
                    .audio_in => "input",
                };
                for (param_name) |c| {
                    lnpc.lnpc_char(gfx, x_off, y, c, port_color);
                    x_off += 1;
                }
            } else {
                // Single-cell mode: color = waveform
                const wave_name: []const u8 = switch (cell.port_type) {
                    .ctrl_a => "sine",
                    .ctrl_b => "saw",
                    .ctrl_c => "square",
                    .ctrl_d => "tri",
                    .audio_out => "sine",
                    .audio_in => "sine",
                };
                for (wave_name) |c| {
                    lnpc.lnpc_char(gfx, x_off, y, c, port_color);
                    x_off += 1;
                }
            }

            // Show value interpretation based on parameter type
            x_off += 1;
            const val_str = if (has_white_in_group) switch (cell.port_type) {
                .ctrl_a => blk: { // freq/rate
                    if (mod_type == .osc) {
                        const freq = 55.0 * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(cell.value)) / 64.0);
                        break :blk std.fmt.bufPrint(&buf, "{d:.0}Hz", .{freq}) catch "";
                    } else {
                        const rate = 0.1 + @as(f32, @floatFromInt(cell.value)) / 255.0 * 19.9;
                        break :blk std.fmt.bufPrint(&buf, "{d:.1}Hz", .{rate}) catch "";
                    }
                },
                .ctrl_b => blk: { // waveform
                    const wave_names = [_][]const u8{ "sin", "saw", "sqr", "tri" };
                    break :blk wave_names[cell.value >> 6];
                },
                .ctrl_c => blk: { // phase
                    const deg = @as(f32, @floatFromInt(cell.value)) / 255.0 * 360.0;
                    break :blk std.fmt.bufPrint(&buf, "{d:.0}deg", .{deg}) catch "";
                },
                .ctrl_d => blk: { // amplitude
                    const pct = @as(f32, @floatFromInt(cell.value)) / 255.0 * 100.0;
                    break :blk std.fmt.bufPrint(&buf, "{d:.0}%", .{pct}) catch "";
                },
                else => "",
            } else blk: {
                // Single cell mode: value = freq/rate
                if (mod_type == .osc) {
                    const freq = 55.0 * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(cell.value)) / 64.0);
                    break :blk std.fmt.bufPrint(&buf, "{d:.0}Hz", .{freq}) catch "";
                } else {
                    const rate = 0.1 + @as(f32, @floatFromInt(cell.value)) / 255.0 * 19.9;
                    break :blk std.fmt.bufPrint(&buf, "{d:.1}Hz", .{rate}) catch "";
                }
            };
            for (val_str) |c| {
                lnpc.lnpc_char(gfx, x_off, y, c, 0xFFAAAAAA);
                x_off += 1;
            }
        } else if (mod_type == .filter) {
            // Show filter-specific info: port type + filter type
            x_off += 1;
            const port_name = cell.port_type.name();
            for (port_name) |c| {
                lnpc.lnpc_char(gfx, x_off, y, c, cell.port_type.toColor());
                x_off += 1;
            }
            // Show filter type based on port color
            x_off += 1;
            const filt_name: []const u8 = switch (cell.port_type) {
                .ctrl_a => "(LP)",
                .ctrl_b => "(HP)",
                .ctrl_c => "(BP)",
                .ctrl_d => "(notch)",
                else => "",
            };
            for (filt_name) |c| {
                lnpc.lnpc_char(gfx, x_off, y, c, 0xFFAAAAAA);
                x_off += 1;
            }
        } else {
            x_off += 1;
            const port_name = cell.port_type.name();
            for (port_name) |c| {
                lnpc.lnpc_char(gfx, x_off, y, c, cell.port_type.toColor());
                x_off += 1;
            }
        }
    }

    // Help - only draw if there's room (don't overlap cell info)
    const help = "S+drag=wire TAB=port";
    const start = WIDTH - help.len - 1;
    if (x_off < start - 2) {
        for (help, 0..) |c, i| {
            lnpc.lnpc_char(gfx, @intCast(start + i), y, c, 0xFF666688);
        }
    }
}

// =============================================================================
// Audio Processing
// =============================================================================

fn processAudio(sg: *SubGrid, frames: u32) void {
    // Process audio following connections from Output back to sources

    const sample_rate_f: f32 = @floatFromInt(SAMPLE_RATE);

    for (0..frames) |frame| {
        var output_sample: f32 = 0;

        // Find output cells and trace back what's connected
        for (0..WIDTH * HEIGHT) |idx| {
            const cell = &sg.cells[idx];
            if (cell.module_type == .output) {
                const x: u32 = @intCast(idx % WIDTH);
                const y: u32 = @intCast(idx / WIDTH);

                // Find what's connected to this output
                for (0..sg.connection_count) |ci| {
                    const conn = &sg.connections[ci];
                    if (conn.dst_x == x and conn.dst_y == y) {
                        output_sample += traceSignal(sg, conn.src_x, conn.src_y, sample_rate_f);
                    }
                }
            }
        }

        // Master volume and clamp
        output_sample = std.math.clamp(output_sample * 0.4, -1.0, 1.0);
        audio_output_buffer[frame * 2] = output_sample;
        audio_output_buffer[frame * 2 + 1] = output_sample;
    }
}

fn traceSignal(sg: *SubGrid, x: u32, y: u32, sample_rate: f32) f32 {
    const idx = y * WIDTH + x;
    const cell = &sg.cells[idx];

    if (cell.module_type == null) return 0;

    return switch (cell.module_type.?) {
        .osc => blk: {
            // Find all contiguous osc cells and gather parameters
            var has_white_port: bool = false;
            var white_port_x: u32 = x;
            var white_port_y: u32 = y;

            // Parameters with defaults
            var base_freq: f32 = 55.0 * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(cell.value)) / 64.0);
            var waveform: u8 = 0; // 0=sin, 1=saw, 2=sqr, 3=tri
            var phase_offset: f32 = 0; // 0-1
            var amplitude: f32 = 1.0;

            var visited: [WIDTH * HEIGHT]bool = [_]bool{false} ** (WIDTH * HEIGHT);
            var stack: [64]struct { px: u32, py: u32 } = undefined;
            var stack_len: usize = 1;
            stack[0] = .{ .px = x, .py = y };

            while (stack_len > 0) {
                stack_len -= 1;
                const pos = stack[stack_len];
                const vi = pos.py * WIDTH + pos.px;
                if (visited[vi]) continue;
                visited[vi] = true;

                const check_cell = sg.cellAt(pos.px, pos.py);
                if (check_cell.module_type != .osc) continue;

                if (check_cell.port_type == .audio_out) {
                    has_white_port = true;
                    white_port_x = pos.px;
                    white_port_y = pos.py;
                }

                // In multi-cell mode, each color controls a parameter
                var has_connection = false;
                for (0..sg.connection_count) |ci| {
                    const conn = &sg.connections[ci];
                    if (conn.dst_x == pos.px and conn.dst_y == pos.py) {
                        has_connection = true;
                        const src_cell = sg.cellAt(conn.src_x, conn.src_y);
                        const cv: f32 = if (src_cell.module_type == .knob)
                            @as(f32, @floatFromInt(src_cell.value)) / 255.0
                        else
                            traceSignal(sg, conn.src_x, conn.src_y, sample_rate) * 0.5 + 0.5;

                        switch (check_cell.port_type) {
                            .ctrl_a => { // cyan = frequency
                                base_freq = 55.0 * std.math.pow(f32, 2.0, cv * 4.0);
                            },
                            .ctrl_b => waveform = @intFromFloat(cv * 3.99), // magenta = waveform
                            .ctrl_c => phase_offset = cv, // green = phase
                            .ctrl_d => amplitude = cv, // yellow = amplitude
                            else => {},
                        }
                    }
                }

                // If no connection, use cell's value for that parameter
                if (!has_connection and check_cell.port_type != .audio_out and check_cell.port_type != .audio_in) {
                    switch (check_cell.port_type) {
                        .ctrl_a => base_freq = 55.0 * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(check_cell.value)) / 64.0),
                        .ctrl_b => waveform = check_cell.value >> 6,
                        .ctrl_c => phase_offset = @as(f32, @floatFromInt(check_cell.value)) / 255.0,
                        .ctrl_d => amplitude = @as(f32, @floatFromInt(check_cell.value)) / 255.0,
                        else => {},
                    }
                }

                if (stack_len < 60) {
                    if (pos.px > 0) {
                        stack[stack_len] = .{ .px = pos.px - 1, .py = pos.py };
                        stack_len += 1;
                    }
                    if (pos.px < WIDTH - 1) {
                        stack[stack_len] = .{ .px = pos.px + 1, .py = pos.py };
                        stack_len += 1;
                    }
                    if (pos.py > 0) {
                        stack[stack_len] = .{ .px = pos.px, .py = pos.py - 1 };
                        stack_len += 1;
                    }
                    if (pos.py < HEIGHT - 1) {
                        stack[stack_len] = .{ .px = pos.px, .py = pos.py + 1 };
                        stack_len += 1;
                    }
                }
            }

            // Determine output behavior based on mode
            if (has_white_port) {
                // Multi-cell mode: only output from white cell
                if (x != white_port_x or y != white_port_y) break :blk 0;
            } else {
                // Single-cell mode: color = waveform, value = frequency
                switch (cell.port_type) {
                    .ctrl_a => waveform = 0, // cyan = sine
                    .ctrl_b => waveform = 1, // magenta = saw
                    .ctrl_c => waveform = 2, // green = square
                    .ctrl_d => waveform = 3, // yellow = triangle
                    else => waveform = 0, // white/red default to sine
                }
                base_freq = 55.0 * std.math.pow(f32, 2.0, @as(f32, @floatFromInt(cell.value)) / 64.0);
            }

            // Calculate phase with offset
            const out_idx = white_port_y * WIDTH + white_port_x;
            sg.osc_phases[out_idx] += base_freq / sample_rate;
            if (sg.osc_phases[out_idx] >= 1.0) sg.osc_phases[out_idx] -= 1.0;
            var phase = sg.osc_phases[out_idx] + phase_offset;
            if (phase >= 1.0) phase -= 1.0;

            // Generate waveform
            const raw = switch (waveform) {
                0 => std.math.sin(phase * std.math.tau),
                1 => phase * 2.0 - 1.0,
                2 => if (phase < 0.5) @as(f32, 1.0) else @as(f32, -1.0),
                3 => if (phase < 0.5) phase * 4.0 - 1.0 else 3.0 - phase * 4.0,
                else => 0,
            };

            break :blk raw * amplitude;
        },
        .lfo => {
            // Find all contiguous LFO cells and gather parameters
            var has_white_port: bool = false;
            var white_port_x: u32 = x;
            var white_port_y: u32 = y;

            // Parameters with defaults
            var base_rate: f32 = 0.1 + @as(f32, @floatFromInt(cell.value)) / 255.0 * 19.9;
            var waveform: u8 = 0; // 0=sin, 1=saw, 2=sqr, 3=tri
            var phase_offset: f32 = 0; // 0-1
            var amplitude: f32 = 1.0;

            var visited: [WIDTH * HEIGHT]bool = [_]bool{false} ** (WIDTH * HEIGHT);
            var stack: [64]struct { px: u32, py: u32 } = undefined;
            var stack_len: usize = 1;
            stack[0] = .{ .px = x, .py = y };

            while (stack_len > 0) {
                stack_len -= 1;
                const pos = stack[stack_len];
                const vi = pos.py * WIDTH + pos.px;
                if (visited[vi]) continue;
                visited[vi] = true;

                const check_cell = sg.cellAt(pos.px, pos.py);
                if (check_cell.module_type != .lfo) continue;

                if (check_cell.port_type == .audio_out) {
                    has_white_port = true;
                    white_port_x = pos.px;
                    white_port_y = pos.py;
                }

                // In multi-cell mode, each color controls a parameter
                // Check for connections first, fall back to cell value
                var has_connection = false;
                for (0..sg.connection_count) |ci| {
                    const conn = &sg.connections[ci];
                    if (conn.dst_x == pos.px and conn.dst_y == pos.py) {
                        has_connection = true;
                        const src_cell = sg.cellAt(conn.src_x, conn.src_y);
                        const cv: f32 = if (src_cell.module_type == .knob)
                            @as(f32, @floatFromInt(src_cell.value)) / 255.0
                        else if (src_cell.module_type == .tempo) blk: {
                            const bpm = 40.0 + @as(f32, @floatFromInt(src_cell.value)) / 255.0 * 160.0;
                            break :blk bpm / 120.0; // normalize around 120bpm
                        } else traceSignal(sg, conn.src_x, conn.src_y, sample_rate) * 0.5 + 0.5;

                        switch (check_cell.port_type) {
                            .ctrl_a => base_rate = 0.1 + cv * 19.9, // cyan = rate
                            .ctrl_b => waveform = @intFromFloat(cv * 3.99), // magenta = waveform
                            .ctrl_c => phase_offset = cv, // green = phase
                            .ctrl_d => amplitude = cv, // yellow = amplitude
                            else => {},
                        }
                    }
                }

                // If no connection, use cell's value for that parameter
                if (!has_connection and check_cell.port_type != .audio_out and check_cell.port_type != .audio_in) {
                    switch (check_cell.port_type) {
                        .ctrl_a => base_rate = 0.1 + @as(f32, @floatFromInt(check_cell.value)) / 255.0 * 19.9,
                        .ctrl_b => waveform = check_cell.value >> 6, // top 2 bits
                        .ctrl_c => phase_offset = @as(f32, @floatFromInt(check_cell.value)) / 255.0,
                        .ctrl_d => amplitude = @as(f32, @floatFromInt(check_cell.value)) / 255.0,
                        else => {},
                    }
                }

                if (stack_len < 60) {
                    if (pos.px > 0) {
                        stack[stack_len] = .{ .px = pos.px - 1, .py = pos.py };
                        stack_len += 1;
                    }
                    if (pos.px < WIDTH - 1) {
                        stack[stack_len] = .{ .px = pos.px + 1, .py = pos.py };
                        stack_len += 1;
                    }
                    if (pos.py > 0) {
                        stack[stack_len] = .{ .px = pos.px, .py = pos.py - 1 };
                        stack_len += 1;
                    }
                    if (pos.py < HEIGHT - 1) {
                        stack[stack_len] = .{ .px = pos.px, .py = pos.py + 1 };
                        stack_len += 1;
                    }
                }
            }

            // Determine output behavior based on mode
            if (has_white_port) {
                // Multi-cell mode: only output from white cell
                if (x != white_port_x or y != white_port_y) return 0;
            } else {
                // Single-cell mode: color = waveform, value = rate
                switch (cell.port_type) {
                    .ctrl_a => waveform = 0, // cyan = sine
                    .ctrl_b => waveform = 1, // magenta = saw
                    .ctrl_c => waveform = 2, // green = square
                    .ctrl_d => waveform = 3, // yellow = triangle
                    else => waveform = 0, // white/red default to sine
                }
                base_rate = 0.1 + @as(f32, @floatFromInt(cell.value)) / 255.0 * 19.9;
            }

            // Calculate phase with offset
            const out_idx = white_port_y * WIDTH + white_port_x;
            sg.lfo_phases[out_idx] += base_rate / sample_rate;
            if (sg.lfo_phases[out_idx] >= 1.0) sg.lfo_phases[out_idx] -= 1.0;
            var phase = sg.lfo_phases[out_idx] + phase_offset;
            if (phase >= 1.0) phase -= 1.0;

            // Generate waveform
            // Square uses 25% duty cycle for better sequencer/gate behavior
            const raw = switch (waveform) {
                0 => std.math.sin(phase * std.math.tau),
                1 => phase * 2.0 - 1.0,
                2 => if (phase < 0.25) @as(f32, 1.0) else @as(f32, -1.0),
                3 => if (phase < 0.5) phase * 4.0 - 1.0 else 3.0 - phase * 4.0,
                else => 0,
            };

            return raw * amplitude;
        },
        .knob => processKnob(cell.value),
        .filter => {
            // Only output from audio_out port
            if (cell.port_type != .audio_out) return 0;

            // Find all contiguous filter cells and gather inputs
            var input: f32 = 0;
            var cutoff: f32 = 0.5;
            var filter_type: u8 = 0; // 0=LP, 1=HP, 2=BP, 3=notch

            var visited: [WIDTH * HEIGHT]bool = [_]bool{false} ** (WIDTH * HEIGHT);
            var stack: [64]struct { x: u32, y: u32 } = undefined;
            var stack_len: usize = 1;
            stack[0] = .{ .x = x, .y = y };

            while (stack_len > 0) {
                stack_len -= 1;
                const pos = stack[stack_len];
                const vi = pos.y * WIDTH + pos.x;
                if (visited[vi]) continue;
                visited[vi] = true;

                const check_cell = sg.cellAt(pos.x, pos.y);
                if (check_cell.module_type != .filter) continue;

                // Determine filter type from port colors present
                switch (check_cell.port_type) {
                    .ctrl_a => filter_type = 0, // cyan = lowpass
                    .ctrl_b => filter_type = 1, // magenta = highpass
                    .ctrl_c => filter_type = 2, // green = bandpass
                    .ctrl_d => filter_type = 3, // yellow = notch
                    else => {},
                }

                // Check connections to this filter cell based on its port type
                for (0..sg.connection_count) |ci| {
                    const conn = &sg.connections[ci];
                    if (conn.dst_x == pos.x and conn.dst_y == pos.y) {
                        if (check_cell.port_type == .audio_in) {
                            // Red cell = audio input
                            input = traceSignal(sg, conn.src_x, conn.src_y, sample_rate);
                        } else if (check_cell.port_type != .audio_out) {
                            // Any non-input/output port = CV for cutoff
                            const src_cell = sg.cellAt(conn.src_x, conn.src_y);
                            if (src_cell.module_type == .knob) {
                                cutoff = @as(f32, @floatFromInt(src_cell.value)) / 255.0;
                            } else {
                                // Use traceSignal for LFO and everything else
                                cutoff = 0.5 + traceSignal(sg, conn.src_x, conn.src_y, sample_rate) * 0.4;
                            }
                        }
                    }
                }

                // Add neighbors to stack
                if (stack_len < 60) {
                    if (pos.x > 0) {
                        stack[stack_len] = .{ .x = pos.x - 1, .y = pos.y };
                        stack_len += 1;
                    }
                    if (pos.x < WIDTH - 1) {
                        stack[stack_len] = .{ .x = pos.x + 1, .y = pos.y };
                        stack_len += 1;
                    }
                    if (pos.y > 0) {
                        stack[stack_len] = .{ .x = pos.x, .y = pos.y - 1 };
                        stack_len += 1;
                    }
                    if (pos.y < HEIGHT - 1) {
                        stack[stack_len] = .{ .x = pos.x, .y = pos.y + 1 };
                        stack_len += 1;
                    }
                }
            }

            // Apply filter based on type
            const coef = std.math.clamp(cutoff, 0.01, 0.99);
            const prev_state = sg.filter_states[idx];
            sg.filter_states[idx] += coef * (input - sg.filter_states[idx]);

            return switch (filter_type) {
                0 => sg.filter_states[idx], // lowpass
                1 => input - sg.filter_states[idx], // highpass
                2 => (sg.filter_states[idx] - prev_state) * 4.0, // bandpass
                3 => input - (sg.filter_states[idx] - prev_state) * 2.0, // notch
                else => sg.filter_states[idx],
            };
        },
        .amp => {
            // Only output from audio_out port
            if (cell.port_type != .audio_out) return 0;

            // Find all contiguous amp cells and gather inputs
            var input: f32 = 0;
            var gain: f32 = 1.0;

            var visited: [WIDTH * HEIGHT]bool = [_]bool{false} ** (WIDTH * HEIGHT);
            var stack: [64]struct { x: u32, y: u32 } = undefined;
            var stack_len: usize = 1;
            stack[0] = .{ .x = x, .y = y };

            while (stack_len > 0) {
                stack_len -= 1;
                const pos = stack[stack_len];
                const vi = pos.y * WIDTH + pos.x;
                if (visited[vi]) continue;
                visited[vi] = true;

                const check_cell = sg.cellAt(pos.x, pos.y);
                if (check_cell.module_type != .amp) continue;

                // Check connections based on port type
                for (0..sg.connection_count) |ci| {
                    const conn = &sg.connections[ci];
                    if (conn.dst_x == pos.x and conn.dst_y == pos.y) {
                        if (check_cell.port_type == .audio_in) {
                            // Red cell = audio input
                            input = traceSignal(sg, conn.src_x, conn.src_y, sample_rate);
                        } else if (check_cell.port_type == .ctrl_d) {
                            // Yellow cell = gain CV
                            const src_cell = sg.cellAt(conn.src_x, conn.src_y);
                            if (src_cell.module_type == .knob) {
                                gain = @as(f32, @floatFromInt(src_cell.value)) / 255.0;
                            } else {
                                // Use traceSignal for LFO and everything else
                                gain = 0.5 + traceSignal(sg, conn.src_x, conn.src_y, sample_rate) * 0.5;
                            }
                        }
                    }
                }

                // Add neighbors
                if (stack_len < 60) {
                    if (pos.x > 0) {
                        stack[stack_len] = .{ .x = pos.x - 1, .y = pos.y };
                        stack_len += 1;
                    }
                    if (pos.x < WIDTH - 1) {
                        stack[stack_len] = .{ .x = pos.x + 1, .y = pos.y };
                        stack_len += 1;
                    }
                    if (pos.y > 0) {
                        stack[stack_len] = .{ .x = pos.x, .y = pos.y - 1 };
                        stack_len += 1;
                    }
                    if (pos.y < HEIGHT - 1) {
                        stack[stack_len] = .{ .x = pos.x, .y = pos.y + 1 };
                        stack_len += 1;
                    }
                }
            }

            // Apply base gain from cell value, then CV modulation
            const base_gain = @as(f32, @floatFromInt(cell.value)) / 255.0;
            return input * base_gain * gain;
        },
        .mixer => {
            var sum: f32 = 0;
            for (0..sg.connection_count) |ci| {
                const conn = &sg.connections[ci];
                if (conn.dst_x == x and conn.dst_y == y) {
                    sum += traceSignal(sg, conn.src_x, conn.src_y, sample_rate);
                }
            }
            return sum;
        },
        .gate => {
            // Gate/comparator: outputs 1.0 if input > threshold, else -1.0
            // Only output from audio_out port
            if (cell.port_type != .audio_out) return 0;

            var input: f32 = 0;
            var threshold: f32 = 0; // default threshold at 0

            // Find all contiguous gate cells
            var visited: [WIDTH * HEIGHT]bool = [_]bool{false} ** (WIDTH * HEIGHT);
            var stack: [64]struct { gx: u32, gy: u32 } = undefined;
            var stack_len: usize = 1;
            stack[0] = .{ .gx = x, .gy = y };

            while (stack_len > 0) {
                stack_len -= 1;
                const pos = stack[stack_len];
                const vi = pos.gy * WIDTH + pos.gx;
                if (visited[vi]) continue;
                visited[vi] = true;

                const check_cell = sg.cellAt(pos.gx, pos.gy);
                if (check_cell.module_type != .gate) continue;

                // Check connections based on port type
                for (0..sg.connection_count) |ci| {
                    const conn = &sg.connections[ci];
                    if (conn.dst_x == pos.gx and conn.dst_y == pos.gy) {
                        if (check_cell.port_type == .audio_in) {
                            input = traceSignal(sg, conn.src_x, conn.src_y, sample_rate);
                        } else if (check_cell.port_type == .ctrl_a) {
                            // Threshold from connection
                            const src_cell = sg.cellAt(conn.src_x, conn.src_y);
                            if (src_cell.module_type == .knob) {
                                threshold = (@as(f32, @floatFromInt(src_cell.value)) - 128.0) / 128.0;
                            } else {
                                threshold = traceSignal(sg, conn.src_x, conn.src_y, sample_rate);
                            }
                        }
                    }
                }

                // If no connection, use cell's value for threshold
                if (check_cell.port_type == .ctrl_a) {
                    var has_conn = false;
                    for (0..sg.connection_count) |ci| {
                        const conn = &sg.connections[ci];
                        if (conn.dst_x == pos.gx and conn.dst_y == pos.gy) {
                            has_conn = true;
                            break;
                        }
                    }
                    if (!has_conn) {
                        // Value 0-255 maps to threshold -1.0 to 1.0
                        threshold = (@as(f32, @floatFromInt(check_cell.value)) - 128.0) / 128.0;
                    }
                }

                // Add neighbors
                if (stack_len < 60) {
                    if (pos.gx > 0) {
                        stack[stack_len] = .{ .gx = pos.gx - 1, .gy = pos.gy };
                        stack_len += 1;
                    }
                    if (pos.gx < WIDTH - 1) {
                        stack[stack_len] = .{ .gx = pos.gx + 1, .gy = pos.gy };
                        stack_len += 1;
                    }
                    if (pos.gy > 0) {
                        stack[stack_len] = .{ .gx = pos.gx, .gy = pos.gy - 1 };
                        stack_len += 1;
                    }
                    if (pos.gy < HEIGHT - 1) {
                        stack[stack_len] = .{ .gx = pos.gx, .gy = pos.gy + 1 };
                        stack_len += 1;
                    }
                }
            }

            // Output gate signal
            return if (input > threshold) @as(f32, 1.0) else @as(f32, -1.0);
        },
        .composite => {
            // Trace signal from inside the composite's subgrid
            if (cell.subgrid_id) |sub_id| {
                const sub = &subgrids[sub_id];
                // Find output port cells inside and sum their signals
                var sum: f32 = 0;
                for (0..WIDTH * HEIGHT) |i| {
                    const sub_cell = &sub.cells[i];
                    if (sub_cell.module_type == .port and sub_cell.port_type == .audio_out) {
                        const px: u32 = @intCast(i % WIDTH);
                        const py: u32 = @intCast(i / WIDTH);
                        // Trace what's connected to this output port
                        for (0..sub.connection_count) |ci| {
                            const conn = &sub.connections[ci];
                            if (conn.dst_x == px and conn.dst_y == py) {
                                sum += traceSignal(sub, conn.src_x, conn.src_y, sample_rate);
                            }
                        }
                    }
                }
                return sum;
            }
            return 0;
        },
        .port => {
            // Port inside a subgrid: trace what's connected to it
            if (cell.port_type == .audio_out) {
                var sum: f32 = 0;
                for (0..sg.connection_count) |ci| {
                    const conn = &sg.connections[ci];
                    if (conn.dst_x == x and conn.dst_y == y) {
                        sum += traceSignal(sg, conn.src_x, conn.src_y, sample_rate);
                    }
                }
                return sum;
            }
            return 0;
        },
        else => 0,
    };
}

fn processKnob(value: u8) f32 {
    return (@as(f32, @floatFromInt(value)) - 128.0) / 128.0;
}

fn initAudio() void {
    ray.InitAudioDevice();
    audio_stream = ray.LoadAudioStream(SAMPLE_RATE, 32, 2);
    ray.PlayAudioStream(audio_stream);
    audio_initialized = true;
}

fn updateAudio() void {
    if (!audio_initialized) return;

    if (ray.IsAudioStreamProcessed(audio_stream)) {
        processAudio(currentGrid(), BUFFER_SIZE);
        ray.UpdateAudioStream(audio_stream, &audio_output_buffer, BUFFER_SIZE);
    }
}

fn deinitAudio() void {
    if (audio_initialized) {
        ray.StopAudioStream(audio_stream);
        ray.UnloadAudioStream(audio_stream);
        ray.CloseAudioDevice();
    }
}

// =============================================================================
// Main
// =============================================================================

pub fn main() void {
    gfx = lnpc.lnpc_grid(WIDTH, HEIGHT) orelse return;
    defer lnpc.lnpc_nogrid(gfx);

    // Initialize subgrids
    for (&subgrids) |*sg| {
        sg.* = SubGrid.init(null);
    }

    // Create root subgrid
    _ = createSubgrid(null);
    nav_stack[0] = 0;
    nav_depth = 0;

    const w = lnpc.lnpc_window(20, gfx) orelse return;
    defer lnpc.lnpc_nowindow(w);

    ray.SetExitKey(ray.KEY_NULL);

    initAudio();
    defer deinitAudio();

    // Demo: 8-Step Sequencer in a Composite module
    const root = currentGrid();

    // Create composite cell in root grid
    root.cellAt(10, 10).* = .{ .module_type = .composite, .port_type = .audio_out, .value = 128 };

    // Create subgrid for the composite
    const sub_id = createSubgrid(0);
    root.cellAt(10, 10).subgrid_id = sub_id;
    const seq = &subgrids[sub_id];

    // Sequencer parameters
    const seq_rate: u8 = 12;
    const gate_thresh: u8 = 246;
    const phases = [8]u8{ 0, 32, 64, 96, 128, 160, 192, 224 };
    const pitches = [8]u8{ 64, 76, 88, 96, 104, 116, 128, 140 };

    // Build 8-step sequencer inside the composite
    var step: u32 = 0;
    while (step < 8) : (step += 1) {
        const base_x: u32 = 2 + step * 7;
        const base_y: u32 = 2;

        // LFO: sine with phase offset
        seq.cellAt(base_x, base_y).* = .{ .module_type = .lfo, .port_type = .ctrl_a, .value = seq_rate };
        seq.cellAt(base_x + 1, base_y).* = .{ .module_type = .lfo, .port_type = .ctrl_c, .value = phases[step] };
        seq.cellAt(base_x + 2, base_y).* = .{ .module_type = .lfo, .port_type = .audio_out, .value = seq_rate };

        // Gate: input, threshold, output
        seq.cellAt(base_x + 3, base_y).* = .{ .module_type = .gate, .port_type = .audio_in, .value = 128 };
        seq.cellAt(base_x + 4, base_y).* = .{ .module_type = .gate, .port_type = .ctrl_a, .value = gate_thresh };
        seq.cellAt(base_x + 5, base_y).* = .{ .module_type = .gate, .port_type = .audio_out, .value = 128 };

        // Oscillator: saw wave
        seq.cellAt(base_x + 1, base_y + 2).* = .{ .module_type = .osc, .port_type = .ctrl_b, .value = pitches[step] };

        // Amp: audio in, cv, audio out
        seq.cellAt(base_x + 3, base_y + 2).* = .{ .module_type = .amp, .port_type = .audio_in, .value = 200 };
        seq.cellAt(base_x + 4, base_y + 2).* = .{ .module_type = .amp, .port_type = .ctrl_d, .value = 200 };
        seq.cellAt(base_x + 5, base_y + 2).* = .{ .module_type = .amp, .port_type = .audio_out, .value = 200 };

        // Internal connections
        seq.addConnection(gfx, base_x + 2, base_y, base_x + 3, base_y); // LFO -> Gate
        seq.addConnection(gfx, base_x + 1, base_y + 2, base_x + 3, base_y + 2); // Osc -> Amp in
        seq.addConnection(gfx, base_x + 5, base_y, base_x + 4, base_y + 2); // Gate -> Amp cv
        seq.addConnection(gfx, base_x + 5, base_y + 2, 30, 8); // Amp -> internal mixer
    }

    // Internal mixer
    seq.cellAt(30, 8).* = .{ .module_type = .mixer, .port_type = .audio_out, .value = 128 };

    // Output port - exposes signal to parent
    seq.cellAt(35, 8).* = .{ .module_type = .port, .port_type = .audio_out, .value = 128 };
    seq.addConnection(gfx, 30, 8, 35, 8); // mixer -> output port

    // In root grid: connect composite to output
    root.cellAt(20, 10).* = .{ .module_type = .output, .port_type = .audio_in, .value = 128 };
    root.addConnection(gfx, 10, 10, 20, 10); // composite -> output

    while (!lnpc.lnpc_draw(w)) {
        handleInput();
        updateAudio();
        updateTempo();
        render();
    }
}

fn updateTempo() void {
    const sg = currentGrid();
    const dt = ray.GetFrameTime();

    // Find tempo cells and update phase
    for (0..WIDTH * HEIGHT) |idx| {
        const cell = &sg.cells[idx];
        if (cell.module_type == .tempo) {
            // BPM from value: 40-200 BPM
            const bpm = 40.0 + @as(f32, @floatFromInt(cell.value)) / 255.0 * 160.0;
            const beat_freq = bpm / 60.0;

            tempo_phase += beat_freq * dt;
            if (tempo_phase >= 1.0) {
                tempo_phase -= 1.0;
                tempo_beat = true;
            } else if (tempo_phase > 0.1) {
                tempo_beat = false;
            }
            return; // Only use first tempo found
        }
    }
}
