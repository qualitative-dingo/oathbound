#!/usr/bin/env python3
"""Verify all creature .gltf files have non-transparent textures and report unique color counts."""

import json
import base64
import os
from pathlib import Path
from collections import Counter

try:
    from PIL import Image
    import io
except ImportError:
    print("PIL/Pillow required: pip install Pillow")
    exit(1)

CREATURES_DIR = Path(__file__).parent


def extract_images_from_gltf(gltf_path):
    """Extract image data from gltf file (embedded base64 or external references)."""
    with open(gltf_path, "rb") as f:
        data = json.load(f)

    images = data.get("images", [])
    results = []

    for i, img_def in enumerate(images):
        uri = img_def.get("uri")
        if not uri:
            continue
        if uri.startswith("data:image"):
            header, b64 = uri.split(",", 1)
            try:
                raw = base64.b64decode(b64)
                results.append(Image.open(io.BytesIO(raw)).convert("RGBA"))
            except Exception as e:
                results.append(None)
                print(f"  Image {i}: decode error - {e}")
        else:
            ext_path = gltf_path.parent / uri
            if ext_path.exists():
                try:
                    results.append(Image.open(ext_path).convert("RGBA"))
                except Exception as e:
                    results.append(None)
                    print(f"  Image {i}: load error - {e}")
            else:
                results.append(None)
                print(f"  Image {i}: external file not found - {uri}")

    return results


def analyze_image(img):
    """Return (unique_colors, opaque_pixel_ratio, has_content)."""
    if img is None:
        return None, None, False
    w, h = img.size
    pixels = list(img.getdata())
    total = len(pixels)
    opaque = sum(1 for p in pixels if p[3] >= 250)
    semi = sum(1 for p in pixels if 10 < p[3] < 250)
    transparent = sum(1 for p in pixels if p[3] <= 10)
    unique = len(set(pixels))
    opaque_ratio = opaque / total if total else 0
    has_content = opaque + semi > total * 0.01
    return unique, opaque_ratio, has_content


def main():
    gltf_files = sorted(CREATURES_DIR.glob("*.gltf"))
    print(f"Verifying {len(gltf_files)} creature .gltf files\n")
    print("-" * 60)

    all_ok = True
    for gltf_path in gltf_files:
        name = gltf_path.stem
        imgs = extract_images_from_gltf(gltf_path)
        if not imgs:
            print(f"{name}: NO TEXTURES")
            all_ok = False
            continue

        for i, img in enumerate(imgs):
            unique, opaque_ratio, has_content = analyze_image(img)
            if unique is None:
                print(f"{name} (tex {i}): FAILED TO LOAD")
                all_ok = False
            else:
                status = "OK" if (has_content and opaque_ratio > 0.5) else "WARN"
                if not has_content or opaque_ratio <= 0.5:
                    all_ok = False
                print(f"{name}: unique colors={unique}, opaque={opaque_ratio:.1%} {status}")

    print("-" * 60)
    print("Done." if all_ok else "Some files need attention.")


if __name__ == "__main__":
    main()
