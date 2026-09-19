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

## Bitstream preamble is load-bearing

Rebuilding the routed checkpoint with `BITSTREAM.CONFIG.SPI_32BIT_ADDR NO`
moves the preamble from offset 288 to 32 and makes the first 48 bytes identical
to the vendor cores. **That image does not configure the board**; the
offset-288 image does. Their FDRI payloads are byte-identical, so only the
preamble differs. See the comment at `K2/constraints/k2_revb0c.xdc`.

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
