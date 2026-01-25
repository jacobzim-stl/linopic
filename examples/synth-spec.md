# Modular Synth Specification v0.0.1

## Overview

A cell-based modular synthesizer built on linopic. The design follows west-coast synthesis philosophy with function generators and vactrols, while retaining east-coast fundamentals (filters, amps) for learning and precision control.

## Core Principles

1. **Grid is the canvas** — navigable via keyboard and mouse
2. **Empty space separates** — gap between cells = separate modules
3. **Wires connect** — directional (start → end = signal flow)
4. **Simple rules, emergent complexity** — like physical modular synths

## Cells

A cell is a position on the grid with the following properties:
- **Character**: defines module type (or empty)
- **Color**: variant (single-cell) or port role (multi-cell)
- **Value**: 0-255, parameter value

## Modules

Adjacent cells of the same type form one module. A single cell is also a module.

## Boards

A Board cell contains a sub-grid:
- From outside: one cell, connections via ports (`.`)
- From inside: full grid with its own cells and wires
- Boards can be nested

## Module Modes

### Single-Cell Mode

Compact, immediate, simplified:
- **Sources**: incoming wire = parameter modulation, output = generated signal
- **Processors**: incoming wire = audio input, output = processed signal
- Value controls the primary parameter
- Color selects the variant/type

### Multi-Cell Mode

Expanded, full control:
- Adjacent cells of same type form one module
- **White cell** = audio output (required)
- **Red cell** = audio input
- **Colored cells** = parameter ports (cyan/magenta/green/yellow)
- Wire to colored cell = CV modulation of that parameter
- Cell value = base value for that parameter

## Color Semantics

### Single-Cell (Variant Selection)

| Color | Oscillator/Function | Filter | General |
|-------|---------------------|--------|---------|
| Cyan | Sine | Lowpass | Type A |
| Magenta | Saw | Highpass | Type B |
| Green | Square | Bandpass | Type C |
| Yellow | Triangle | Notch | Type D |
| White | (default) | (default) | Output |
| Red | — | — | Input |

### Multi-Cell (Port Role)

| Color | Role | Typical Parameter |
|-------|------|-------------------|
| Red | Audio input | Signal to process |
| White | Audio output | Processed/generated signal |
| Cyan | Parameter A | Frequency, cutoff, rate |
| Magenta | Parameter B | Waveform, resonance, curve |
| Green | Parameter C | Phase, type, shape |
| Yellow | Parameter D | Amplitude, gain, level |

## Module Reference

### Sources

Sources generate signals. In single-cell mode, incoming wires modulate parameters.

#### K — Knob

Outputs a constant value.

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Value | Output level (-1 to +1 mapped from 0-255) | Base output level |
| Color | — | Cyan: fine tune, Yellow: output |
| Incoming | Modulates output value | Per-port modulation |

Use cases: bias voltages, fixed CV, manual control.

#### W — Oscillator

Audio-rate waveform generator.

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Value | Frequency (exponential: ~27Hz to ~7kHz) | Per-port base value |
| Color | Waveform (cyan=sin, mag=saw, grn=sqr, yel=tri) | Port role |
| Incoming | Frequency modulation (FM) | Per-port CV |

**Multi-cell ports:**
- Cyan: frequency
- Magenta: waveform (0-63=sin, 64-127=saw, 128-191=sqr, 192-255=tri)
- Green: phase offset
- Yellow: amplitude
- White: audio output

Frequency scale: `freq = 27.5 * 2^(value/32)` — covers ~8 octaves.

#### ~ — Function Generator

Rise/fall shape generator. Replaces both LFO and envelope depending on patching.

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Value | Fall time (primary tweakable) | Per-port base value |
| Color | Curve shape or rise/fall ratio | Port role |
| Incoming | Trigger (if connected: one-shot mode) | Per-port CV |
| No trigger | Cycles continuously (LFO mode) | — |

**Multi-cell ports:**
- Red: trigger input (rising edge fires envelope)
- Cyan: rise time (0=instant, 255=~5 seconds)
- Magenta: fall time (0=instant, 255=~5 seconds)
- Green: curve shape (0=log, 128=linear, 255=exp)
- Yellow: output amplitude
- White: output

**Behavior modes:**
- **Cycling (LFO)**: no trigger connected → loops continuously
- **One-shot (Envelope)**: trigger connected → fires once per trigger

**Time scale:** `time_ms = (value/255)^2 * 5000` — quadratic for finer control at short times.

### Processors

Processors transform signals. In single-cell mode, incoming wire is audio input.

#### F — Filter

Frequency-domain shaping.

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Value | Cutoff frequency | Per-port base value |
| Color | Type (cyan=LP, mag=HP, grn=BP, yel=notch) | Port role |
| Incoming | Audio input | Per-port signal |

**Multi-cell ports:**
- Red: audio input
- Cyan: cutoff frequency
- Magenta: resonance/Q
- Green: filter type (CV-controllable)
- Yellow: output gain
- White: audio output

Cutoff scale: `freq = 20 * 2^(value/32)` — ~20Hz to ~20kHz.

#### A — Amp

Amplitude control (VCA).

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Value | Gain (0-255 = 0% to 100%) | Per-port base value |
| Color | — | Port role |
| Incoming | Audio input | Per-port signal |

**Multi-cell ports:**
- Red: audio input
- Cyan: gain CV (bipolar, for tremolo)
- Yellow: gain CV (unipolar, for envelope)
- White: audio output

#### V — Vactrol (Low-Pass Gate)

Combined filter + amp with organic response. Simulates vactrol behavior.

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Value | Response speed (0=fast/snappy, 255=slow/smooth) | Per-port base value |
| Color | — | Port role |
| Incoming | Audio input | Per-port signal |

**Multi-cell ports:**
- Red: audio input
- Cyan: CV input (controls both brightness + loudness)
- Magenta: response time
- White: audio output

**Behavior:** CV controls both lowpass cutoff AND amplitude simultaneously. Higher CV = louder + brighter. Lower CV = quieter + duller. This mimics acoustic instrument behavior.

#### S — Slew

Rate-limits signal changes (smoothing, portamento, lag).

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Value | Slew time | Per-port base value |
| Color | Rise/fall balance (cyan=rise only, yellow=fall only, white=both) | Port role |
| Incoming | Signal to smooth | Per-port signal |

**Multi-cell ports:**
- Red: signal input
- Cyan: rise slew time
- Magenta: fall slew time
- White: smoothed output

#### G — Gate

Comparator/threshold detector. Outputs 0 or 1.

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Value | Threshold (-1 to +1 mapped from 0-255) | Per-port base value |
| Color | — | Port role |
| Incoming | Signal to compare | Per-port signal |

**Multi-cell ports:**
- Red: signal input
- Cyan: threshold CV
- White: gate output (0 or 1)

Use cases: convert any signal to square, trigger extraction, comparator logic.

#### + — Mixer

Sums all inputs.

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Value | Output gain/attenuation | Per-port base value |
| Color | — | Port role |
| Incoming | Signals to sum (multiple allowed) | Per-port signal |

All incoming wires are summed. No limit on input count.

### IO

#### O — Output

Audio destination (speakers/DAC).

| Property | Description |
|----------|-------------|
| Value | Master level |
| Incoming | Audio to output |

Multiple O cells = multiple output channels (stereo, etc).

#### . — Port

Exposes signals across board boundaries.

| Property | Single-Cell | Multi-Cell |
|----------|-------------|------------|
| Color | Direction (white=out from board, red=into board) | Port role |
| Incoming | Signal to expose | — |

Used inside boards to create inputs/outputs visible from parent level.

### Structure

#### B — Board

Container for sub-patches. Enables abstraction and reuse.

| Property | Description |
|----------|-------------|
| Value | — |
| Color | — |
| Incoming | Routed to ports inside |
| Enter | Navigate into board (keyboard: Enter) |
| Exit | Navigate out (keyboard: Escape) |

Boards can be nested. Ports (`.`) inside the board appear as connection points on the board cell from outside.

## Wiring Rules

1. **Direction**: start → end = signal flow
2. **Multiple outputs**: one cell can connect to many destinations
3. **Multiple inputs**: one cell can receive from many sources (summed for audio, varies for CV)
4. **Self-patch**: a module can feed back into itself (creates feedback)
5. **Cross-board**: wires cannot cross board boundaries directly; use ports

## Global State

### Tempo (Design TBD)

Options under consideration:
- Global BPM parameter (outside grid)
- First `~` in trigger mode sets master clock
- Explicit clock module with special routing

Currently: no global tempo. Use `~` in cycle mode as clock source.

### Transport

- Play/Pause: global, affects all audio
- (Future: record, loop regions)

## Audio Engine

| Parameter | Value |
|-----------|-------|
| Sample rate | 44100 Hz |
| Buffer size | 512 samples (~11.6ms latency) |
| Bit depth | 32-bit float internal |
| Output | Stereo |

## Keyboard Controls

| Key | Action |
|-----|--------|
| Arrow keys | Move cursor / adjust value (context-dependent) |
| Enter | Place module / enter board |
| Escape | Exit board / cancel |
| Delete/Backspace | Clear cell |
| Tab | Cycle color (variant/port type) |
| Shift+Tab | Cycle color reverse |
| Shift+Arrow | Adjust value by 5 |
| Shift+Drag | Create wire |
| Character keys | Place module (k, w, ~, f, a, v, s, g, +, o, ., b) |

## Mouse Controls

| Action | Effect |
|--------|--------|
| Click | Select cell, move cursor |
| Drag on value-cell | Adjust value |
| Shift+Drag | Create wire from source to destination |
| Right-click | Delete wire at cursor / open context menu |

---

# Annex A: Example — Basic Kick Drum

A kick drum has three components:
- **Sub**: low sine ~40Hz, medium decay
- **Thump**: mid sine ~150Hz, short decay
- **Click**: high content ~2kHz+, very short decay

## Minimal Kick (3 cells + output)

```
W ─→ V ─→ O
     ↑
     ~
```

- `W`: sine oscillator, value=64 (~55Hz)
- `V`: vactrol, shapes the tone
- `~`: function generator, one-shot mode (self-triggering? or free-running fast)
- `O`: output

**Limitation**: single oscillator, single envelope. Sounds thin.

## Standard Kick (9 cells)

```
W ─→ V ─┐
        │
W ─→ V ─┼→ + ─→ O
        │
W ─→ V ─┘
↑    ↑
all ~ (shared trigger)
```

Layout on grid:
```
~ · W · V ─┐
           │
~ · W · V ─┼─ + ─ O
           │
~ · W · V ─┘
```

Configuration:
| Layer | W value | W color | ~ value | Purpose |
|-------|---------|---------|---------|---------|
| Sub | 48 | cyan (sine) | 180 | ~40Hz, slow decay |
| Thump | 80 | cyan (sine) | 120 | ~150Hz, medium decay |
| Click | 160 | green (square) | 40 | ~2kHz, fast decay |

## Punchy Kick with Pitch Sweep

Real kicks often have pitch that sweeps down. The initial "punch" is higher, settling to the sub.

```
~ ─→ W ─→ V ─→ O
│    ↑
│    │
└────┘ (~ modulates W frequency AND V amplitude)
```

Expanded multi-cell version:
```
┌─────────────────────┐
│  ~   ~   ~          │  Function generator (trigger, rise, fall, out)
│  R   C   M   W      │
│          │          │
│          ↓          │
│      W   W   W      │  Oscillator (freq CV, -, -, out)
│      C       W      │
│          │          │
│          ↓          │
│      V   V   V      │  Vactrol (audio in, CV, -, out)
│      R   C       W  │
│              │      │
│              ↓      │
│              O      │  Output
└─────────────────────┘
```

The function generator:
- Triggers itself (cycling at ~2-4Hz for tempo)
- Fast rise, medium fall, exponential curve
- Output goes to BOTH oscillator frequency AND vactrol CV

Result: pitch sweeps from high to low while amplitude decays. Classic 808-style kick.

## Layered Kick with Board Encapsulation

For reuse, encapsulate the kick in a board:

**Inside board "KICK":**
```
. ─────────────────────────────┐ (trigger input port)
│                              │
├─→ ~ ─→ W ─→ V ─┐             │
│   │    ↑       │             │
│   └────┘       │             │
│                ├─→ + ─→ .    │ (audio output port)
├─→ ~ ─→ W ─→ V ─┤             │
│   │    ↑       │             │
│   └────┘       │             │
│                │             │
└─→ ~ ─→ W ─→ V ─┘             │
    │    ↑                     │
    └────┘                     │
```

**From outside:**
```
~ ─→ B ─→ O
     (KICK board)
```

The board appears as single cell. Trigger input fires all internal envelopes. Audio output is the mixed kick.

---

# Annex B: Example — Hi-Hat

Hi-hats are noise-based with very short envelopes.

## Basic Hi-Hat

We need a noise source. Options:
1. Very high frequency oscillator (>10kHz)
2. Multiple detuned oscillators mixed (metallic)
3. Dedicated noise module (N) — not in current spec

**Using high oscillators as pseudo-noise:**
```
W ─┐
   ├─→ + ─→ V ─→ O
W ─┘        ↑
            ~
```

- Two oscillators at different high frequencies (slight detune creates beating)
- Mixed, then through vactrol with very fast envelope

Configuration:
| Cell | Value | Color | Notes |
|------|-------|-------|-------|
| W (1) | 220 | green (square) | ~8kHz |
| W (2) | 224 | green (square) | ~9kHz, detuned |
| ~ | 30 | — | Very fast decay |
| V | 0 | — | Fast response |

## Consideration: Add Noise Module?

A dedicated noise source would simplify hi-hats, snares, and other percussion:

| Char | Name | Description |
|------|------|-------------|
| N | Noise | White/pink/red noise generator |
| | Color | cyan=white, mag=pink, grn=red |

**Deferred decision** — can be added in future version if needed.

---

# Annex C: Example — Bass Sequence

A sequenced bass line using function generators as both clock and envelope.

## 4-Step Bass

```
~ ─→ G ─→ ~ ─→ A ─→ O
         ↗    ↑
W ───────┘    │
              K
```

- First `~`: cycling (LFO mode), slow rate = clock
- `G`: converts to square wave (clean trigger)
- Second `~`: one-shot mode (triggered by G), envelope
- `W`: bass oscillator
- `A`: amp controlled by envelope
- `K`: base gain level

For pitch sequencing, we'd need sample-and-hold or a sequencer module (future consideration).

## Multi-Pitch Sequence (using multiple oscillators)

```
~ ─→ G ─┬→ ~ ─→ A ─┐
        │    ↑     │
        │    W     │
        │   (C)    │
        │          ├→ + ─→ O
        ├→ ~ ─→ A ─┤
        │    ↑     │
        │    W     │
        │   (D)    │
        │          │
        ├→ ~ ─→ A ─┤
        │    ↑     │
        │    W     │
        │   (E)    │
        │          │
        └→ ~ ─→ A ─┘
             ↑
             W
            (G)
```

Each oscillator is a different pitch (C, D, E, G). The clock triggers all envelopes, but only one plays at a time based on...

**Problem**: We need a way to select which voice plays. This requires:
- A sequencer/counter module, or
- Phase-offset function generators (each triggers at different point in cycle)

**Phase-offset approach:**
```
~ (master, cyan, phase=0) ─→ G ─→ ~₁ ─→ A ─→ +
~ (slave, cyan, phase=64) ─→ G ─→ ~₂ ─→ A ─→ +  ─→ O
~ (slave, cyan, phase=128) ─→ G ─→ ~₃ ─→ A ─→ +
~ (slave, cyan, phase=192) ─→ G ─→ ~₄ ─→ A ─→ +
```

Each function generator has different phase offset, so they trigger in sequence.

---

# Annex D: Example — Drone Pad

Evolving drone texture using multiple oscillators and slow modulation.

```
W ─┐
W ─┼→ + ─→ F ─→ A ─→ O
W ─┤        ↑   ↑
W ─┘        ~   ~
           (slow modulation)
```

- Four oscillators, slightly detuned (creates chorus/beating)
- Mixed together
- Filter with slow LFO modulation (movement)
- Amp with slow LFO modulation (breathing)

Configuration:
| Cell | Value | Color | Notes |
|------|-------|-------|-------|
| W (1) | 100 | cyan (sine) | Base pitch |
| W (2) | 101 | cyan (sine) | +1 detune |
| W (3) | 99 | magenta (saw) | -1 detune, different timbre |
| W (4) | 100 | yellow (triangle) | Same pitch, different timbre |
| F | 180 | cyan (lowpass) | Cutoff |
| ~ (filter) | 250 | cyan (sine) | Very slow, subtle |
| ~ (amp) | 240 | cyan (sine) | Very slow, offset phase |

---

# Annex E: Module Quick Reference

```
SOURCES (generate signals)
  K  Knob        constant value
  W  Oscillator  audio-rate waveform
  ~  Function    rise/fall generator (LFO or envelope)

PROCESSORS (transform signals)
  F  Filter      frequency shaping
  A  Amp         amplitude control
  V  Vactrol     combined filter+amp (organic)
  S  Slew        signal smoothing
  G  Gate        threshold/comparator
  +  Mixer       sum inputs

IO
  O  Output      audio destination
  .  Port        board boundary

STRUCTURE
  B  Board       sub-patch container

COLORS (single-cell = variant)
  Cyan     sine / lowpass / param A
  Magenta  saw / highpass / param B
  Green    square / bandpass / param C
  Yellow   triangle / notch / param D
  White    default / output
  Red      input
```

---

# Annex F: Open Questions

1. **Global tempo**: Should there be a global BPM? How does it interact with `~`?

2. **Noise source**: Add `N` for white/pink noise? Currently approximated with high-freq oscillators.

3. **Sample and hold**: Needed for sequencing? Would be `H` module with signal + trigger inputs.

4. **Quantization**: Pitch quantization to scales? Could be a processor module.

5. **Polyphony**: Multiple voices? Currently monophonic by default.

6. **MIDI input**: External control? Outside current scope but future consideration.

7. **Visual feedback**: Oscilloscope view? Level meters? Signal flow animation?

8. **Preset management**: Save/load patches? Board library?
