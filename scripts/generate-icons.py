#!/usr/bin/env python3
"""Derive raster sizes from the two masters using the catalog's actual slots."""
import json
from pathlib import Path
import subprocess

root = Path(__file__).resolve().parent.parent
for name, master in (("AppIcon", "release"), ("AppIcon-Dev", "dev")):
    source = root / f"Assets/AppIcon-masters/{master}.png"
    if not source.is_file():
        raise SystemExit(f"Missing master: {source}")
    catalog = root / f"Assets/Assets.xcassets/{name}.appiconset"
    for slot in json.loads((catalog / "Contents.json").read_text())["images"]:
        width, height = (int(n) for n in slot["size"].split("x"))
        scale = int(slot["scale"].removesuffix("x"))
        subprocess.run(["sips", "-z", str(height * scale), str(width * scale), str(source), "--out", str(catalog / slot["filename"])], check=True, stdout=subprocess.DEVNULL)
print("Generated both icon sets from their masters.")
