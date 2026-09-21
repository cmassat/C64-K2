# Session handoff -- 2026-09-21

Working state, not reference material. Delete once M1 closes.
Settled findings live in [DIAGNOSTICS.md](DIAGNOSTICS.md) and
[README.md](README.md); this file is only "where we stopped".

## One-line status

**The black screen is fixed.** The core boots from the SD card and displays.
M1's remaining work is hardware validation of input and file loading.

## What changed

The fault was never video or clocking. `avm_arbit` routes read responses by a
single `last_grant` bit and assumes a *blocking* memory; the CDC FIFO this port
needs between the 100 MHz Avalon domain and MIG's 166.667 MHz `ui_clk` is not
blocking. Read data was being delivered to the wrong master, so ascal wrote
every frame into DDR3 and never got one back.

`K2/vhdl/k2_avm_read_guard.vhd` restores the blocking contract. Full write-up
in DIAGNOSTICS.md; the reasoning, including the wrong turn that cost a day, is
in `/home/bill/Development/artix7/docs/black-screen-fix.md`.

Also settled: the 09-19 claim that `SPI_32BIT_ADDR` must stay `YES` was a
confounded measurement. The vendor-convention `NO` variant boots from SD, and
is now the default, so `build.tcl` emits vendor-format images directly.

## Verified on hardware 2026-09-21

- guarded build passes every gate: WNS +0.523 ns, WHS +0.041 ns, WPWS
  +0.251 ns, zero failing endpoints, zero bus-skew violations, zero route
  errors;
- programmed over JTAG -- picture;
- **booted from the RP2040 SD card (`CNTX1`) -- picture.** This is the real
  install path, not JTAG.

## SD card, as left

`/run/media/bill/30A9-815D` when mounted:

| Context | Core |
|---|---|
| `CNTX1` | **this C64 core** (9,730,652 B, sha256 `fcdf93ab...`) |
| `CNTX2` | Amiga (AExp-K2) |
| `CNTX3` | 6809 |
| `CNTX4` | native F256K2 |

These are all still on the **obsolete** hard-coded filenames (`CFP95600C.bin`
and friends), which is a local habit, not the convention. Anything published
must be named `Wildbits*.gz` -- see `K2/release/README.md`. Dropping a
`Wildbits*.gz` into a context takes precedence over the legacy name, so the old
file can stay put as a fallback.

A pristine copy of the original `CNTX1` image is at
`~/Development/Wildbits/Firmware/CNTX1/CFP95600C.bin`. Three other contexts
still hold known-good cores, and golden recovery (hold RESET through a restart)
works regardless.

## Uncommitted

Nothing is committed yet. **Do not `git checkout` `framework_k2.vhd`** -- unlike
the previous session, its diff is now the fix itself, not ILA scaffolding.

- new: `K2/vhdl/k2_avm_read_guard.vhd`
- new: `K2/test/tb_k2_avm_read_order.vhd`, `K2/test/tb_k2_avm_read_guard.vhd`
- new: `K2/scripts/test_memory_order.sh`
- modified: `K2/vhdl/framework_k2.vhd` (guard instantiated, read FIFO 16 -> 128)
- modified: `K2/scripts/build.tcl`, `K2/scripts/create_project.tcl`
- modified: `K2/constraints/k2_revb0c.xdc` (SPI_32BIT_ADDR -> NO)
- modified: `K2/README.md`, `K2/DIAGNOSTICS.md`, `AGENTS.md`
- new, outside the repo: `/home/bill/Development/artix7/docs/`

## Next steps

1. Commit the above as one change.
2. The hardware validation that has been blocked since bring-up:
   keyboard, **C= + RESTORE** menu chord, **RUN/STOP + RESTORE** warm reset,
   D64 loading from `/c64/games/`, Kernal -> JiffyDOS, settings persistence
   across a power cycle.
3. Close M1; then M3, M5, M4. M6 stays deferred -- and when it lands, measure
   REU and CRT-cacher latency, because the read guard serialises reads.

## Still worth knowing

- **Vivado BASIC licence:** exactly one ILA, max 5 probes.
- **Probe rewiring beats rebuilding.** Re-point ILA probes on a routed
  checkpoint and `route_design -directive Quick`: ~2 min per hypothesis instead
  of ~20. See DIAGNOSTICS.md; working examples in `K2/build/rewire_*.tcl`.
- **The FTDI is powered by the K2**, so it only enumerates when the board is on.
  Plug it straight into the host, not through a hub.
- Synthesis ~6 min; a full build is well under an hour.
