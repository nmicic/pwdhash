#!/usr/bin/env python3
"""Draw the app's geometric hash/key icon locally; no remote image service."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1]
folder = root / "src/IOS/PwdHash/Assets.xcassets/AppIcon.appiconset"
folder.mkdir(parents=True, exist_ok=True)
image = Image.new("RGB", (1024, 1024), (20, 64, 51))
draw = ImageDraw.Draw(image)
mint = (170, 239, 210)
# A hash mark with softly rounded strokes, with one stem becoming a key.
def stroke(points, width=64):
    draw.line(points, fill=mint, width=width, joint="curve")
    radius = width // 2
    for x, y in [points[0], points[-1]]:
        draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=mint)
stroke([(420, 294), (340, 730)])
stroke([(650, 294), (570, 730)])
stroke([(268, 442), (734, 442)])
stroke([(238, 610), (704, 610)])
draw.ellipse((637, 169, 829, 361), fill=mint)
draw.ellipse((692, 224, 774, 306), fill=(20, 64, 51))
image.save(folder / "AppIcon.png")
(folder / "Contents.json").write_text(json.dumps({
    "images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
    "info": {"author": "xcode", "version": 1}
}, indent=2) + "\n")
assets = folder.parent
(assets / "Contents.json").write_text('{"info":{"author":"xcode","version":1}}\n')
legacy = root / ".build/icons"
legacy.mkdir(parents=True, exist_ok=True)
for size, suffix in [(120, "@2x"), (180, "@3x")]:
    image.resize((size, size), Image.Resampling.LANCZOS).save(legacy / f"AppIcon60x60{suffix}.png")
