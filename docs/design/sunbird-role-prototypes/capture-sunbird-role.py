#!/usr/bin/env python3
# Throwaway capture: renders each ?variant= of sunbird-role.html in the
# pre-installed headless Chromium at 393x852 css / deviceScaleFactor 3 and
# crops the result to exactly 1179x2556 (pure-python PNG crop; the bundled
# ffmpeg rejects Chromium's PNG output).
import pathlib, struct, subprocess, sys, zlib

here = pathlib.Path(__file__).parent
CHROMIUM = "/opt/pw-browsers/chromium"
W, H, SCALE = 393, 852, 3
WIN_H = 1000  # headroom: headless "new" steals ~81px of window height for chrome

def png_read(path):
    data = pathlib.Path(path).read_bytes()
    pos, idat = 8, b""
    while pos < len(data):
        ln, typ = struct.unpack(">I4s", data[pos:pos + 8])
        if typ == b"IHDR":
            w, h, bd, ct = struct.unpack(">IIBB", data[pos + 8:pos + 18])
        if typ == b"IDAT":
            idat += data[pos + 8:pos + 8 + ln]
        pos += 12 + ln
    assert (bd, ct) in ((8, 2), (8, 6)), f"unexpected PNG format {bd}/{ct}"
    bpp = 4 if ct == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp + 1
    prev = bytearray(w * bpp)
    rows = []
    def paeth(a, b, c):
        p = a + b - c
        pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
        return a if pa <= pb and pa <= pc else (b if pb <= pc else c)
    for y in range(h):
        f = raw[y * stride]
        line = bytearray(raw[y * stride + 1:(y + 1) * stride])
        if f == 1:
            for i in range(bpp, len(line)):
                line[i] = (line[i] + line[i - bpp]) & 255
        elif f == 2:
            for i in range(len(line)):
                line[i] = (line[i] + prev[i]) & 255
        elif f == 3:
            for i in range(len(line)):
                a = line[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(len(line)):
                a = line[i - bpp] if i >= bpp else 0
                c = prev[i - bpp] if i >= bpp else 0
                line[i] = (line[i] + paeth(a, prev[i], c)) & 255
        prev = line
        rows.append(line)
    return w, h, bpp, rows

def png_write(path, w, h, bpp, rows):
    def chunk(typ, payload):
        return (struct.pack(">I", len(payload)) + typ + payload
                + struct.pack(">I", zlib.crc32(typ + payload) & 0xFFFFFFFF))
    ct = 6 if bpp == 4 else 2
    ihdr = struct.pack(">IIBBBBB", w, h, 8, ct, 0, 0, 0)
    body = b"".join(b"\x00" + bytes(r[:w * bpp]) for r in rows)
    out = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
           + chunk(b"IDAT", zlib.compress(body, 6)) + chunk(b"IEND", b""))
    pathlib.Path(path).write_bytes(out)

for v in ["a", "a2", "b", "c"]:
    raw = f"/tmp/sunbird-raw-{v}.png"
    url = f"file://{here / 'sunbird-role.html'}?variant={v}&shot=1"
    subprocess.run(
        [CHROMIUM, "--headless=new", "--disable-gpu", "--no-sandbox",
         "--hide-scrollbars", f"--force-device-scale-factor={SCALE}",
         f"--window-size={W},{WIN_H}", f"--screenshot={raw}", url],
        check=True, capture_output=True)
    w, h, bpp, rows = png_read(raw)
    assert w == W * SCALE and h >= H * SCALE, (w, h)
    out = here / f"sunbird-role-{v}.png"
    png_write(out, W * SCALE, H * SCALE, bpp, rows[:H * SCALE])
    print("wrote", out.name, f"{W * SCALE}x{H * SCALE}")
