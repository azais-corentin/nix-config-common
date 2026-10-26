"""Extract Tern's hicolor icon set from its binary.

Tern embeds the PNGs its own desktop integration writes, as one contiguous run
of 16 to 512 px icons. The binary embeds other PNGs too, some of them square
512 px images, so only that exact run counts.
Usage: extract-icons.py BINARY HICOLOR_DIR
"""

import struct
import sys
from pathlib import Path

SIZES = (16, 32, 48, 64, 128, 256, 512)
SIGNATURE = b"\x89PNG\r\n\x1a\n"

binary, hicolor = Path(sys.argv[1]).read_bytes(), Path(sys.argv[2])

pngs = []
start = binary.find(SIGNATURE)
while start != -1:
    width, height = struct.unpack(">II", binary[start + 16 : start + 24])
    end = binary.find(b"IEND", start) + 8
    pngs.append((start, end, width, height))
    start = binary.find(SIGNATURE, end)

runs = [
    pngs[index : index + len(SIZES)]
    for index in range(len(pngs) - len(SIZES) + 1)
    if all(
        width == height == size and (i == 0 or begin == pngs[index + i - 1][1])
        for i, ((begin, _, width, height), size) in enumerate(
            zip(pngs[index : index + len(SIZES)], SIZES)
        )
    )
]
if len(runs) != 1:
    sys.exit(f"expected one contiguous {SIZES} icon run, found {len(runs)}")

for begin, end, size, _ in runs[0]:
    target = hicolor / f"{size}x{size}" / "apps" / "so.stencil.tern.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(binary[begin:end])
