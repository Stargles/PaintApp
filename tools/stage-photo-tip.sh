#!/bin/zsh
# Stages the 40x200 black vertical bar the photo-tip UI test imports as the newest item in a
# simulator's Photos library. Usage: tools/stage-photo-tip.sh <simulator udid>
set -e
[[ -n "$1" ]] || { echo "usage: $0 <simulator udid>" >&2; exit 2; }
png="$(mktemp -d)/photo-tip-vertical-bar-40x200.png"
python3 - "$png" <<'PY'
import struct, sys, zlib
w, h = 40, 200
rows = b"".join(b"\x00" + b"\x00\x00\x00" * w for _ in range(h))
def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))
open(sys.argv[1], "wb").write(png)
PY
xcrun simctl addmedia "$1" "$png"
