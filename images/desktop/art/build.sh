#!/bin/sh
# Renders the desktop's art from the SVGs here into OUT, when the image
# builds (Dockerfile, stage art). Needs rsvg-convert.
#
#   build.sh OUT
#
# OUT/wallpaper.png  the wallpaper, 1920x1200 (xwallpaper fits it to the screen)
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: build.sh OUT}
mkdir -p "$out"

rsvg-convert -w 1920 -h 1200 "$here/wallpaper.svg" -o "$out/wallpaper.png"
