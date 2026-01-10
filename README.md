# linopic

Simple, intentionally-constrained, easy GUI library with a C ABI.
Like NCurses but _just_ powerful enough for beautiful tools.

This exposes a very beautiful C FFI that C developers (and other FFIs) love to use.

### 

Here's the idea, it's a cell-based GUI library, where each cell can contain a monospace character, a background color, a foreground color, 
or recursive subcells.

### Basics of how it works.

/* initialize a grid */
g = lnpc_grid(800, 600)

/* open a window with that grid */
l = lnpc_open(cell_size: u32, g)

/* get a cell from the grid */
cell = lnpc_getcell(g, x, y)

/* set a cell from the grid */
lnpc_setcell(g, x, y, cell)

/* close a window */
lnpc_close(l)

### Under the hood

Uses raylib, written in zig.
