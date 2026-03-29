#!/usr/bin/env python3
"""
ClaudePet Status Bar Icon Generator
Generates macOS status bar template image (black silhouette + transparent background)
System automatically adapts to light/dark mode

Output:
  statusbar_icon.png    (18x18, @1x)
  statusbar_icon@2x.png (36x36, @2x Retina)

Style reference from generate_sprites.py:
  Rounded square body + round eyes (transparent cutout) + bowtie + stubby feet
"""

from PIL import Image, ImageDraw

BLACK = (0, 0, 0, 255)
CLEAR = (0, 0, 0, 0)


def gen_icon_2x():
    """36x36 @2x Retina -- body + eyes + hands + feet (vertically centered)"""
    img = Image.new("RGBA", (36, 36), CLEAR)
    d = ImageDraw.Draw(img)
    dy = 4  # Offset down to center vertically

    # ── Body: rounded square ──
    d.rounded_rectangle([9, 3+dy, 27, 22+dy], radius=5, fill=BLACK)

    # ── Eyes: transparent cutout ──
    d.ellipse([13, 9+dy, 17, 13+dy], fill=CLEAR)
    d.ellipse([19, 9+dy, 23, 13+dy], fill=CLEAR)

    # ── Hands: small circles on body sides ──
    d.ellipse([4, 13+dy, 9, 18+dy], fill=BLACK)
    d.ellipse([27, 13+dy, 32, 18+dy], fill=BLACK)

    # ── Feet ──
    d.ellipse([12, 23+dy, 17, 27+dy], fill=BLACK)
    d.ellipse([19, 23+dy, 24, 27+dy], fill=BLACK)

    return img


def gen_icon_1x():
    """18x18 @1x -- simplified version (vertically centered)"""
    img = Image.new("RGBA", (18, 18), CLEAR)
    d = ImageDraw.Draw(img)
    dy = 2  # Offset down to center vertically

    # ── Body ──
    d.rounded_rectangle([4, 1+dy, 14, 11+dy], radius=2, fill=BLACK)

    # ── Eyes (cutout) ──
    d.rectangle([6, 4+dy, 7, 6+dy], fill=CLEAR)
    d.rectangle([10, 4+dy, 11, 6+dy], fill=CLEAR)

    # ── Hands ──
    d.rectangle([2, 7+dy, 4, 9+dy], fill=BLACK)
    d.rectangle([14, 7+dy, 16, 9+dy], fill=BLACK)

    # ── Feet ──
    d.rectangle([6, 12+dy, 8, 14+dy], fill=BLACK)
    d.rectangle([10, 12+dy, 12, 14+dy], fill=BLACK)

    return img


def main():
    import os

    out = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "Sources", "ClaudePet", "Resources"
    )
    os.makedirs(out, exist_ok=True)

    # @1x
    icon_1x = gen_icon_1x()
    icon_1x.save(os.path.join(out, "statusbar_icon.png"))
    print("  ✓ statusbar_icon.png (18x18)")

    # @2x
    icon_2x = gen_icon_2x()
    icon_2x.save(os.path.join(out, "statusbar_icon@2x.png"))
    print("  ✓ statusbar_icon@2x.png (36x36)")

    # Enlarged preview
    prev = os.path.join(out, "..", "..", "..", "sprites_preview")
    os.makedirs(prev, exist_ok=True)
    icon_2x.resize((144, 144), Image.NEAREST).save(
        os.path.join(prev, "statusbar_icon_preview.png"))
    print(f"  ✓ statusbar_icon_preview.png (4x preview)")

    print(f"\n  Icons → {out}")


if __name__ == "__main__":
    main()
