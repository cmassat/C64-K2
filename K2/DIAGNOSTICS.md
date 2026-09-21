# K2 hardware diagnostics

How to see inside a running K2 when the screen tells you nothing, and what the
first hardware bring-up (2026-09-19) established.

## The board's two debug channels

The RevB0C carries an FT4232H that enumerates as
`Xilinx New Retro Computer`, serial `138SA20405`, four interfaces:

| Interface | Device | Use |
|---|---|---|
| `-if00` | `/dev/ttyUSB0` | JTAG (Vivado hardware manager) |
| `-if02` | `/dev/ttyUSB2` | QNICE console UART, 115200 8N1 |

The FTDI is powered by the board, so it only enumerates when the K2 is on.
Plug it straight into the host: a hub dropping out takes the JTAG link with it.

### The console UART is silent by design

`framework_k2.vhd` leaves the QNICE console on this UART, and
`M2M/vhdl/QNICE/qnice.vhd` hardcodes the switch register to zero
(`STDIN=STDOUT=UART`). Nevertheless **expect no output**: `M2M/rom/shell.asm`
contains zero `IO$PUTS` calls, and `START_FIRMWARE` branches straight to
`START_SHELL`, bypassing `QMON$COLDSTART` and its banner. The only console
write in the firmware is the JiffyDOS fallback warning in
`CORE/m2m-rom/m2m-rom.asm`. Silence on this port proves nothing.

## Configuration status over JTAG

The K2 does not route the FPGA `DONE` pin to the RP2040, so the supervisor
infers success from `INIT_B` alone. JTAG sees the real thing:

```tcl
open_hw_manager
connect_hw_server -quiet
open_hw_target -quiet [lindex [get_hw_targets] 0]
set d [lindex [get_hw_devices] 0]
current_hw_device $d
refresh_hw_device -update_hw_probes false $d
report_property $d          ;# REGISTER.CONFIG_STATUS.* and REGISTER.BOOT_STATUS.*
```

A healthy configured board reads `DONE_PIN=1`, `END_OF_STARTUP=1`,
`PLL_LOCK_STATUS=1`, `GTS_CFG_B`/`GWE`/`GHIGH` all 1, `MODE_PIN M[2:0]=110`
(slave SelectMAP), `CFG_BUS_WIDTH_DETECTION=01` (x8), and zero in
`CRC_ERROR`, `IDCODE_ERROR`, `BAD_PACKET_ERROR` and the over-temp alarm.

## Readback diffing: which logic is actually running

7-series readback exposes **memory contents** (BRAM, LUTRAM, SRL) but not
flip-flop state -- `readback_hw_device -capture` is UltraScale only. That is
still enough to tell which modules are executing, because anything with RAM
changes as it runs.

```tcl
readback_hw_device -force -bin_file s1.bin $d
after 5000
readback_hw_device -force -bin_file s2.bin $d
```

Diff the two, then map differing bytes to nets with a logic-location file
generated from the *same* routed checkpoint:

```tcl
open_checkpoint .../k2_revb0c_top_routed.dcp
write_bitstream -force -logic_location_file probe.bit    ;# writes probe.ll
```

`.ll` lines read `Bit <offset> <frame> <frameoffset> Block=<site> [Net=...]`;
`<offset>` is a **bit** index, so `offset/8` is the byte in the readback.
BRAM entries carry only `Block=`/`Ram=`, so resolve sites to instances with
`get_cells -of_objects [get_sites RAMB36_XnYn]` on the routed checkpoint.

To identify which design is loaded, compare the readback against a bitstream's
FDRI payload at **offset 404** -- the readback carries one leading pad frame
(a 7-series frame is 101 words = 404 bytes). A match around 99% is the same
design; different designs sit near 78%.

## What bring-up established (2026-09-19)

Working, proven directly on hardware:

- configuration is clean (status register as above);
- DDR3 calibrates -- the LCD's temperature digits are gated on
  `mem_calib_done` via `k2_temperature_source.vhd`, and `STAT_LED0` (pin U16)
  is wired straight to it;
- QNICE executes (`QNICE_SOC/cpu/Registers/*` changing) and reads the SD card
  (`QNICE_SOC/sd_card/buffer_ram` changing);
- the 6510 runs (`i_core/c64_ram/i_tdp_ram`), as do the 1541 and the C64 ROMs;
- ascal, the OSM overlay and `i_vga_to_hdmi` are clocked and moving data;
- the 100 MHz `hr_clk` -> `ui_clk` CDC passes traffic
  (`i_mem_cdc/i_axi_fifo_wr/...xpm_fifo_axis`);
- the HDMI pixel-clock MMCM (`MMCME2_ADV_X1Y0`) reconfigures once at boot and
  then holds -- across four snapshots its config bits changed `[7, 0, 0]`, so
  it is not stuck in a DRP loop.

Not working: **no HDMI picture**. The same monitor, cable and input display the
AExp-K2 Amiga core at 720p50, and the HDMI clocking path
(`video_mode` table, `qnice_clk_sel <= video_mode.CLK_SEL`, the
`video_out_clock` instantiation and its pin constraints) is byte-for-byte
identical to that working port. Removing the SD card changes nothing.

## Bitstream preamble: a false lead, and how it fooled us

**This section previously claimed the preamble was load-bearing. It is not.**
Kept as a worked example of a confounded measurement.

On 2026-09-19, rebuilding the routed checkpoint with
`BITSTREAM.CONFIG.SPI_32BIT_ADDR NO` moved the preamble from offset 288 to 32,
matching the vendor cores' first 48 bytes. That image appeared not to configure
the board, while the offset-288 image appeared to work -- so the setting was
pinned to `YES` with a "do not fix this toward vendor convention" warning.

The test was worthless. It was run on a day when the core showed a **black
screen from any image**, so "did not configure" and "configured fine and
displayed nothing" produced identical evidence. The only instrument that could
have told them apart is JTAG `CONFIG_STATUS`, and it was not used.

Re-tested 2026-09-21, once the read-guard fix gave a picture: the `NO` variant
**boots from the RP2040 SD card and runs**. It is now the default.

Diffing the two images settles why. Exactly **one byte** of the configuration
payload differs:

```
NO : ... 3003e001 0000026b ...
YES: ... 3003e001 0000026c ...
```

`0x3003E001` is a Type-1 write to the **BSPI** register; `0x6B` / `0x6C` are
the SPI flash read opcodes *Quad Output Fast Read* with a 3- or 4-byte address.
The FDRI payload is byte-identical (sha256 `78580b5198f2a3c2`); the rest is 256
bytes of leading `0xFF` traded against 256 trailing NOOPs, since Vivado holds
the total at `FPGA_SIZE`.

BSPI is only consulted in **master SPI boot**, where the FPGA fetches its own
bitstream from flash. This board configures in **slave SelectMAP x8** with the
RP2040 clocking bytes in, so that register is never read. There was never a
plausible mechanism.

**The lesson:** before trusting a "hardware-verified" claim, check what
instrument produced it and whether the system was healthy enough for the
measurement to mean anything. A negative result taken while something else is
broken is not a result.

## Instrumented build

`framework_k2.vhd` can host ILAs directly, because the core's video output and
the pipeline's measured parameters are both in scope there:

- `video_clk_i` domain: `video_ce_i`, `video_hs_i`, `video_vs_i`,
  `video_hblank_i`, `video_vblank_i`, `video_red_i`/`green`/`blue_i`;
- `qnice_clk` domain: `qnice_h_pixels`, `qnice_v_pixels`, `qnice_h_freq`,
  `qnice_hdmax`, `qnice_vdmax`.

Create the cores with `create_ip -name ila`, declare them as components before
the architecture's `begin`, and instantiate before `end architecture`. This is
a throwaway build: restore `framework_k2.vhd` before committing.

## Rewiring ILA probes without re-synthesising (2026-09-21)

Synthesis of this design takes ~6 minutes, and the BASIC licence allows exactly
one ILA with at most five probes. Chasing a signal by editing `framework_k2.vhd`
and rebuilding therefore costs a full build per hypothesis.

It is much cheaper to build the ILA **once** with generously sized probes, then
re-point those probes at different nets on the *routed checkpoint*:

```tcl
open_checkpoint K2/build/pc_probe_routed.dcp
# for each probe pin: clear DONT_TOUCH on the old net, disconnect, reconnect
set_property DONT_TOUCH false $old_net
disconnect_net -net $old_net -objects $pin
connect_net -hierarchical -net $net -objects $pin
route_design -directive Quick
write_checkpoint -force .../probe_routed.dcp
write_debug_probes -force .../probe.ltx
write_bitstream -force .../probe.bit
```

That is a ~2 minute turnaround instead of ~20. `K2/build/rewire_*.tcl` are the
working examples; the base ILA is `i_system/i_ila_control` with probe widths
5/8/8/8/4 (five probes, the licence maximum). Two rules matter: `get_nets` must
resolve to exactly one object, so check `llength` and fail loudly; and the old
net's `DONT_TOUCH` has to be cleared or `disconnect_net` refuses.

These are throwaway checkpoints. Nothing under `K2/build/` is committed.

## The black screen is a stalled scaler read path (2026-09-21)

Probing ascal's Avalon and output-side handshakes settled the question the
2026-09-19 captures left open. Measured over 16384 samples:

| Signal | Result | Meaning |
|---|---|---|
| `avl_write_i`, avalon FSM | toggling, `idle_st` <-> `writing_st` | ascal **writes** the C64 frame into DDR3 normally |
| `o_readlev` | **stuck at 2** | ascal has two read bursts outstanding -- its maximum |
| `hr_dig_read`, `hr_wide_read` | stuck 0 | so it issues no further reads |
| `hr_dig_readdatavalid`, `hr_wide_readdatavalid` | **stuck 0 for all 16384 samples** | **the read data never comes back** |
| `avl_read_sync`/`_sync2` = 1/1, `avl_read_pulse` | 0 | request toggle already delivered |
| `o_readack_sync`/`_sync2` = 1/1, `o_readack` | 0 | ack toggle already consumed |
| `o_readdataack_sync`/`_sync2` = 1/1 | 0 | no data ack pending |

So the write path works, the read requests were issued and accepted, and the
responses never returned. ascal's output FSM waits on `o_readlev` forever, emits
no pixels, and the screen stays black. Every CDC toggle pair is in its settled
state, so this is not a lost-pulse CDC bug.

### Root cause: the arbiter cannot track a read across a command FIFO

`M2M/vhdl/memory/avm_arbit.vhd` routes read responses by a single `last_grant`
bit, with no per-transaction owner:

```vhdl
s0_avm_readdatavalid_o <= m_avm_readdatavalid_i when last_grant = '0' else '0';
s1_avm_readdatavalid_o <= m_avm_readdatavalid_i when last_grant = '1' else '0';
```

and its `burstcount` bookkeeping has a second-order flaw: the write branch is
guarded by `burstcount = 0`, so a write accepted *while a read is pending* falls
through to the `else` branch and **decrements the pending read's burstcount**.
That makes `s0_last` fire early, the grant switch, and `last_grant` flip --
after which the remaining read words are delivered to the other master.

Upstream never hits this because the MEGA65's HyperRAM is a **blocking**
interface: `m_avm_waitrequest_i` stays high for the whole transaction, so no new
command can be accepted while a read is in flight. Putting `avm_fifo` (the CDC)
in front of the arbiter breaks that contract -- waitrequest drops as soon as the
command is *enqueued*, not when it completes.

`avm_arbit_general` is a tree of three `avm_arbit` instances, so the flaw is
present at every level of the tree.

### The fix, and its status

`K2/vhdl/k2_avm_read_guard.vhd` sits between `avm_arbit_general` and `avm_fifo`
and holds `waitrequest` high until every word of an accepted read has returned,
restoring the blocking contract. Because the guard drives the *top* arbiter's
`m_avm_waitrequest_i`, and each `avm_arbit` computes
`s_avm_waitrequest_o <= m_avm_waitrequest_i or not grant`, the freeze propagates
down the whole tree.

`bash K2/scripts/test_memory_order.sh` reproduces the misrouted read word
without the guard (`owner=3, incorrectly to competitor=1`) and passes with it,
plus a unit test covering 1/64/128/255-word bursts, gapped responses,
downstream backpressure and reset.

Serialising reads is not a regression against upstream: the HyperRAM the
framework was written for is fully blocking too, and DDR3 is the faster part.

**Status: confirmed on hardware 2026-09-21.** The guarded build closes timing
(WNS +0.523 ns, WHS +0.041 ns, WPWS +0.251 ns, zero failing endpoints, zero bus
skew violations), and once programmed over JTAG the board produces a picture.

Getting here took two wrong turns worth remembering: enlarging the CDC read FIFO
from 16 to 128 words was *necessary but not sufficient*, and the 09-19 captures
were read as "the 6510 is not running" when the CPU was fine all along -- the
frame was being written to DDR3 correctly and simply never read back. When the
write path works and the read path does not, suspect the transport, not the
producer.
