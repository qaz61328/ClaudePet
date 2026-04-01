"""
ClaudePet Pixel Art Utility Functions

Copy these functions into your persona's generate_sprites.py.
All functions use only PIL (Pillow) — no external dependencies.
"""

import colorsys
from PIL import Image, ImageDraw


# ────────────────────────────────────────────
# Color Utilities
# ────────────────────────────────────────────

def make_palette(base_rgb, n=4):
    """Generate n tones from a base RGB color (highlight to shadow).

    Returns a list of RGBA tuples from lightest to darkest:
      [specular, highlight, base, shadow] (n=4)
      [highlight, base, shadow] (n=3)

    Uses HSV adjustments:
      - Highlights: increase value, decrease saturation
      - Shadows: decrease value, increase saturation
    """
    r, g, b = [c / 255.0 for c in base_rgb[:3]]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)

    tones = []
    if n == 4:
        steps = [
            (s * 0.6, min(v * 1.35, 1.0)),   # specular
            (s * 0.85, min(v * 1.15, 1.0)),   # highlight
            (s, v),                             # base
            (min(s * 1.15, 1.0), v * 0.72),   # shadow
        ]
    elif n == 3:
        steps = [
            (s * 0.85, min(v * 1.15, 1.0)),   # highlight
            (s, v),                             # base
            (min(s * 1.15, 1.0), v * 0.72),   # shadow
        ]
    else:
        # Linear interpolation from bright to dark
        steps = []
        for i in range(n):
            t = i / max(n - 1, 1)
            ns = s * (0.7 + 0.4 * t)
            nv = v * (1.25 - 0.55 * t)
            steps.append((min(ns, 1.0), min(nv, 1.0)))

    for ns, nv in steps:
        nr, ng, nb = colorsys.hsv_to_rgb(h, ns, nv)
        tones.append((int(nr * 255), int(ng * 255), int(nb * 255), 255))

    return tones


def outline_color_from(base_rgb, darken=0.45):
    """Derive an outline color from a base RGB by reducing HSV value.

    Args:
        base_rgb: (r, g, b) or (r, g, b, a) tuple
        darken: how much to reduce brightness (0.0-1.0, default 0.45)

    Returns:
        (r, g, b, 255) RGBA tuple
    """
    r, g, b = [c / 255.0 for c in base_rgb[:3]]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    v = max(v * (1.0 - darken), 0.0)
    s = min(s * 1.2, 1.0)  # slightly more saturated
    nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
    return (int(nr * 255), int(ng * 255), int(nb * 255), 255)


# ────────────────────────────────────────────
# Auto-Outline (post-processing)
# ────────────────────────────────────────────

def auto_outline(img, color=None, mode=8, alpha_threshold=128):
    """Add a 1px outline around all solid pixels.

    Scans the image for solid pixels (alpha >= alpha_threshold) and draws
    an outline on adjacent transparent pixels. The outline goes
    BEHIND the character (only on transparent/semi-transparent pixels).

    Semi-transparent pixels (like ground shadows with alpha 15-50) are
    skipped — they don't trigger outlines and don't block outline placement.

    When color is None (adaptive mode), the outline color is derived
    from the neighboring pixel that triggered it — each region gets
    an outline matching its own color (e.g., body gets dark orange,
    bowtie gets dark red).

    Args:
        img: PIL Image (RGBA)
        color: outline color as (r, g, b, a) tuple, or None for adaptive
        mode: 4 (cardinal only) or 8 (includes diagonals, smoother)
        alpha_threshold: minimum alpha to be considered a solid pixel (default 128)

    Returns:
        New PIL Image with outline applied
    """
    w, h = img.size
    pixels = img.load()
    result = img.copy()
    result_px = result.load()

    if mode == 8:
        neighbors = [(-1, -1), (0, -1), (1, -1),
                     (-1,  0),          (1,  0),
                     (-1,  1), (0,  1), (1,  1)]
    else:
        neighbors = [(0, -1), (-1, 0), (1, 0), (0, 1)]

    # Cache for adaptive outline colors
    _color_cache = {}

    for y in range(h):
        for x in range(w):
            # Only draw outline on non-solid pixels
            if pixels[x, y][3] >= alpha_threshold:
                continue
            # Find the first solid neighbor
            for dx, dy in neighbors:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and pixels[nx, ny][3] >= alpha_threshold:
                    if color is not None:
                        result_px[x, y] = color
                    else:
                        # Adaptive: derive outline from neighbor's color
                        neighbor_rgb = pixels[nx, ny][:3]
                        if neighbor_rgb not in _color_cache:
                            _color_cache[neighbor_rgb] = outline_color_from(
                                neighbor_rgb, darken=0.45
                            )
                        result_px[x, y] = _color_cache[neighbor_rgb]
                    break

    return result


# ────────────────────────────────────────────
# Ground Shadow
# ────────────────────────────────────────────

def gradient_shadow(d, cx=32, sy=47, w=30, layers=3):
    """Draw a multi-layer gradient ground shadow.

    Creates a softer, more natural shadow by stacking ellipses
    of decreasing size and increasing opacity.

    Args:
        d: ImageDraw instance
        cx: center x
        sy: shadow top y
        w: maximum shadow width
        layers: number of layers (default 3)
    """
    for i in range(layers):
        # Outer layers are wider and more transparent
        layer_idx = layers - 1 - i  # draw outer first
        frac = (layer_idx + 1) / layers
        layer_w = int(w * (0.5 + 0.5 * frac))
        alpha = int(15 + 35 * (1.0 - frac))  # inner=50, outer=15
        h_offset = layer_idx  # slight vertical spread for outer layers

        d.ellipse(
            [cx - layer_w // 2, sy - h_offset,
             cx + layer_w // 2, sy + 4 + h_offset],
            fill=(0, 0, 0, alpha)
        )


# ────────────────────────────────────────────
# Dithering
# ────────────────────────────────────────────

def dither_rect(img, x1, y1, x2, y2, color_a, color_b):
    """Apply checkerboard dithering in a rectangular region.

    Alternates between color_a and color_b in a checkerboard pattern.
    Only affects pixels that are already non-transparent.

    Args:
        img: PIL Image (RGBA), modified in place
        x1, y1, x2, y2: rectangle bounds
        color_a, color_b: RGBA color tuples
    """
    pixels = img.load()
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            if 0 <= x < img.width and 0 <= y < img.height:
                if pixels[x, y][3] > 0:  # only affect existing pixels
                    pixels[x, y] = color_a if (x + y) % 2 == 0 else color_b


def dither_band(d, img, y_start, x_left, x_right, color_a, color_b, rows=2):
    """Draw a horizontal dither band between two colors.

    Useful for transitions between body regions (e.g., body-to-shadow).

    Args:
        d: ImageDraw instance (unused, kept for API consistency)
        img: PIL Image (RGBA), modified in place
        y_start: top row of the dither band
        x_left, x_right: horizontal bounds
        color_a, color_b: RGBA color tuples
        rows: number of dither rows (1-2 recommended for 64x64)
    """
    pixels = img.load()
    for row in range(rows):
        y = y_start + row
        for x in range(x_left, x_right + 1):
            if 0 <= x < img.width and 0 <= y < img.height:
                if pixels[x, y][3] > 0:
                    pixels[x, y] = color_a if (x + row) % 2 == 0 else color_b


# ────────────────────────────────────────────
# Symmetry
# ────────────────────────────────────────────

def mirror_half(img, axis='vertical'):
    """Mirror one half of the image to the other for perfect symmetry.

    Args:
        img: PIL Image (RGBA)
        axis: 'vertical' (left->right) or 'horizontal' (top->bottom)

    Returns:
        New PIL Image with mirrored symmetry
    """
    result = img.copy()
    pixels = img.load()
    result_px = result.load()
    w, h = img.size

    if axis == 'vertical':
        mid = w // 2
        for y in range(h):
            for x in range(mid):
                result_px[w - 1 - x, y] = pixels[x, y]
    else:
        mid = h // 2
        for x in range(w):
            for y in range(mid):
                result_px[x, h - 1 - y] = pixels[x, y]

    return result


# ────────────────────────────────────────────
# Preview Generation
# ────────────────────────────────────────────

def gen_preview(sprites_dir, scale=4):
    """Generate enlarged preview images and a spritesheet.

    Reads all 20 sprite PNGs from sprites_dir, creates:
    - Individual {scale}x enlarged previews (preview_{name}.png)
    - A combined spritesheet (spritesheet_preview.png)

    Args:
        sprites_dir: path to directory containing the 20 PNGs
        scale: enlargement factor (default 4)
    """
    import os

    states = ['idle', 'bow', 'alert', 'happy', 'working']
    frames = [1, 2, 3, 4]
    names = [f"{s}_{f}" for s in states for f in frames]

    preview_dir = os.path.join(sprites_dir, "preview")
    os.makedirs(preview_dir, exist_ok=True)

    sprites = {}
    for name in names:
        path = os.path.join(sprites_dir, f"{name}.png")
        if os.path.exists(path):
            sprites[name] = Image.open(path)

    if not sprites:
        print("  No sprites found!")
        return

    # Individual enlarged previews
    for name, img in sprites.items():
        enlarged = img.resize(
            (img.width * scale, img.height * scale), Image.NEAREST
        )
        enlarged.save(os.path.join(preview_dir, f"preview_{name}.png"))

    # Spritesheet (5 rows x 4 columns)
    cols, rows = 4, 5
    cell_w, cell_h = 64, 64
    sheet = Image.new("RGBA", (cols * cell_w * scale, rows * cell_h * scale), (0, 0, 0, 0))
    for row_idx, state in enumerate(states):
        for col_idx, frame in enumerate(frames):
            name = f"{state}_{frame}"
            if name in sprites:
                enlarged = sprites[name].resize(
                    (cell_w * scale, cell_h * scale), Image.NEAREST
                )
                sheet.paste(enlarged, (col_idx * cell_w * scale, row_idx * cell_h * scale))
    sheet.save(os.path.join(preview_dir, "spritesheet_preview.png"))

    print(f"  Preview → {preview_dir}")
    print(f"  Spritesheet → {os.path.join(preview_dir, 'spritesheet_preview.png')}")
