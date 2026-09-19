# K2 developer guide

Standalone target for **Wildbits/K2 RevB0C (XC7A200T-FBG676-2)** with the
optical keyboard, ported from [C64MEGA65](https://github.com/MJoergen/C64MEGA65)
V5.2 and modelled on the [AExp-K2](https://github.com/mbrukner/AExp-K2) Amiga
port of the same board.

## Status

**Bring-up: M0 and M2 complete; the routed build closes timing.**

| Stage | Result |
|---|---|
| RTL elaboration | 0 errors, 0 critical warnings |
| Synthesis | 0 errors, 0 critical warnings |
| Routing | 54,902/54,902 nets routed, 0 routing errors |
| Setup | **WNS +0.593 ns**, 0 failing endpoints |
| Hold | WHS +0.010 ns, 0 failing endpoints |
| Pulse width | WPWS +0.251 ns, 0 failing endpoints |
| Bus skew | 0 violations |
| Constraints | every K2 constraint binds (checked in the **impl** log) |
| Sign-off checks | LED, LCD and RTC pass |
| Utilization | 30,619 LUTs (22.8%), 25,978 FFs (9.7%), 192/365 BRAM (52.6%), 73 DSPs |

**First hardware bring-up 2026-09-19.** The core configures and runs on a real
RevB0C board. Verified on hardware: `DONE` high, end-of-startup reached, all
PLLs locked, no CRC/IDCODE/bad-packet errors, DDR3 calibrated, and -- by JTAG
readback diffing -- QNICE executing, the SD card being read, the 6510 writing
C64 RAM, the 1541 running, ascal and the TMDS encoder clocked and moving data.
**No HDMI picture yet**, so M1 remains open; the same monitor, cable and input
display the AExp-K2 Amiga core at 720p50 correctly. See [DIAGNOSTICS.md](DIAGNOSTICS.md).

Critical path is now intra-`clk_pll_i` (MIG's 166.667 MHz ui_clk) at +0.593 ns;
`hr_clk` (100 MHz, 5,798 endpoints) sits at +1.525 ns.

### Why the memory path has two clock domains

The first routed build failed setup badly: WNS -1.485 ns over 144 endpoints, all
intra-clock in MIG's `ui_clk`, 84 of them inside `sw_cartridge_wrapper`. The
cause was that `framework_k2` tied the framework's `hr_clk` straight to `ui_clk`
at 166.667 MHz, as AExp-K2 does. On the MEGA65 `hr_clk` is the HyperRAM clock at
**100 MHz**, and everything upstream puts in that domain -- the ascal
framebuffer side of `av_pipeline`, plus whatever the core hangs off `hr_core_*`,
which for C64MEGA65 is the REU and the entire CRT cartridge pipeline -- was
written against a 10 ns budget. AExp only got away with 6 ns because its ADF
track engine was the sole core-side logic there.

So `hr_clk` now comes from `clk_m2m`'s 100 MHz `hr_clk_o`, the same MMCM output
the MEGA65 uses, and the crossing into `ui_clk` happens inside the memory path:

```
core / ascal / QNICE -> avm_arbit_general -> avm_fifo   | 100 MHz  (hr_clk)
                                             ==CDC==
                        k2_avm_increase -> avm_mig_bridge -> MIG | 166.667 MHz
```

The CDC sits on the **16-bit side**, before the width converter, because
`k2_avm_increase` and `avm_mig_bridge` are coupled by the read-credit loop
(7 credits, at most one read per 8 UI cycles); splitting that across a clock
domain crossing would break its latency contract. `avm_fifo` is built on
`xpm_fifo_axis`, so the crossing carries Xilinx's own CDC constraints, and it is
the same component C64MEGA65 already uses for the REU's `main_clk` crossing.

Cost: +165 LUTs, no extra BRAM. Consequence to remember: the Avalon side now
runs at 100 MHz rather than 166.667, so peak 16-bit transaction rate ahead of
the width converter is a third lower. Irrelevant for the scaler, but the REU and
CRT cacher are the latency-sensitive consumers, so **measure M6, do not assume**.

## Architecture

The target reuses C64MEGA65 and MiSTer2MEGA65 through a K2-specific board shell.
`CORE/` and `M2M/` are **unmodified upstream**: the K2 port needs no framework
patches, so the fork stays mergeable.

| Source | Responsibility |
|---|---|
| [k2_revb0c_top.vhd](vhdl/k2_revb0c_top.vhd), [k2_revb0c.xdc](constraints/k2_revb0c.xdc) | Board I/O and pin assignments |
| [k2_c64_system.vhd](vhdl/k2_c64_system.vhd), [framework_k2.vhd](vhdl/framework_k2.vhd) | Core/framework integration |
| [k2_avm_increase.vhd](vhdl/k2_avm_increase.vhd), [avm_mig_bridge.vhd](vhdl/avm_mig_bridge.vhd) | Avalon width conversion and DDR3 transactions |
| [k2_keyboard_matrix.vhd](vhdl/k2_keyboard_matrix.vhd), [k2_m2m_keyb.vhd](vhdl/k2_m2m_keyb.vhd) | Optical scan, RESTORE handling and keyboard delivery |
| [k2_codec_audio.vhd](vhdl/k2_codec_audio.vhd) | Codec initialization and audio output |
| [k2_status_leds.vhd](vhdl/k2_status_leds.vhd) | Keyboard PWR/MEDIA serial RGB LEDs |
| [k2_rtc.vhd](vhdl/k2_rtc.vhd) | Read-only physical BQ4802LY RTC and ticking fallback |
| [k2_lcd_splash.sv](rtl/k2_lcd_splash.sv) | Core identification and live FPGA temperature on the ST7789 LCD |

`framework_k2.vhd` is a fork of `M2M/vhdl/framework.vhd` that differs only in
four board-level hunks: the `G_MEM_CLK_SPEED` generic, the MEGA65 smart-keyboard
serial link replaced by an 80-bit logical-key bitmap (`key_state_n_i` +
`k2_m2m_keyb`), the HyperRAM PHY replaced by `k2_avm_increase` + `avm_mig_bridge`
onto the DDR3 MIG, and `hr_clk`/`hr_rst` taken from MIG's `ui_clk`. The core's
`hr_core_*` Avalon contract is unchanged, so C64MEGA65's REU and CRT cacher plug
in exactly as they do on HyperRAM.

The C64's RAM, ROMs and the simulated 1541 remain in BRAM. The 128 MiB DDR3
serves the HDMI scaler and the core's Avalon port; the 2 MiB asynchronous SRAM
is parked. MIG runs DDR-333 with a 166.667 MHz, 64-bit application port.

Board-specific details worth preserving:

- **HDMI only.** The K2 has no analog VGA output. `vga_*`/`vdac_*` are left
  open, and the menu's VGA / retro-15 kHz / CSYNC items drive nothing.
- **No IEC connector and no expansion port.** All `iec_*` and `cart_*` core
  ports are parked, so real 1541/SD2IEC drives and hardware cartridges are out
  of scope. Simulated drives and CRT/PRG files from SD are unaffected.
- **Optical keyboard:** the selected PA row is released; the other rows are
  grounded. PB high means pressed. Do not substitute mechanical polarity. The
  matrix already uses C64 cell numbering, so `CORE/vhdl/keyboard.vhd` needs no
  K2 variant. K2's four independent arrow keys override M2M slots 74/73/7/2.
- **RESTORE** at AA4 is an input with a key-down pulse, not an HDMI-enable
  output. A bare press goes to slot 75 (`m65_restore`) and therefore to the
  6510 NMI, so **RUN/STOP + RESTORE still performs the C64's own warm reset**.
  Holding **C=** (the `/F` logo key, slot 61) first redirects the same pulse to
  slot 67 and opens the OSM. The destination is latched at the leading edge, so
  releasing C= mid-press cannot redirect it. C= was chosen over the key AExp
  calls Fn because that keycap *is* RUN/STOP (slot 63) on this board; claiming
  it would have swallowed the warm-reset chord forever. `tb_k2_restore` guards
  all of this, including that neither RUN/STOP nor CTRL qualifies the chord.
- **Menu configuration:** [config_variant.tcl](scripts/config_variant.tcl)
  generates the K2-only menu labels from the canonical configuration. Welcome
  and help content lives in [help/](help/) (ASCII, at most 43 columns and 30
  rows per page — wider than AExp's, because the C64 core uses the 16x16 font).
  Edit those sources, not the ignored generated file.
- **Settings file** is `/c64/c64k2`, deliberately distinct from the MEGA65's
  `c64mega65`, so both can live on one card.
- **Built-in LCD:** currently a **placeholder** C64 screen generated by
  [generate_c64_logo.py](scripts/generate_c64_logo.py) with no SVG, Pillow or
  network dependency. It uses no BRAM, DDR3 or SRAM.

## Build and reports

Use Vivado 2026.1 on Linux and a C compiler, with Vivado's `settings64.sh`
sourced. From the checkout root:

```sh
vivado -mode batch -source K2/scripts/create_project.tcl
vivado -mode batch -source K2/scripts/build.tcl -tclargs impl
```

Create the project once per checkout. The synthesis hook rebuilds the QNICE
firmware and generates missing QNICE tools/monitor files. MIG source
configuration is tracked in [mig_a.prj](ip/DDR3_CTRL/mig_a.prj); generated IP
and all build products are ignored under `K2/build/`.

`create_project.tcl` symlinks `CORE`, `M2M` and `C64_MiSTerMEGA65` into
`K2/build/project/`, because `c1541_multi.sv` and `c1581_multi.sv` resolve
`../../C64_MiSTerMEGA65/rtl/iec_drive/*.mif.hex` from the synthesis run
directory. The OSM font resolves by a different route — `FONT_FILE`'s
`../font/...` is relative to `M2M/vhdl/`, the directory of the `tdp_ram.vhd`
that opens it — so it needs no link.

The bitstream is
`K2/build/project/C64-K2-B0C.runs/impl_1/k2_revb0c_top.bit`.
After each build, inspect `timing_routed.rpt`, `bus_skew_routed.rpt`,
`route_status.rpt` and `utilization_placed.rpt` in `K2/build/`.
Do not treat bitstream generation alone as a passing build. Grep every
synthesis log for "no pins matched": a missed XDC object silently no-ops
static timing analysis.

## Milestones

| # | Scope | Status |
|---|---|---|
| M0 | Repo, board shell, project creation, elaboration | Done |
| M1 | C64 BASIC boot on HDMI | **In progress** -- core runs on hardware, no HDMI output yet |
| M2 | Optical keyboard, RESTORE to the NMI, C= menu chord | Done |
| M3 | D64 / 1541 via vdrives and the file browser | Planned |
| M4 | PS/2 mouse as a 1351 (POT values, not quadrature) | Planned |
| M5 | Real LCD artwork, status LEDs, RTC, die temperature | Planned |
| M6 | REU and CRT cartridges over DDR3 | Deferred |

M6 is deferred on purpose: C64MEGA65 documents the REU and the simulated-
cartridge path as latency-sensitive against HyperRAM, and the K2's DDR3 bridge
has different latency characteristics (BL8, 7 read credits, at most one read
per 8 UI cycles).

## Installing the core

The K2 is not programmed over JTAG in normal use. The RP2040 on the board is an
FPGA boot supervisor (`Firmware/fpga-manager`): it picks a core for the context
selected by the physical DIP switches, programs the Artix, and then serves the
running K2 through a supervisor mailbox. Cores live either on the RP2040's own
SD card under `CNTX1/` .. `CNTX4/`, or in a per-context replaceable flash slot.
`k2coremgr.pgz`, run on the K2, browses, copies, installs and selects them.

The build produces both accepted forms in `K2/build/`:

```text
c64_k2.bin      9,730,652 bytes   raw bitstream
c64_k2.bin.gz   ~1.2 MB           gzip of the same image
```

Copy either into a `CNTX<n>/` directory on the RP2040 SD card, then set the DIP
switches to that context and restart. Or copy it to the K2's own SD card and use
`k2coremgr.pgz` to install it into the context's flash slot.

### Format requirements, and why COMPRESS must be FALSE

`fpga_mgr.cpp` defines `FPGA_SIZE` as **9730652** and rejects any image whose
decompressed length differs. So the core must be the **raw** configuration
bitstream -- no `.bit` ASCII header, no `write_cfgmem` flash padding -- and
`BITSTREAM.GENERAL.COMPRESS` **must be FALSE** in `k2_revb0c.xdc`. AExp-K2 sets
it TRUE, which yields a ~5.2 MB image that this loader will not boot. A `.gz` is
validated by gzip magic, method, reserved flag bits, CRC-32 and that same
decompressed size.

`K2/scripts/make_core.py` does the packaging and enforces all of it. It is pure
Python, so a core can be repackaged without Vivado:

```sh
python3 K2/scripts/make_core.py path/to/k2_revb0c_top.bit -o out/c64_k2.bin
```

It parses the `.bit` header, checks the size, checks that everything before the
bus-width detect pattern is `0xFF`, and checks that the sync word follows the
preamble. It deliberately does **not** pin absolute offsets: the leading dummy
run varies with the `BITSTREAM.CONFIG` SPI settings (our image has 288 bytes,
the reference K2 core has 32) and Vivado compensates with fewer trailing NOOP
words, so the total stays at `FPGA_SIZE` and no configuration data moves.

## Regression tests

Ported from AExp-K2 and retargeted. All of these pass today:

```sh
bash K2/scripts/test_keyboard.sh      # optical scan, RESTORE, menu + heap, help pages
bash K2/scripts/test_lcd.sh           # 240x280 pixel-exact SPI against the C64 asset
bash K2/scripts/test_status_leds.sh   # SK6812 GRB order, colors, priority, timing
bash K2/scripts/test_temperature.sh   # XADC decode, MIG coupling, LCD footer
bash K2/scripts/test_rtc.sh           # BQ4802LY timing, BCD, fallback, CDC
```

`tb_k2_menu` is worth singling out: it reads `OPTM_ITEMS`, the group array and
every welcome/help page through `work.config`'s real ROM port, then recomputes
the exact heap demand that `HELP_MENU` in `M2M/rom/options.asm` checks at
runtime. Current numbers: 98 rows, 1085-character item string, 5 submenus,
demand 1643 of `MENU_HEAP_SIZE` 1664 — **21 words of headroom**. Menu or
help-page growth therefore fails in simulation instead of as a QNICE FATAL on
hardware. This is also why the menu headline is the terse `" C64 for K2"`:
upstream's own headroom is only 17 words.

Run the memory-path test separately:

```sh
repo_dir=$(pwd) # checkout root
test_dir=$(mktemp -d /tmp/c64-k2-xsim.XXXXXX)
cd "$test_dir"
xvhdl --2008 \
  "$repo_dir/M2M/vhdl/axi_fifo_small.vhd" \
  "$repo_dir/K2/vhdl/k2_avm_increase.vhd" \
  "$repo_dir/K2/vhdl/avm_mig_bridge.vhd" \
  "$repo_dir/K2/test/tb_avm_mig_path.vhd"
xelab tb_avm_mig_path -s tb_avm_mig_path_sim
xsim tb_avm_mig_path_sim -runall
```

It covers unaligned bursts, byte enables, command/write backpressure and
back-to-back read responses with all seven credits occupied, and is
core-agnostic. Simulation does not validate physical DDR3 calibration.

Two AExp suites were **deleted rather than ported**, because they assert
against Minimig RTL and Amiga scancodes:

- `tb_k2_keymap` (raw Amiga scancodes out of `CORE/vhdl/keyboard.vhd`).
  C64MEGA65's `keyboard.vhd` drives the CIA-1 matrix instead, and the K2 matrix
  is already C64-numbered, so no K2 keymap variant exists to test.
- `test_ps2_mouse.sh`, `tb_k2_ps2_mouse.sv`, `tb_k2_keyboard_guard.sv` (Amiga
  quadrature mouse against Minimig `userio`/`ciaa`). M4 writes the 1351 suite.

## Not ported from AExp-K2

Deliberately left behind; the sources remain in the AExp-K2 checkout:

- `k2_debug_trace.vhd` and the SysInfo diagnostic capture build. The trace bus
  samples Amiga CPU/chipset state; repoint it at 6510/VIC state if wanted.
- `load_chunk.asm` / `firmware_variant.py` / `AEXP_K2_LOADER`. That
  sector-bounded FAT32 fast path existed because an 880 KiB ADF took 9.05 s to
  mount byte-at-a-time. D64 images are 174 KiB, so measure the stock loader
  first. The mechanism is generic, not Amiga-coupled, so reviving it is cheap.
- `mouse_kbd_mux.vhd`, which arbitrated Amiga quadrature mouse and keyboard
  events into Minimig.

## Board diagnostics

- FT4232 channel A is JTAG, useful for a volatile load during bring-up, but
  **not** how a core is normally installed -- see "Installing the core".
  Channel C (`...-if02-port0` in `/dev/serial/by-id/`): QNICE UART,
  115200 baud, 8-N-1, no flow control.
- `STAT_LED0`: DDR3 calibration complete. `STAT_LED1`: reset asserted.
- If a fatal error ends at `QMON>`, the Shell and on-screen menu are no longer
  running.
- A C64 BASIC READY screen confirms execution through the DDR3-backed scaler.
  The menu alone does not, because it is composited after scaling.
