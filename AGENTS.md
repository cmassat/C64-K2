# C64-K2 — Commodore 64 for Wildbits/K2

## Fork context

This checkout is a K2 port of **C64MEGA65 V5.2**
(`https://github.com/MJoergen/C64MEGA65`, remote `upstream`, push disabled).
The active branch is `k2`; `master` mirrors upstream. Read `K2/README.md`
before working on anything under `K2/`.

The port is modelled on **AExp-K2** (`/home/bill/Development/artix7/AExp-K2`),
an Amiga 500 core for the same board. That checkout is the source of truth for
every board-level decision and carries much deeper board documentation
(`K2/KEYBOARD.md`, `K2/RTC.md`, `K2/TEMPERATURE.md`, `K2/SD_LOADING.md`,
`K2/DIAGNOSTICS.md`). Consult it before re-deriving anything.

Vivado 2026.1 is at `/mnt/e/2026.1/Vivado`. On this Fedora host it needs an
ncurses-5 shim (`libncurses.so.5` -> `.so.6`) on `LD_LIBRARY_PATH`, or
`ncurses-compat-libs` installed.

**Status: M0 and M2 complete (2026-09-18); the routed build closes timing.**
Setup +0.593 ns, hold +0.010 ns, pulse width +0.251 ns, zero failing endpoints,
zero routing errors, zero bus-skew violations, every K2 constraint binding.
30,619 LUTs, 192/365 BRAM tiles. **Never run on hardware.**

## The emulated machine

PAL C64, unmodified C64MEGA65 V5.2 core: 6510, VIC-II, switchable 6581/8580
SID (incl. dual SID), switchable 6526/8521 CIA, one simulated C1541 reading and
writing D64 images. Simulated CRT cartridges and PRG loading from SD.

Not available on this board: hardware cartridges (no expansion port), real
IEC devices (no connector), analog VGA and retro 15 kHz (HDMI only).

## Repository map

- `CORE/`, `M2M/` — **unmodified upstream.** The K2 port required no framework
  patches; keep it that way so the fork stays mergeable. `CORE/C64_MiSTerMEGA65`
  and `M2M/QNICE` are submodules.
- `K2/` — the entire port. `vhdl/`, `rtl/`, `constraints/`, `scripts/`, `test/`,
  `help/`, `assets/`, `ip/`. Build products live in the ignored `K2/build/`.
- `lib/font5x7/` — reusable Wildbits 5x7 font, copied from AExp-K2.

## Hard rules

1. **Do not modify `CORE/` or `M2M/`.** Board differences belong in
   `K2/vhdl/framework_k2.vhd` (a fork of `M2M/vhdl/framework.vhd`) and
   `K2/vhdl/k2_c64_system.vhd` (the K2 analogue of `M2M/vhdl/top_mega65-r6.vhd`).
   The one sanctioned exception is `CORE/vhdl/config.vhd`, which is never
   edited but *rewritten at build time* into `K2/build/generated/config.vhd`
   by `K2/scripts/config_variant.tcl`.
2. **Grep the IMPLEMENTATION log for "no pins matched", not just synthesis.**
   The first constraint read happens with unresolved black boxes, so Vivado
   defers the failures; they surface in `impl_1/runme.log`. Two dead ascal
   constraints hid in exactly that gap. A missed XDC object
   silently no-ops static timing analysis. The core clock constraints
   (`k2_revb0c.xdc`: `set_case_analysis 0` on
   `i_system/i_core/hr_core_speed_reg[0]/Q` and `main_clk` generated from
   `i_system/i_core/clk_gen/i_clk_c64_orig/CLKOUT0`) name leaf registers inside
   `CORE/vhdl/mega65.vhd` and `CORE/vhdl/clk.vhd` and are load-bearing. Note the
   polarity is the opposite of AExp-K2's: here core_speed 0 is the *fast* leg.
3. **Never leave a dangling XDC constraint.** If a module is deferred, comment
   its constraints out with a pointer to the milestone, and remove the matching
   `check_*.tcl` call from `build.tcl`. (Done for PS/2 until M4.)
4. **Bitstream generation alone is not a passing build.** `build.tcl` gates on
   setup/hold slack and bus skew; keep those gates. It wraps the whole build in
   a `catch` and calls `exit 1`, because Vivado's batch mode otherwise exits 0
   even when a sourced script raises -- a failing gate used to look like a pass
   to any caller that checked only the exit code.
5. **`C64MEGA65`'s relative ROM paths are load-bearing.** `c1541_multi.sv` and
   `c1581_multi.sv` open `../../C64_MiSTerMEGA65/rtl/iec_drive/*.mif.hex` from
   the synthesis run directory, which is why `create_project.tcl` symlinks the
   submodule into `K2/build/project/`. `FONT_FILE` resolves differently — its
   `../font/...` is relative to `M2M/vhdl/`, the directory of the `tdp_ram.vhd`
   that opens it.
6. **Every OSM growth needs a QNICE heap rebudget.** `OPTM_SIZE` is not only
   the settings-file length; `HELP_MENU` in `M2M/rom/options.asm` sizes
   `MENU_HEAP_SIZE` and `OPTM_HEAP` from it. AExp-K2's `AGENTS.md` rule 11 has
   the exact demand formula and applies verbatim.
7. If `OPTM_SIZE` changes, regenerate the settings file
   (`M2M/tools/make_config.sh c64k2 auto`) — `CFG_FILE` is `/c64/c64k2`.

## Architecture cheat sheet

- **Clocks.** `k2_clock_gen.vhd` turns the board's 40 MHz oscillator into
  100 MHz (system), 333.333 MHz (MIG sys) and 200 MHz (MIG IODELAY).
  `CORE/vhdl/clk.vhd` takes the 100 MHz and makes the C64 clock: `i_clk_c64_orig`
  = 31.5278 MHz (50.124 Hz) and `i_clk_c64_slow` = 31.4490 MHz (49.999 Hz,
  HDMI flicker-free), selected by a `BUFGMUX_CTRL`.
- **Memory: two clock domains, and the split is load-bearing.**
  `hr_core_*` Avalon (16-bit) → `avm_arbit_general` → `avm_fifo` **at 100 MHz**
  (`clk_m2m`'s `hr_clk_o`, the MEGA65's HyperRAM clock) ==CDC==>
  `k2_avm_increase` (16→128 bit) → `avm_mig_bridge` → DDR3 **at MIG's
  166.667 MHz `ui_clk`**. `hr_count_long/short` are tied to zero.
  Do NOT collapse this back onto `ui_clk` the way AExp-K2 does: upstream wrote
  the `hr_clk` domain against 10 ns, and at 6 ns it misses setup by 1.485 ns
  (84 endpoints in `sw_cartridge_wrapper` alone). The CDC must stay on the
  16-bit side, because `k2_avm_increase` and `avm_mig_bridge` are coupled by a
  read-credit loop that must not cross clock domains.
- **Keyboard.** `k2_keyboard_matrix` scans the optical matrix and publishes an
  80-bit low-active M2M logical-key bitmap; `k2_m2m_keyb` turns that into
  `(key_num, pressed_n)` plus `qnice_keys_n`. The matrix is already
  C64-numbered, so `CORE/vhdl/keyboard.vhd` is untouched.
  The RESTORE pin carries a key-down pulse only; it is stretched to 100 ms and
  routed to **slot 75** (the 6510 NMI) on its own, or to **slot 67** (open the
  OSM) when **C=** (slot 61) is already held, latched at the leading edge.
  Do not move the chord onto RUN/STOP: that keycap is slot 63, and
  RUN/STOP + RESTORE is the C64's own warm reset. `tb_k2_restore` asserts this.
- **Video.** The whole M2M `av_pipeline`/ascal chain is instantiated unmodified
  inside `framework_k2`; only HDMI is physically wired.

## Installing a core (NOT JTAG)

The RP2040 FPGA manager programs the Artix from `CNTX1..CNTX4/<name>.bin|.gz`
on its own SD card, or from a per-context replaceable flash slot managed by
`k2coremgr.pgz`. `fpga_mgr.cpp` enforces `FPGA_SIZE` = **9730652** bytes on the
decompressed image, so:

- `BITSTREAM.GENERAL.COMPRESS` **must stay FALSE** in `k2_revb0c.xdc`
  (AExp-K2 sets it TRUE; that image is ~5.2 MB and gets rejected);
- the image is the RAW bitstream, not a `.bit` and not `write_cfgmem` output;
- `K2/scripts/make_core.py` packages and validates it, and `build.tcl` runs it
  after the timing gates. It is pure Python -- no Vivado needed to repackage.

Reference material lives outside this repo at
`/mnt/Retro/WildBits/Firmware/fpga-manager` (`README.md`, `fpga_mgr.cpp`,
`k2/README.md`), and `/home/bill/CFP95600C.bin` is a known-good context-1 core
to compare against.

## Build and verification

```sh
source /mnt/e/2026.1/Vivado/settings64.sh
vivado -mode batch -source K2/scripts/create_project.tcl   # once per checkout
vivado -mode batch -source K2/scripts/build.tcl -tclargs impl
```

Cheap pre-Vivado check: `xvhdl --2008` the K2 sources (packages first:
`M2M/QNICE/vhdl/tools.vhd`, `M2M/vhdl/controllers/HDMI/types_pkg.vhd`,
`M2M/vhdl/av_pipeline/video_modes_pkg.vhd`).

Full elaboration gate, run from inside the synthesis run directory so the
relative ROM paths resolve:

```sh
cd K2/build/project/C64-K2-B0C.runs/synth_1
vivado -mode batch -source <(echo '
open_project ../../C64-K2-B0C.xpr
update_compile_order -fileset sources_1
synth_design -rtl -name rtl_check -top k2_revb0c_top')
```

## People

Bill Massat maintains this fork. MJoergen and sy2002 are the C64MEGA65
authors; sy2002 also wrote the M2M framework. Matthias Brukner wrote AExp-K2,
from which this port's board shell is derived.
