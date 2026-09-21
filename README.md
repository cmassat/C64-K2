Commodore 64 for Wildbits
=========================

A [Commodore 64](https://en.wikipedia.org/wiki/Commodore_64) core for the
**Wildbits K2 / Foenix F256K2** (RevB0C, XC7A200T).

Experience a PAL C64 with great accuracy and sublime compatibility on your K2:
a cycle-level 6510, VIC-II, switchable 6581/8580 SID including dual SID,
switchable 6526/8521 CIA, and a simulated C1541 that reads and writes D64
images.

![Commodore64](doc/c64.jpg)

Status
------

The core **runs on hardware and outputs HDMI**. It configures cleanly, DDR3
calibrates, the SD card is read, and the C64 boots.

| Area | State |
|---|---|
| HDMI video, DDR3, SD card | Working on hardware |
| Optical keyboard, RESTORE to NMI, `C=` menu chord | Implemented, hardware validation in progress |
| D64 / 1541 through the file browser | Planned |
| PS/2 mouse as a 1351 | Planned |
| LCD artwork, status LEDs, RTC, die temperature | Planned |
| REU and simulated cartridges over DDR3 | Deferred |

The full milestone table is in [K2/README.md](K2/README.md).

Installation
------------

Download the newest core from
[Releases](https://github.com/cmassat/C64-K2/releases) and copy **one** file
into a context directory on the FPGA manager's SD card:

```
CNTX1/WildbitsC64-K2-<date>.bin.gz
```

Any of `CNTX1`..`CNTX4` works — that is simply which slot you select at
power-on.

**Keep the `Wildbits` prefix.** It is how the loader finds the file: for each
context it scans for `Wildbits*.gz`, then `Wildbits*.bin`. A file named
anything else is never discovered, and the machine sits at a black screen
doing nothing. When a core *is* found it loads in about a second and the
machine reboots into it — that reboot is the signal to look for.

Older FPGA managers do not scan for `Wildbits*` at all and only accept one
fixed filename per context. If your core never loads, update the
[FPGA manager](https://github.com/wildbitscomputing/fpga-manager), or see
[K2/release/README.md](K2/release/README.md) for the legacy names.

If something goes wrong, hold **RESET** through a restart for golden recovery.

SD cards
--------

There are **two different cards**, and it is easy to confuse them:

| Card | Holds |
|---|---|
| The FPGA manager's card (inside, on the RP2040) | The cores themselves, in `CNTX1`..`CNTX4` — see Installation above |
| The K2's own card (bottom or back slot) | Disk images, ROMs and your settings |

The K2's card should be **FAT32**. The core's file browser starts in `/c64`,
so put your content there:

```
/c64/
    c64k2           <- settings file, exactly 98 bytes (see below)
    games/          <- your own layout; the browser walks subdirectories
    demos/
    prg/
    jd-c64.bin      <- optional JiffyDOS ROMs, 16,384 bytes each
    jd-c1541.bin
```

The subdirectory names are entirely up to you — only `/c64` itself matters.

### The settings file is not optional

**Settings are only saved if `/c64/c64k2` already exists and is exactly 98
bytes.** If the file is missing or the wrong size, the core silently discards
your settings on every power cycle, with no error.

A ready-made one is attached to each release — just copy it to `/c64/c64k2`.
A file of `0xFF` bytes means "use defaults", so a fresh copy starts clean.

If you ever need to regenerate it:

```sh
cd M2M/tools && ./make_config.sh c64k2 auto
```

That size is tied to the number of menu entries, so it changes if the menu
changes. A release's file always matches that release's core.

### JiffyDOS

JiffyDOS ROMs are not included — they are commercial. If you own them, put
`jd-c64.bin` and `jd-c1541.bin` (16,384 bytes each) anywhere under `/c64` and
load them from the menu.

Using the core
--------------

**Hold `C=` (the Commodore key) and press `RESTORE` to open the on-screen
menu.** The same chord closes it, and your settings are saved when it closes.

The menu deliberately uses `C=` so the RESTORE key keeps its original C64
behaviour:

| Keys | Action |
|---|---|
| `C=` + `RESTORE` | Open / close the menu |
| `RESTORE` alone | C64 NMI, exactly as on real hardware |
| `RUN/STOP` + `RESTORE` | Warm reset |
| Board reset button | Full reset |

In the menu, the top-left arrow key leaves a sub-menu.

When browsing for D64, CRT or PRG files:

| Keys | Action |
|---|---|
| Cursor up / down | File up / down |
| Cursor left / right | Page up / down |
| `Enter` | Mount disk, or load CRT / PRG |
| `Space` | Unmount drive |
| `F1` / `F3` | Bottom SD card / back SD card |
| Top-left arrow | Cancel browsing |

The K2 has four independent cursor keys, so no shifting is needed to move up
or left.

More help is built into the core itself, on the menu's help screens.

Not available on this board
---------------------------

- **Hardware cartridges** — there is no expansion port. Cartridges are
  simulated from `.crt` files on the SD card instead.
- **Real IEC devices** — there is no IEC connector.
- **Analog VGA and retro 15 kHz output** — HDMI only.

Documentation
-------------

| Document | Contents |
|---|---|
| [K2/README.md](K2/README.md) | The port: architecture, milestones, build and test |
| [K2/DIAGNOSTICS.md](K2/DIAGNOSTICS.md) | Seeing inside a running K2 when the screen tells you nothing |
| [K2/release/README.md](K2/release/README.md) | Release notes and install detail |
| [AGENTS.md](AGENTS.md) | Working rules for this fork |
| [doc/README-C64MEGA65.md](doc/README-C64MEGA65.md) | The upstream user's manual. Much of it — SID behaviour, disk handling, compatibility — still applies; the hardware and installation chapters do not. |

Building
--------

```sh
git clone --recurse-submodules https://github.com/cmassat/C64-K2.git
source /path/to/Vivado/settings64.sh
vivado -mode batch -source K2/scripts/create_project.tcl
vivado -mode batch -source K2/scripts/build.tcl -tclargs impl
```

The submodules are not optional — the tree does not build without them.

Credits
-------

This core is based on the
[MiSTer](https://github.com/MiSTer-devel/C64_MiSTer) Commodore 64 core, which
itself builds on the work of [many others](AUTHORS).

[MJoergen](https://github.com/MJoergen) and [sy2002](http://www.sy2002.de)
created [C64MEGA65](https://github.com/MJoergen/C64MEGA65), from which this
port is derived at version 5.2. It uses the
[MiSTer2MEGA65](https://github.com/sy2002/MiSTer2MEGA65) framework and
[QNICE-FPGA](https://github.com/sy2002/QNICE-FPGA) for FAT32 support and the
on-screen menu.

The K2 board shell is derived from
[AExp-K2](https://github.com/mbrukner/AExp-K2) by Matthias Brukner.

Licence
-------

See [LICENSE](LICENSE).
