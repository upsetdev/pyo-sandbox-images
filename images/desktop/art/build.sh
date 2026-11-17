#!/bin/sh
# Renders the desktop's art from the SVGs here into OUT, when the image
# builds (Dockerfile, stage art). Needs rsvg-convert and python3.
#
#   build.sh OUT
#
# OUT/wallpaper.png  the wallpaper, 1920x1200 (xwallpaper fits it to the screen)
# OUT/favicon.svg    Pyo's mark, the page's icon
# OUT/favicon.ico    the mark on a dark tile at 16, 32 and 48 pixels, for
#                    browsers without SVG icons
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: build.sh OUT}
mkdir -p "$out"

rsvg-convert -w 1920 -h 1200 "$here/wallpaper.svg" -o "$out/wallpaper.png"
cp "$here/pyo.svg" "$out/favicon.svg"
for n in 16 32 48; do
  rsvg-convert -w "$n" -h "$n" "$here/favicon-tile.svg" -o "$out/favicon-$n.png"
done
# An ICO holding the three PNGs.
python3 -I - "$out" <<'PY'
import struct, sys
out = sys.argv[1]
pngs = [open(f"{out}/favicon-{n}.png", "rb").read() for n in (16, 32, 48)]
head = struct.pack("<HHH", 0, 1, len(pngs))
entries, data, offset = b"", b"", 6 + 16 * len(pngs)
for n, png in zip((16, 32, 48), pngs):
    entries += struct.pack("<BBBBHHII", n, n, 0, 0, 1, 32, len(png), offset)
    data += png
    offset += len(png)
open(f"{out}/favicon.ico", "wb").write(head + entries + data)
PY
rm -f "$out"/favicon-*.png
