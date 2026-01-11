# linopic

Cell-based GUI for terminal-style interfaces. ncurses, but graphical.

## Quick Start

```c
#include <linopic.h>

int main(void) {
    Grid *g = lnpc_grid(80, 24);
    Window *w = lnpc_window(16, g);

    lnpc_char(g, 0, 0, 'H', 0xFFFFFF);
    lnpc_char(g, 1, 0, 'i', 0xFFFFFF);
    lnpc_bg(g, 0, 0, 0x282850);
    lnpc_bg(g, 1, 0, 0x282850);

    while (!lnpc_draw(w)) {}

    lnpc_nowindow(w);
    lnpc_nogrid(g);
    return 0;
}
```

## API

### Grid

```c
Grid *lnpc_grid(uint32_t width, uint32_t height);
void  lnpc_nogrid(Grid *g);
```

### Window

```c
Window *lnpc_window(uint32_t font_size, Grid *g);
void    lnpc_nowindow(Window *w);
bool    lnpc_draw(Window *w);
```

### Characters

```c
void lnpc_char(Grid *g, uint32_t x, uint32_t y, uint32_t codepoint, Color fg);
void lnpc_nochar(Grid *g, uint32_t x, uint32_t y);
```

### Background

```c
void lnpc_bg(Grid *g, uint32_t x, uint32_t y, Color color);
void lnpc_nobg(Grid *g, uint32_t x, uint32_t y);
```

### Color

```c
typedef uint32_t Color;

Color rgb(uint8_t r, uint8_t g, uint8_t b);

0xFF0000            // red
0x00FF00            // green
rgb(255, 128, 0)    // orange
```

## Naming

- `lnpc_thing` creates or does
- `lnpc_nothing` removes or destroys

## Building

```
zig build              # build library
zig build run          # run example
zig build test         # run tests
```
