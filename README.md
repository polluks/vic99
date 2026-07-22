# VIC-99: TI-99/4A Boot Screen for VIC-20

Recreates the TI-99/4A startup screen on a VIC-20 (3.5K unexpanded, no expansion RAM) using cc65 assembler.

## Features

- **VIA stable raster rainbow stripes** using Marko Makela's auxiliary timer technique
- **Two screens**: title screen with stripes, then "TI-99/4A BASIC" ready prompt
- **Beep** at startup and screen transition
- **TI-99/4A GROM 0 font** (authentic character set with small caps)

## Build

```
make          # assemble + link -> vic99.prg
make run      # build + launch in VICE
make clean    # remove build artifacts
```

Requires: `ca65`, `ld65` (cc65 toolchain), VICE (`x64`)

## Hardware

- **Target**: VIC-20 with 3.5K RAM (unexpanded)
- **Stable raster**: Both VIAs in free-run mode (`$40` to ACR)
  - VIA2 (`$9120`) = IRQ timer, VIA1 (`$9110`) = auxiliary reference timer
  - `TIMER_VAL = 312 * 71 - 2 = 22150` (PAL timing)
- **Screen RAM**: `$1E00`
- **Border/bg color**: `$900F`
- **Character set**: `$1C00` (TI-99/4A GROM 0 font, selected via `$9005` bits 0-2 = `%101`)

## References

- [Marko Makela's stable raster technique](https://www.antimon.org/dl/c64/code/stable.txt)
- [JonVogel/TI_Font](https://github.com/JonVogel/TI_Font) - TI-99/4A bitmap font data
