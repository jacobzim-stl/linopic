# linopic

Cell-based GUI for terminal-style interfaces. ncurses, but better.

## Quick Start

```c
#include <linopic.h>

int main(void) {
    Grid *g = lnpc_grid(80, 24);
    Window *w = lnpc_window(16, g);
    
    while (lnpc_draw(w)) {
        // ...
    }

    lnpc_nowindow(w);
    lnpc_nogrid(g);
    return 0;
}
```

## API

```c
typedef ... Window;
typedef ... Grid;
typedef uint32_t Color; // rgba
typedef uint32_t Line;
typedef uint32_t Spline;

struct MouseEvt {
    int x, y;
    bool is_down, is_pressed, is_released;
};

struct KeyState {
    bool is_down, is_pressed, is_released;
};

Window *lnpc_window(uint32_t font_size, Grid *g);
void    lnpc_nowindow(Window *w);
bool    lnpc_draw(Window *w); // returns false when should quit

Grid *lnpc_grid(uint32_t width, uint32_t height);
void  lnpc_nogrid(Grid *g);

MouseEvt lnpc_mouse(Grid *g, int mouse); // 0 is left, 1 is right, 2 is middle
KeyState lnpc_key(Key k); // either a Key enum or a char

Color rgb(uint8_t r, uint8_t g, uint8_t b);
Color rgba(uint8_t r, uint8_t g, uint8_t b, uint8_t a);
Color hex(const char *hex);

void lnpc_bg(Grid *g, uint32_t x, uint32_t y, Color color);
void lnpc_nobg(Grid *g, uint32_t x, uint32_t y);

void lnpc_char(Grid *g, uint32_t x, uint32_t y, uint32_t codepoint, Color fg);
void lnpc_nochar(Grid *g, uint32_t x, uint32_t y);

Line lnpc_line(Grid *g, uint32_t x1, uint32_t y1, uint32_t x2, uint32_t y2, Color color, enum LineStyle style);
void lnpc_noline(Grid *g, Line line);

// not yet implemented
Spline lnpc_spline(Grid *g, ...);
void   lnpc_nospline(Grid *g, Spline spline);

// not yet implemented
bool lnpc_subgrid(Grid *parent, Grid *child, uint32_t x, uint32_t y, uint32_t w, uint32_t h);
void lnpc_nosubgrid(Grid *parent, Grid *child);

enum LineStyle {
    // Default: straight line = 0
    LNPC_LINE_2SEG        = 0x00000001, // 2 segment line, run then rise
    LNPC_LINE_3SEG        = 0x00000002, // 3 segment line, run then rise then run
    
     // Default: subtle rounded corner = 0
    LNPC_LINE_CORNER_HARD = 0x00000010, // hard-edges
    LNPC_LINE_CORNER_NONE = 0x00000020, // no corners, smooth bend
    
    // Default: bias towards midpoint = 0
    LNPC_LINE_BIAS_START = 0x00000100, // bias towards startpoint
    LNPC_LINE_BIAS_END   = 0x0000c000, // bias towards endpoint
};

const char LNPC_KEY_SHIFT = 0x01;
const char LNPC_KEY_CTRL  = 0x02;
const char LNPC_KEY_ALT   = 0x04;
const char LNPC_KEY_SUPER = 0x08;
const char LNPC_KEY_ENTER = 0x10;
const char LNPC_KEY_BKSP  = 0x20;
const char LNPC_KEY_SPACE = 0x40;
const char LNPC_KEY_ESC   = 0x80;

```

## Building

```
zig build              # build library
zig build test         # run tests
```

## Examples

```
zig build run          # run demo (line styles, colors)
zig build editor       # run text editor example
```
