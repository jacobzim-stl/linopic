// =============================================================================
// C ABI Exports
// =============================================================================

pub const Line = u32;

pub const Window = struct {
    linopic: *Linopic,
    // ...
};

pub const Linopic = struct {
    width: u32,
    height: u32,
    // ...
};

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

pub export fn lnpc_draw(w: *Window) bool {
    shouldClose = // ...;
        return shouldClose;
}

pub export fn lnpc_window(cell_size: u32, g: *Linopic) ?*Window {
    // ...
}

pub export fn lnpc_nowindow(w: *Window) bool {
    // ...
}

pub export fn lnpc_grid(w: u32, h: u32) ?*Linopic {
    // ...
}

pub export fn lnpc_nogrid(?*Linopic) void {
    // ...
}

pub export fn lnpc_bg(linopic: *Linopic, x: u32, y: u32, color: Color) void {
    // ...
}

pub export fn lnpc_nobg(linopic: *Linopic, x: u32, y: u32, color: Color) void {
    // ...
}

pub export fn lnpc_char(linopic: *Linopic, x: u32, y: u32, rune: u32, color: Color) void {
    // ...
}

pub export fn lnpc_nochar(linopic: *Linopic, x: u32, y: u32, rune: u32, color: Color) void {
    // ...
}

//
pub export fn lnpc_line(linopic: *Linopic, ax: u32, ay: u32, bx: u32, by: u32, bendiness: i8) *Line {
    // ...
}

pub export fn lnpc_noline(linopic: *Linopic, line: *Line) void {
    // ...
}

pub export fn lnpc_subgrid(parent: *Linopic, child: *Linopic, x: u32, y: u32, w: u32, h: u32) bool {
    // ...
}

pub export fn lnpc_nosubgrid(parent: *Linopic, child: *Linopic) bool {
    // ...
}
