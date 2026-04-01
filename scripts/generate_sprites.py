#!/usr/bin/env python3
"""
ClaudePet Sprite Generator (64x64)
Generates pixel art character based on Claude mascot (orange rounded square)
4 frames per animation state (idle/bow/alert/happy/working x 4 = 20 PNGs)
PIL coordinate system: y=0 at top, y increases downward

Applies mandatory techniques:
  - auto_outline (adaptive, 8-connected, post-processing)
  - make_palette (3-tone shading from base colors)
  - gradient_shadow (multi-layer ground shadow)
  - Inset outline for overlapping parts (hands on body)
  - Canvas headroom: body top at y=9

Layout (top to bottom, body top=9):
  y ~  1-2   working typing dots (fixed, does not follow dy)
  y ~  9-39  body (rounded rectangle)
  y ~ 19-25  eyes
  y ~ 28     mouth
  y ~ 32-36  bowtie
  y ~ 41-46  feet
  y ~ 50-54  ground shadow (fixed)
"""

import colorsys
from PIL import Image, ImageDraw

SIZE = 64
T = (0, 0, 0, 0)  # transparent

# ── Color palette (derived via make_palette) ──

def make_palette(base_rgb, n=4):
    """Generate n tones from a base RGB color (highlight to shadow)."""
    r, g, b = [c / 255.0 for c in base_rgb[:3]]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    if n == 4:
        steps = [
            (s * 0.6, min(v * 1.35, 1.0)),
            (s * 0.85, min(v * 1.15, 1.0)),
            (s, v),
            (min(s * 1.15, 1.0), v * 0.72),
        ]
    elif n == 3:
        steps = [
            (s * 0.85, min(v * 1.15, 1.0)),
            (s, v),
            (min(s * 1.15, 1.0), v * 0.72),
        ]
    else:
        steps = []
        for i in range(n):
            t = i / max(n - 1, 1)
            ns = s * (0.7 + 0.4 * t)
            nv = v * (1.25 - 0.55 * t)
            steps.append((min(ns, 1.0), min(nv, 1.0)))
    tones = []
    for ns, nv in steps:
        nr, ng, nb = colorsys.hsv_to_rgb(h, ns, nv)
        tones.append((int(nr * 255), int(ng * 255), int(nb * 255), 255))
    return tones


def outline_color_from(base_rgb, darken=0.45):
    """Derive an outline color from a base RGB by reducing HSV value."""
    r, g, b = [c / 255.0 for c in base_rgb[:3]]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    v = max(v * (1.0 - darken), 0.0)
    s = min(s * 1.2, 1.0)
    nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
    return (int(nr * 255), int(ng * 255), int(nb * 255), 255)


# Body palette: specular, highlight, base, shadow
BODY_BASE  = (205, 119, 84)
BODY_HI, BODY_LIGHT, BODY, BODY_DARK = make_palette(BODY_BASE, n=4)

# Limb palette: highlight, base, shadow
LIMB_BASE  = (188, 108, 78)
LIMB_LT, LIMB, LIMB_DK = make_palette(LIMB_BASE, n=3)
LIMB_OL    = outline_color_from(LIMB_BASE, darken=0.45)

# Eye / mouth
EYE        = (45, 35, 30, 255)
EYE_SHINE  = (255, 255, 255, 255)
MOUTH      = (150, 72, 52, 255)
BLUSH      = (230, 110, 95, 255)

# Bowtie palette: highlight, base, shadow
BOWTIE_BASE = (185, 40, 40)
BOWTIE_LT, BOWTIE, BOWTIE_DK = make_palette(BOWTIE_BASE, n=3)

# Effects
SHADOW_CLR = (0, 0, 0)  # used by gradient_shadow
STAR       = (255, 220, 80, 255)
STAR_GLOW  = (255, 220, 80, 100)
EXCLAM     = (220, 50, 50, 255)


# ────────────────────────────────────────────
# Utility functions
# ────────────────────────────────────────────

def canvas():
    return Image.new("RGBA", (SIZE, SIZE), T)


def auto_outline(img, color=None, mode=8, alpha_threshold=128):
    """Add 1px outline around solid pixels. Adaptive mode if color=None."""
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

    _color_cache = {}
    for y in range(h):
        for x in range(w):
            if pixels[x, y][3] >= alpha_threshold:
                continue
            for dx, dy in neighbors:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and pixels[nx, ny][3] >= alpha_threshold:
                    if color is not None:
                        result_px[x, y] = color
                    else:
                        neighbor_rgb = pixels[nx, ny][:3]
                        if neighbor_rgb not in _color_cache:
                            _color_cache[neighbor_rgb] = outline_color_from(
                                neighbor_rgb, darken=0.45
                            )
                        result_px[x, y] = _color_cache[neighbor_rgb]
                    break
    return result


def gradient_shadow(d, cx=32, sy=50, w=30, layers=3):
    """Multi-layer gradient ground shadow."""
    for i in range(layers):
        layer_idx = layers - 1 - i
        frac = (layer_idx + 1) / layers
        layer_w = int(w * (0.5 + 0.5 * frac))
        alpha = int(15 + 35 * (1.0 - frac))
        h_offset = layer_idx
        d.ellipse(
            [cx - layer_w // 2, sy - h_offset,
             cx + layer_w // 2, sy + 4 + h_offset],
            fill=(0, 0, 0, alpha)
        )


# ────────────────────────────────────────────
# Drawing primitives (body top=9)
# ────────────────────────────────────────────

def draw_body(d, cx=32, top=9, w=36, h=30, dy=0):
    """Rounded square body with 3-tone shading."""
    t = top + dy
    l = cx - w // 2
    r = l + w
    b = t + h
    rad = 7

    # Main body fill
    d.rounded_rectangle([l, t, r, b], radius=rad, fill=BODY)

    # Top-left highlight (specular + highlight)
    for gy in range(t + 3, t + 9):
        for gx in range(l + 3, l + 8):
            d.point((gx, gy), BODY_LIGHT)
    d.point((l + 4, t + 4), BODY_HI)
    d.point((l + 5, t + 4), BODY_HI)
    d.point((l + 4, t + 5), BODY_HI)

    # Bottom-right shadow
    for gy in range(b - 8, b - 3):
        for gx in range(r - 6, r - 2):
            d.point((gx, gy), BODY_DARK)
    for gx in range(l + rad, r - rad):
        d.point((gx, b - 1), BODY_DARK)
        d.point((gx, b - 2), BODY_DARK)


def draw_eyes_normal(d, cx=32, ey=19, dy=0):
    """Normal round eyes + shine."""
    y = ey + dy
    d.ellipse([cx - 11, y, cx - 5, y + 6], fill=EYE)
    d.point((cx - 8, y + 1), EYE_SHINE)
    d.point((cx - 9, y + 1), EYE_SHINE)
    d.point((cx - 8, y + 2), EYE_SHINE)
    d.ellipse([cx + 5, y, cx + 11, y + 6], fill=EYE)
    d.point((cx + 8, y + 1), EYE_SHINE)
    d.point((cx + 7, y + 1), EYE_SHINE)
    d.point((cx + 8, y + 2), EYE_SHINE)


def draw_eyes_closed(d, cx=32, ey=21, dy=0):
    """Closed eyes (bowing) — horizontal arcs."""
    y = ey + dy
    for dx in range(-10, -4):
        d.point((cx + dx, y), EYE)
        d.point((cx + dx, y + 1), EYE)
    for dx in range(5, 11):
        d.point((cx + dx, y), EYE)
        d.point((cx + dx, y + 1), EYE)


def draw_eyes_alert(d, cx=32, ey=17, dy=0):
    """Surprised wide eyes."""
    y = ey + dy
    d.ellipse([cx - 12, y, cx - 4, y + 8], fill=EYE)
    d.point((cx - 9, y + 2), EYE_SHINE)
    d.point((cx - 10, y + 2), EYE_SHINE)
    d.point((cx - 9, y + 3), EYE_SHINE)
    d.ellipse([cx + 4, y, cx + 12, y + 8], fill=EYE)
    d.point((cx + 9, y + 2), EYE_SHINE)
    d.point((cx + 8, y + 2), EYE_SHINE)
    d.point((cx + 9, y + 3), EYE_SHINE)


def draw_eyes_happy(d, cx=32, ey=19, dy=0):
    """Happy ^^ curved eyes."""
    y = ey + dy
    d.point((cx - 10, y + 4), EYE)
    d.point((cx - 9, y + 3), EYE)
    d.point((cx - 8, y + 2), EYE)
    d.point((cx - 7, y + 3), EYE)
    d.point((cx - 6, y + 4), EYE)
    d.point((cx - 9, y + 2), EYE)
    d.point((cx - 7, y + 2), EYE)
    d.point((cx + 6, y + 4), EYE)
    d.point((cx + 7, y + 3), EYE)
    d.point((cx + 8, y + 2), EYE)
    d.point((cx + 9, y + 3), EYE)
    d.point((cx + 10, y + 4), EYE)
    d.point((cx + 7, y + 2), EYE)
    d.point((cx + 9, y + 2), EYE)


def draw_mouth_normal(d, cx=32, my=28, dy=0):
    """Small horizontal line mouth."""
    y = my + dy
    d.line([(cx - 2, y), (cx + 2, y)], fill=MOUTH, width=1)


def draw_mouth_happy(d, cx=32, my=28, dy=0):
    """Happy w-shaped smile."""
    y = my + dy
    pts = [
        (cx - 4, y), (cx - 3, y + 1), (cx - 2, y + 2), (cx - 1, y + 1),
        (cx, y), (cx + 1, y + 1), (cx + 2, y + 2), (cx + 3, y + 1),
        (cx + 4, y),
    ]
    for px, py in pts:
        d.point((px, py), MOUTH)


def draw_mouth_alert(d, cx=32, my=28, dy=0):
    """Surprised O mouth."""
    y = my + dy
    d.ellipse([cx - 2, y - 1, cx + 2, y + 2], fill=MOUTH)


def draw_mouth_closed(d, cx=32, my=28, dy=0):
    y = my + dy
    d.point((cx, y), MOUTH)
    d.point((cx - 1, y), MOUTH)


def draw_blush(d, cx=32, by=25, dy=0):
    """Blush marks on cheeks."""
    y = by + dy
    for gy in range(y, y + 3):
        for gx in range(-14, -11):
            d.point((cx + gx, gy), BLUSH)
        for gx in range(11, 14):
            d.point((cx + gx, gy), BLUSH)


def draw_bowtie(d, cx=32, bty=32, dy=0):
    """Butler red bowtie with 3-tone shading."""
    y = bty + dy
    # Center knot
    d.rectangle([cx - 2, y - 1, cx + 1, y + 2], fill=BOWTIE_DK)
    # Left wing
    d.polygon([(cx - 2, y), (cx - 8, y - 3), (cx - 8, y + 4), (cx - 2, y + 1)], fill=BOWTIE)
    d.line([(cx - 8, y - 3), (cx - 3, y)], fill=BOWTIE_LT, width=1)
    # Right wing
    d.polygon([(cx + 1, y), (cx + 7, y - 3), (cx + 7, y + 4), (cx + 1, y + 1)], fill=BOWTIE)
    d.line([(cx + 7, y - 3), (cx + 2, y)], fill=BOWTIE_LT, width=1)


def draw_feet(d, cx=32, fy=41, dy=0, spread=0):
    """Small stubby feet with highlight."""
    y = fy + dy
    lx = cx - 8 - spread
    d.ellipse([lx, y, lx + 7, y + 5], fill=LIMB)
    d.point((lx + 1, y + 1), LIMB_LT)
    d.point((lx + 2, y + 1), LIMB_LT)
    rx = cx + 1 + spread
    d.ellipse([rx, y, rx + 7, y + 5], fill=LIMB)
    d.point((rx + 4, y + 1), LIMB_LT)
    d.point((rx + 5, y + 1), LIMB_LT)


def draw_hands_down(d, cx=32, hy=25, dy=0):
    """Hands hanging down at body sides."""
    y = hy + dy
    d.ellipse([cx - 22, y, cx - 17, y + 6], fill=LIMB)
    d.point((cx - 21, y + 1), LIMB_LT)
    d.ellipse([cx + 17, y, cx + 22, y + 6], fill=LIMB)
    d.point((cx + 21, y + 1), LIMB_LT)


def draw_hands_front(d, cx=32, hy=33, dy=0):
    """Hands in front (bowing/working) — inset outline for body overlap."""
    y = hy + dy
    # Inset outline: outer ring = outline color, inner fill = limb color
    d.ellipse([cx - 5, y, cx - 1, y + 4], fill=LIMB_OL)
    d.ellipse([cx - 4, y + 1, cx - 2, y + 3], fill=LIMB)
    d.ellipse([cx + 1, y, cx + 5, y + 4], fill=LIMB_OL)
    d.ellipse([cx + 2, y + 1, cx + 4, y + 3], fill=LIMB)


def draw_hand_raised(d, cx=32, hy=25, dy=0):
    """Right hand raised, left hand normal."""
    y = hy + dy
    d.ellipse([cx - 22, y, cx - 17, y + 6], fill=LIMB)
    d.point((cx - 21, y + 1), LIMB_LT)
    d.ellipse([cx + 18, y - 8, cx + 23, y - 2], fill=LIMB)
    d.point((cx + 21, y - 7), LIMB_LT)


def draw_hands_wave(d, cx=32, hy=25, dy=0, frame=0):
    """Both hands waving (happy)."""
    y = hy + dy
    if frame == 0:
        d.ellipse([cx - 23, y - 7, cx - 18, y - 1], fill=LIMB)
        d.point((cx - 22, y - 6), LIMB_LT)
        d.ellipse([cx + 18, y - 3, cx + 23, y + 3], fill=LIMB)
        d.point((cx + 21, y - 2), LIMB_LT)
    else:
        d.ellipse([cx - 23, y - 3, cx - 18, y + 3], fill=LIMB)
        d.point((cx - 22, y - 2), LIMB_LT)
        d.ellipse([cx + 18, y - 7, cx + 23, y - 1], fill=LIMB)
        d.point((cx + 21, y - 6), LIMB_LT)


def draw_exclamation(d, x=57, ey=3, dy=0):
    """Red exclamation mark (top-right)."""
    y = ey + dy
    d.rectangle([x, y, x + 2, y + 7], fill=EXCLAM)
    d.rectangle([x, y + 10, x + 2, y + 12], fill=EXCLAM)


def draw_stars(d, positions):
    """Small sparkle stars."""
    for (x, y) in positions:
        d.point((x, y), STAR)
        d.point((x - 1, y), STAR)
        d.point((x + 1, y), STAR)
        d.point((x, y - 1), STAR)
        d.point((x, y + 1), STAR)
        d.point((x - 1, y - 1), STAR_GLOW)
        d.point((x + 1, y - 1), STAR_GLOW)
        d.point((x - 1, y + 1), STAR_GLOW)
        d.point((x + 1, y + 1), STAR_GLOW)


def draw_typing_dots(d, cx=32, frame=0):
    """Typing dots animation, fixed at top (does not follow dy)."""
    y = 1
    positions = [(cx - 6, y), (cx - 1, y), (cx + 4, y)]
    for i, (px, py) in enumerate(positions):
        if i <= frame:
            d.point((px, py), EYE_SHINE)
            d.point((px + 1, py), EYE_SHINE)
            d.point((px, py + 1), EYE_SHINE)
            d.point((px + 1, py + 1), EYE_SHINE)


# ────────────────────────────────────────────
# Animation states
# ────────────────────────────────────────────

def gen_idle_1():
    """Breathing cycle: base position."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d)
    draw_body(d)
    draw_eyes_normal(d)
    draw_mouth_normal(d)
    draw_blush(d)
    draw_bowtie(d)
    draw_hands_down(d)
    return auto_outline(img)


def gen_idle_2():
    """Breathing cycle: slight rise."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, dy=-1)
    draw_body(d, dy=-1)
    draw_eyes_normal(d, dy=-1)
    draw_mouth_normal(d, dy=-1)
    draw_blush(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hands_down(d, dy=-1)
    return auto_outline(img)


def gen_idle_3():
    """Breathing cycle: highest point."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, dy=-2)
    draw_body(d, dy=-2)
    draw_eyes_normal(d, dy=-2)
    draw_mouth_normal(d, dy=-2)
    draw_blush(d, dy=-2)
    draw_bowtie(d, dy=-2)
    draw_hands_down(d, dy=-2)
    return auto_outline(img)


def gen_idle_4():
    """Breathing cycle: descending."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, dy=-1)
    draw_body(d, dy=-1)
    draw_eyes_normal(d, dy=-1)
    draw_mouth_normal(d, dy=-1)
    draw_blush(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hands_down(d, dy=-1)
    return auto_outline(img)


def gen_bow_1():
    """Bow start: slight lean."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d)
    draw_body(d, dy=1)
    draw_eyes_normal(d, dy=1)
    draw_mouth_closed(d, dy=1)
    draw_bowtie(d, dy=1)
    draw_hands_down(d, dy=1)
    return auto_outline(img)


def gen_bow_2():
    """Bowing: shallow bow."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d)
    draw_body(d, dy=2)
    draw_eyes_closed(d, dy=2)
    draw_mouth_closed(d, dy=2)
    draw_bowtie(d, dy=2)
    draw_hands_front(d, dy=2)
    return auto_outline(img)


def gen_bow_3():
    """Bow lowest: deep bow."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d)
    draw_body(d, dy=4)
    draw_eyes_closed(d, dy=4)
    draw_mouth_closed(d, dy=4)
    draw_bowtie(d, dy=4)
    draw_hands_front(d, dy=4)
    return auto_outline(img)


def gen_bow_4():
    """Bow rising: gradually returning."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d)
    draw_body(d, dy=3)
    draw_eyes_closed(d, dy=3)
    draw_mouth_closed(d, dy=3)
    draw_bowtie(d, dy=3)
    draw_hands_front(d, dy=3)
    return auto_outline(img)


def gen_alert_1():
    """Alert: surprised lift."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, spread=1)
    draw_body(d, dy=-1)
    draw_eyes_alert(d, dy=-1)
    draw_mouth_alert(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hand_raised(d, dy=-1)
    draw_exclamation(d, dy=-1)
    return auto_outline(img)


def gen_alert_2():
    """Alert: higher + exclamation offset (flashing effect)."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, spread=1)
    draw_body(d, dy=-2)
    draw_eyes_alert(d, dy=-2)
    draw_mouth_alert(d, dy=-2)
    draw_bowtie(d, dy=-2)
    draw_hand_raised(d, dy=-2)
    draw_exclamation(d, dy=0)
    return auto_outline(img)


def gen_alert_3():
    """Alert: falling back + wider stance."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, spread=2)
    draw_body(d, dy=-1)
    draw_eyes_alert(d, dy=-1)
    draw_mouth_alert(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hand_raised(d, dy=-1)
    draw_exclamation(d, dy=-2)
    return auto_outline(img)


def gen_alert_4():
    """Alert: bounce up again + exclamation reset."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, spread=2)
    draw_body(d, dy=-2)
    draw_eyes_alert(d, dy=-2)
    draw_mouth_alert(d, dy=-2)
    draw_bowtie(d, dy=-2)
    draw_hand_raised(d, dy=-2)
    draw_exclamation(d, dy=-1)
    return auto_outline(img)


def gen_happy_1():
    """Jump start: crouch down."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d, w=28)
    draw_feet(d, dy=-2, spread=1)
    draw_body(d, dy=-2)
    draw_eyes_happy(d, dy=-2)
    draw_mouth_happy(d, dy=-2)
    draw_blush(d, dy=-2)
    draw_bowtie(d, dy=-2)
    draw_hands_wave(d, dy=-2, frame=0)
    draw_stars(d, [(8, 14)])
    return auto_outline(img)


def gen_happy_2():
    """Jump peak."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d, w=20)
    draw_feet(d, dy=-6, spread=2)
    draw_body(d, dy=-6)
    draw_eyes_happy(d, dy=-6)
    draw_mouth_happy(d, dy=-6)
    draw_blush(d, dy=-6)
    draw_bowtie(d, dy=-6)
    draw_hands_wave(d, dy=-6, frame=0)
    draw_stars(d, [(6, 10), (57, 8)])
    return auto_outline(img)


def gen_happy_3():
    """Jump descending."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d, w=24)
    draw_feet(d, dy=-4, spread=1)
    draw_body(d, dy=-4)
    draw_eyes_happy(d, dy=-4)
    draw_mouth_happy(d, dy=-4)
    draw_blush(d, dy=-4)
    draw_bowtie(d, dy=-4)
    draw_hands_wave(d, dy=-4, frame=1)
    draw_stars(d, [(9, 12), (55, 11)])
    return auto_outline(img)


def gen_happy_4():
    """Jump landing."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d, w=28)
    draw_feet(d, dy=-1, spread=1)
    draw_body(d, dy=-1)
    draw_eyes_happy(d, dy=-1)
    draw_mouth_happy(d, dy=-1)
    draw_blush(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hands_wave(d, dy=-1, frame=1)
    draw_stars(d, [(55, 13)])
    return auto_outline(img)


def gen_working_1():
    """Working: leaning forward, focused squint eyes, 1 dot."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, dy=2)
    draw_body(d, dy=3)
    draw_eyes_happy(d, dy=3)
    draw_mouth_closed(d, dy=3)
    draw_blush(d, dy=3)
    draw_bowtie(d, dy=3)
    draw_hands_front(d, dy=1)
    draw_typing_dots(d, frame=0)
    return auto_outline(img)


def gen_working_2():
    """Working: leaning more forward, 2 dots."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, dy=2)
    draw_body(d, dy=4)
    draw_eyes_happy(d, dy=4)
    draw_mouth_closed(d, dy=4)
    draw_blush(d, dy=4)
    draw_bowtie(d, dy=4)
    draw_hands_front(d, dy=2)
    draw_typing_dots(d, frame=1)
    return auto_outline(img)


def gen_working_3():
    """Working: slightly returning, all 3 dots lit."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, dy=1)
    draw_body(d, dy=2)
    draw_eyes_happy(d, dy=2)
    draw_mouth_closed(d, dy=2)
    draw_blush(d, dy=2)
    draw_bowtie(d, dy=2)
    draw_hands_front(d, dy=0)
    draw_typing_dots(d, frame=2)
    return auto_outline(img)


def gen_working_4():
    """Working: leaning forward again, no dots (pause)."""
    img = canvas()
    d = ImageDraw.Draw(img)
    gradient_shadow(d)
    draw_feet(d, dy=2)
    draw_body(d, dy=3)
    draw_eyes_happy(d, dy=3)
    draw_mouth_normal(d, dy=3)
    draw_blush(d, dy=3)
    draw_bowtie(d, dy=3)
    draw_hands_front(d, dy=1)
    return auto_outline(img)


# ────────────────────────────────────────────

def main():
    import os

    out = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "Sources", "ClaudePet", "Resources", "default"
    )
    os.makedirs(out, exist_ok=True)

    sprites = {
        "idle_1": gen_idle_1(), "idle_2": gen_idle_2(),
        "idle_3": gen_idle_3(), "idle_4": gen_idle_4(),
        "bow_1": gen_bow_1(),   "bow_2": gen_bow_2(),
        "bow_3": gen_bow_3(),   "bow_4": gen_bow_4(),
        "alert_1": gen_alert_1(), "alert_2": gen_alert_2(),
        "alert_3": gen_alert_3(), "alert_4": gen_alert_4(),
        "happy_1": gen_happy_1(), "happy_2": gen_happy_2(),
        "happy_3": gen_happy_3(), "happy_4": gen_happy_4(),
        "working_1": gen_working_1(), "working_2": gen_working_2(),
        "working_3": gen_working_3(), "working_4": gen_working_4(),
    }

    for name, img in sprites.items():
        img.save(os.path.join(out, f"{name}.png"))
        print(f"  ✓ {name}.png")

    # 4x enlarged preview
    prev = os.path.join(out, "..", "..", "..", "sprites_preview")
    os.makedirs(prev, exist_ok=True)
    for name, img in sprites.items():
        img.resize((256, 256), Image.NEAREST).save(
            os.path.join(prev, f"{name}_preview.png"))

    # Spritesheet
    cols = len(sprites)
    sheet = Image.new("RGBA", (64 * cols, 64), T)
    for i, name in enumerate(sprites):
        sheet.paste(sprites[name], (i * 64, 0))
    sheet.resize((64 * cols * 3, 64 * 3), Image.NEAREST).save(
        os.path.join(prev, "spritesheet_preview.png"))

    print(f"\n  Sprites → {out}")
    print(f"  Previews → {prev}")


if __name__ == "__main__":
    main()
