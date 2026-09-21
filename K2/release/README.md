# C64 core for the Wildbits K2 / Foenix F256K2

Build of 2026-09-21. PAL Commodore 64 — 6510, VIC-II, switchable 6581/8580 SID
(including dual SID), switchable 6526/8521 CIA, and one simulated C1541 that
reads and writes D64 images. Simulated CRT cartridges and PRG loading from SD.

Target: **RevB0C** board, XC7A200T.

The images themselves are **GitHub Release assets**, not files in this repo —
they are ~20 MB per build. This directory keeps only the release notes and
checksums, so a published build stays documented and verifiable.

## Files

| File | Size | Use |
|---|---|---|
| `WildbitsC64-K2-20260921.bin.gz` | 1.1 MB | **Install this.** Compressed image for the FPGA loader. |
| `WildbitsC64-K2-20260921.bin` | 9.3 MB | Raw image. Use if you prefer uncompressed, or your loader predates gzip support. |
| `WildbitsC64-K2-20260921.bit` | 9.3 MB | JTAG only, for Vivado's hardware manager. **Not** for the SD card. |

Checksums in `SHA256SUMS`; verify with `sha256sum -c SHA256SUMS`.

The `.gz` decompresses to exactly the `.bin` — they are the same core, so you
only need one of them on the card.

## Installing

Copy **one** file into the context directory you want on the RP2040's SD card:

```
CNTX1/WildbitsC64-K2-20260921.bin.gz
```

Any of `CNTX1`..`CNTX4` works; that is just which slot you select at power-on.

### Keep the `Wildbits` prefix

That prefix is not decoration — it is how the loader finds the file. For each
context the manager scans the directory for **`Wildbits*.gz`** first, then
**`Wildbits*.bin`**. Anything named otherwise is not discovered.

So you can call the file whatever you like after that prefix, and it will be
picked up in any of the four contexts. `.gz` wins over `.bin` when both are
present, so only one is needed.

### If your core does not load: check your loader version

**How a naming problem looks:** when a core is found, it loads in about a
second and the machine reboots into it. When the name is wrong, none of that
happens — no load, no reboot, and the machine sits at a **black screen** doing
nothing.

That is worth knowing because a black screen is ambiguous on its own. The
signal to look for is the ~1 second load and the reboot. If you never see it,
the loader never found a file, and the core itself never ran — so the problem
is the filename or the loader, not the core.

`Wildbits*` discovery was added to the RP2040 FPGA manager at a certain point.
**Older loaders do not scan for it at all** — they only look for one fixed
filename per context. On those, a correctly built core with a `Wildbits` name
is never found.

If that is you, either update the FPGA manager (recommended — it is the current
`wildbitscomputing/fpga-manager`), or rename the file to the traditional
basename for the context you are using:

| Context | Legacy filename |
|---|---|
| `CNTX1` | `CFP95600C.bin` |
| `CNTX2` | `CFP95616E.bin` |
| `CNTX3` | `f256k2t9.bin` |
| `CNTX4` | `foenix138.bin` |

This is a compatibility fallback, not the convention. Name it `Wildbits*` for
anything you pass on.

**When several match, the highest-sorting name wins.** That gives you free
version ordering — drop a newer dated build in beside an older one and it takes
over. It also means plain version numbers are a trap: `v1.9` sorts *above*
`v1.10`. Dates, or zero-padded numbers, sort correctly.

### If something goes wrong

Hold **RESET** through a restart for golden recovery. Keeping a known-good core
in another context is a good idea regardless.

## What works

Verified on hardware: HDMI output, DDR3, SD card access, the 6510 and 1541
running, and booting from the SD card through the RP2040 loader.

Not yet validated on hardware at the time of this build: keyboard, the
**C= + RESTORE** menu chord, **RUN/STOP + RESTORE** warm reset, D64 loading,
JiffyDOS switching, and settings persistence across a power cycle.

## Not available on this board

No expansion port, so no hardware cartridges — simulated `.crt` files instead.
No IEC connector, so no real drives. HDMI only: there is no analog VGA and no
retro 15 kHz output.

## Build notes

- Raw bitstream, exactly **9,730,652 bytes**. The loader checks this size and
  rejects anything else, which is why bitstream compression must stay off.
- Vendor configuration preamble: 32 bytes of `0xFF`, bus-width detect at 32,
  sync word `AA995566` at 48 — byte-identical to the other stock K2 cores.
- Timing: WNS +0.523 ns, WHS +0.041 ns, WPWS +0.251 ns, zero failing endpoints,
  zero bus-skew violations.

Built from C64MEGA65 V5.2 (MJoergen, sy2002) with a K2 board port. The board
shell derives from AExp-K2 by Matthias Brukner.
