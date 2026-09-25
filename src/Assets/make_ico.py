"""Write a classic BMP-based ICO that ancient brcc32 can load."""
from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image


def bmp_icon_entry(img: Image.Image) -> tuple[bytes, int, int]:
    """Return XOR+AND DIB payload for one icon size (no BITMAPFILEHEADER)."""
    w, h = img.size
    rgba = img.convert('RGBA')
    # 32-bit BGRA bottom-up XOR bitmap
    xor = bytearray()
    and_mask = bytearray()
    row_and = ((w + 31) // 32) * 4
    for y in range(h - 1, -1, -1):
        and_bits = 0
        and_count = 0
        and_row = bytearray()
        for x in range(w):
            r, g, b, a = rgba.getpixel((x, y))
            xor += bytes((b, g, r, a))
            transparent = 1 if a < 128 else 0
            and_bits = (and_bits << 1) | transparent
            and_count += 1
            if and_count == 8:
                and_row.append(and_bits)
                and_bits = 0
                and_count = 0
        if and_count:
            and_bits <<= 8 - and_count
            and_row.append(and_bits)
        while len(and_row) < row_and:
            and_row.append(0)
        and_mask += and_row

    header = struct.pack(
        '<IIIHHIIIIII',
        40,  # biSize
        w,
        h * 2,  # height includes AND mask
        1,  # planes
        32,  # bit count
        0,  # BI_RGB
        len(xor),
        0,
        0,
        0,
        0,
    )
    data = header + bytes(xor) + bytes(and_mask)
    return data, w, h


def write_ico(path: Path, images: list[Image.Image]) -> None:
    entries: list[tuple[int, int, bytes]] = []
    for im in images:
        data, w, h = bmp_icon_entry(im)
        entries.append((w, h, data))

    offset = 6 + 16 * len(entries)
    buf = bytearray()
    buf += struct.pack('<HHH', 0, 1, len(entries))
    for w, h, data in entries:
        buf += struct.pack(
            '<BBBBHHII',
            w if w < 256 else 0,
            h if h < 256 else 0,
            0,
            0,
            1,
            32,
            len(data),
            offset,
        )
        offset += len(data)
    for _, _, data in entries:
        buf += data
    path.write_bytes(buf)


def main() -> None:
    here = Path(__file__).resolve().parent
    src = Image.open(here / 'mtn2-icon.png').convert('RGBA')
    w, h = src.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    src = src.crop((left, top, left + side, top + side))

    sizes = [16, 32, 48]
    images = [src.resize((s, s), Image.Resampling.LANCZOS) for s in sizes]
    classic = here / 'MTN2.ico'
    write_ico(classic, images)
    print(f'wrote classic {classic} ({classic.stat().st_size} bytes)')

    # High-res PNG-in-ICO for shell / IDE (not for brcc32).
    hi = here / 'MTN2-hi.ico'
    master = src.resize((256, 256), Image.Resampling.LANCZOS)
    master.save(
        hi,
        format='ICO',
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f'wrote hi-res {hi} ({hi.stat().st_size} bytes)')


if __name__ == '__main__':
    main()
