#!/usr/bin/env python3
"""
Generates a pixel-perfect DMG background for Port Menu.

Canvas: 540×360 px, white background.
Layout: App icon at x=130, Applications at x=410, arrow centered at x=270, y=160.

Run: python3 packaging/generate-dmg-background.py
Output: packaging/dmg-background.png
"""

from PIL import Image, ImageDraw
import pathlib

W, H = 540, 360
img = Image.new("RGB", (W, H), "#FFFFFF")
draw = ImageDraw.Draw(img)

ax, ay = 270, 160
arrow_len = 44
head = 12
stroke = 3
color = "#BBBBBB"

draw.line(
    [(ax - arrow_len // 2, ay), (ax + arrow_len // 2 - head + 2, ay)],
    fill=color, width=stroke,
)
draw.line(
    [(ax + arrow_len // 2 - head, ay - head // 2), (ax + arrow_len // 2, ay)],
    fill=color, width=stroke,
)
draw.line(
    [(ax + arrow_len // 2 - head, ay + head // 2), (ax + arrow_len // 2, ay)],
    fill=color, width=stroke,
)

out = pathlib.Path(__file__).parent / "dmg-background.png"
img.save(out)
print(f"Saved {W}x{H} background to {out}")
