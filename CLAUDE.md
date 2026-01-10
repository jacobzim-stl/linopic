# linopic

Cell-based GUI library with C ABI. Like ncurses but graphical.

## Development

**Outside-in.** API first, stub internals, test incrementally.

## Commands

```
zig build test      # unit tests
zig build run       # run example
```

## Structure

```
src/
  linopic.zig       # library
  main.zig          # example
  font.ttf          # embedded JetBrains Mono
```

## API (Zig)

```zig
const grid = Grid.create(40, 20) orelse return;
defer grid.destroy();

grid.print(x, y, "text", fg, bg);
grid.put(x, y, 'A', fg, bg);
grid.set(x, y, Cell{ .char = 'B', .fg = Color.black, .bg = Color.white });

const window = Window.open(font_size, grid) orelse return;
defer window.close();

while (!window.shouldClose()) {
    window.render();
}
```

## API (C)

```c
Grid* g = lnpc_grid(40, 20);
Window* w = lnpc_open(24, g);
lnpc_set(g, x, y, cell);
lnpc_render(w);
lnpc_close(w);
lnpc_grid_destroy(g);
```
