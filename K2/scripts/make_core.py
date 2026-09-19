#!/usr/bin/env python3
"""Package a Vivado .bit into a Wildbits/K2 FPGA-manager core image.

The RP2040 FPGA manager (Firmware/fpga-manager) programs the Artix itself and
is strict about what it accepts:

  * the image is the RAW configuration bitstream -- no .bit ASCII header and
    no write_cfgmem flash padding;
  * it must be EXACTLY 9,730,652 bytes for the XC7A200T (FPGA_SIZE in
    fpga_mgr.cpp), which means BITSTREAM.GENERAL.COMPRESS must be FALSE;
  * a .gz is accepted too, validated by gzip magic, CRC-32 and the same
    decompressed size.

Reference: /cores are installed as CNTX1..CNTX4/<name>.bin or .gz on the
RP2040's SD card, or written into a context's replaceable flash slot by
k2coremgr.pgz running on the K2.

This is pure Python so a core can be repackaged without Vivado.
"""
import argparse
import gzip
import hashlib
import struct
import sys
from pathlib import Path

# XC7A200T uncompressed configuration bitstream length (FPGA_SIZE in
# fpga_mgr.cpp).  This is the one hard requirement: the manager rejects any
# other decompressed length.
FPGA_SIZE = 9_730_652
BUS_WIDTH = bytes.fromhex("000000bb11220044")
SYNC_WORD = bytes.fromhex("aa995566")


def strip_bit_header(raw: bytes) -> bytes:
    """Return the configuration payload of a Vivado .bit file.

    A .bit begins with a 2-byte-length field, a 2-byte constant, then
    key/value fields 'a'..'d' each with a 16-bit big-endian length, and
    finally key 'e' with a 32-bit big-endian length followed by the payload.
    """
    if raw[:2] != b"\x00\x09":
        raise ValueError("not a Vivado .bit file (bad leading length)")
    pos = 2 + 9 + 2  # magic block, then the 2-byte 0x0001 field
    while pos < len(raw):
        key = raw[pos:pos + 1]
        pos += 1
        if key == b"e":
            (length,) = struct.unpack_from(">I", raw, pos)
            pos += 4
            payload = raw[pos:pos + length]
            if len(payload) != length:
                raise ValueError("truncated .bit payload")
            return payload
        if key not in (b"a", b"b", b"c", b"d"):
            raise ValueError(f"unexpected .bit field {key!r} at {pos - 1:#x}")
        (length,) = struct.unpack_from(">H", raw, pos)
        pos += 2 + length
    raise ValueError("no 'e' payload field found in .bit")


def check_image(image: bytes) -> None:
    """Validate the shape of a raw configuration bitstream.

    The leading 0xFF dummy run is NOT a fixed length: it varies with the
    BITSTREAM.CONFIG SPI settings, and Vivado compensates by emitting fewer
    trailing NOOP words so the total stays at FPGA_SIZE.  The reference K2
    core has 32 dummy bytes and ours has 288, and both are valid.  So check
    the structure -- dummy run, bus-width detect, sync -- and the total size,
    not absolute offsets.
    """
    problems = []
    if len(image) != FPGA_SIZE:
        hint = ""
        if len(image) < FPGA_SIZE * 3 // 4:
            hint = (" This is roughly the size of a bitstream-compressed "
                    "image, so BITSTREAM.GENERAL.COMPRESS is still TRUE.")
        problems.append(f"size is {len(image)}, expected {FPGA_SIZE}.{hint}")

    bus_at = image.find(BUS_WIDTH)
    if bus_at < 0:
        problems.append("no bus-width detect pattern (000000BB 11220044)")
    else:
        if image[:bus_at] != b"\xff" * bus_at:
            problems.append(
                f"the {bus_at} bytes before the bus-width pattern are not all "
                "0xFF, so this is not a raw bitstream (write_cfgmem output "
                "carries a flash image header)")
        sync_at = bus_at + len(BUS_WIDTH) + 8
        if image[bus_at + len(BUS_WIDTH):sync_at] != b"\xff" * 8:
            problems.append("bus-width pattern is not followed by 8 dummy bytes")
        elif image[sync_at:sync_at + 4] != SYNC_WORD:
            problems.append(
                f"sync word AA995566 not at {sync_at:#x}, right after the "
                "bus-width preamble")

    if problems:
        raise SystemExit("make_core: refusing to package:\n  - "
                         + "\n  - ".join(problems))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("bitfile", type=Path, help="Vivado .bit to package")
    parser.add_argument("-o", "--output", type=Path, required=True,
                        help="output .bin path; a .gz is written beside it")
    parser.add_argument("--no-gzip", action="store_true",
                        help="write only the raw .bin")
    args = parser.parse_args()

    raw = args.bitfile.read_bytes()
    image = strip_bit_header(raw) if raw[:2] == b"\x00\x09" else raw
    check_image(image)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    digest = hashlib.sha256(image).hexdigest()
    print(f"{args.output}: {len(image)} bytes, sha256 {digest[:16]}")

    if not args.no_gzip:
        gz_path = args.output.with_suffix(args.output.suffix + ".gz")
        # mtime=0 keeps the output reproducible; the manager ignores the
        # timestamp but a stable image makes build comparisons meaningful.
        with gzip.GzipFile(filename="", mode="wb", compresslevel=9,
                           fileobj=gz_path.open("wb"), mtime=0) as f:
            f.write(image)
        ratio = 100.0 * gz_path.stat().st_size / len(image)
        print(f"{gz_path}: {gz_path.stat().st_size} bytes ({ratio:.1f}% of raw)")
        if gzip.decompress(gz_path.read_bytes()) != image:
            raise SystemExit("make_core: gzip round-trip mismatch")

    print("make_core: OK. Copy to CNTX<n>/ on the RP2040 SD card, or install "
          "it into a context flash slot with k2coremgr.pgz.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
