#!/bin/sh
# Developer tool: captures a zoomed screenshot of the Dock's icon strip.
#
# Unlike the app itself, this script captures the screen (it shells out to
# screencapture) — that is why it lives here instead of in the app binary.
# The terminal running it needs the Screen Recording permission.
#
# Usage: Tools/dock-shot.sh <out.png>

set -e

out="$1"
if [ -z "$out" ]; then
    echo "usage: Tools/dock-shot.sh <out.png>" >&2
    exit 1
fi

line="$(swift run -c debug CleanDock --dump | grep '^list ')"
if [ -z "$line" ]; then
    echo "cannot read the Dock" >&2
    exit 1
fi

rect="$(echo "$line" | sed -n 's/^list \([^ ]*\) .*/\1/p')"
x="$(echo "$rect" | cut -d, -f1)"
y="$(echo "$rect" | cut -d, -f2)"
w="$(echo "$rect" | cut -d, -f3)"
h="$(echo "$rect" | cut -d, -f4)"

x=$((x - 8))
y=$((y - 14))
w=$((w + 16))
h=$((h + 28))

stem="$(mktemp /tmp/cleandock-shot.XXXXXX)"
raw="$stem.png"
trap 'rm -f "$stem" "$raw"' EXIT      # mktemp makes the extension-less file; screencapture makes the .png

/usr/sbin/screencapture -x -R"$x","$y","$w","$h" "$raw"
swift Tools/zoom.swift "$raw" "$out"

echo "$out"
