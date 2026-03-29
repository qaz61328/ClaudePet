#!/usr/bin/env python3
"""
ClaudePet Sprite Generator (64x64)
Generates pixel art character based on Claude mascot (orange rounded square)
4 frames per animation state (idle/bow/alert/happy/working x 4 = 20 PNGs)
PIL coordinate system: y=0 at top, y increases downward

Layout (top to bottom):
  y ~  1-2   working typing dots (fixed position, does not move with body)
  y ~  4-36  body (rounded rectangle)
  y ~ 12-18  eyes
  y ~ 21-24  mouth
  y ~ 27-33  bowtie
  y ~ 37-43  feet
  y ~ 46-50  ground shadow
"""

from PIL import Image, ImageDraw

SIZE = 64
T = (0, 0, 0, 0)  # transparent

# ── Color palette ──
BODY       = (205, 119, 84, 255)
BODY_DARK  = (178, 98, 68, 255)
BODY_LIGHT = (225, 150, 120, 255)
BODY_HI    = (240, 175, 148, 255)

EYE        = (45, 35, 30, 255)
EYE_SHINE  = (255, 255, 255, 255)
MOUTH      = (150, 72, 52, 255)
BLUSH      = (230, 110, 95, 255)

BOWTIE     = (185, 40, 40, 255)
BOWTIE_DK  = (145, 30, 30, 255)
BOWTIE_LT  = (210, 65, 65, 255)

LIMB       = (188, 108, 78, 255)
LIMB_DK    = (165, 90, 65, 255)

SHADOW     = (0, 0, 0, 35)
STAR       = (255, 220, 80, 255)
EXCLAM     = (220, 50, 50, 255)


def canvas():
    return Image.new("RGBA", (SIZE, SIZE), T)


# ────────────────────────────────────────────
# Basic drawing primitives
# ────────────────────────────────────────────

def draw_body(d, cx=32, top=6, w=36, h=30, dy=0):
    """Rounded square body"""
    t = top + dy
    l = cx - w // 2
    r = l + w
    b = t + h
    rad = 7

    # Main body fill
    d.rounded_rectangle([l, t, r, b], radius=rad, fill=BODY)

    # Top-left highlight
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
    # Bottom edge shadow
    for gx in range(l + rad, r - rad):
        d.point((gx, b - 1), BODY_DARK)
        d.point((gx, b - 2), BODY_DARK)


def draw_eyes_normal(d, cx=32, ey=16, dy=0):
    """Normal round eyes + shine"""
    y = ey + dy
    # Left eye
    d.ellipse([cx - 11, y, cx - 5, y + 6], fill=EYE)
    d.point((cx - 8, y + 1), EYE_SHINE)
    d.point((cx - 9, y + 1), EYE_SHINE)
    d.point((cx - 8, y + 2), EYE_SHINE)
    # Right eye
    d.ellipse([cx + 5, y, cx + 11, y + 6], fill=EYE)
    d.point((cx + 8, y + 1), EYE_SHINE)
    d.point((cx + 7, y + 1), EYE_SHINE)
    d.point((cx + 8, y + 2), EYE_SHINE)


def draw_eyes_closed(d, cx=32, ey=18, dy=0):
    """Closed eyes (for bowing) -- horizontal arcs"""
    y = ey + dy
    for dx in range(-10, -4):
        d.point((cx + dx, y), EYE)
        d.point((cx + dx, y + 1), EYE)
    for dx in range(5, 11):
        d.point((cx + dx, y), EYE)
        d.point((cx + dx, y + 1), EYE)


def draw_eyes_alert(d, cx=32, ey=14, dy=0):
    """Surprised wide eyes"""
    y = ey + dy
    # Left eye (larger circle)
    d.ellipse([cx - 12, y, cx - 4, y + 8], fill=EYE)
    d.point((cx - 9, y + 2), EYE_SHINE)
    d.point((cx - 10, y + 2), EYE_SHINE)
    d.point((cx - 9, y + 3), EYE_SHINE)
    # Right eye
    d.ellipse([cx + 4, y, cx + 12, y + 8], fill=EYE)
    d.point((cx + 9, y + 2), EYE_SHINE)
    d.point((cx + 8, y + 2), EYE_SHINE)
    d.point((cx + 9, y + 3), EYE_SHINE)


def draw_eyes_happy(d, cx=32, ey=16, dy=0):
    """Happy ^^ curved eyes"""
    y = ey + dy
    # Left eye ^
    d.point((cx - 10, y + 4), EYE)
    d.point((cx - 9, y + 3), EYE)
    d.point((cx - 8, y + 2), EYE)
    d.point((cx - 7, y + 3), EYE)
    d.point((cx - 6, y + 4), EYE)
    d.point((cx - 9, y + 2), EYE)
    d.point((cx - 7, y + 2), EYE)
    # Right eye ^
    d.point((cx + 6, y + 4), EYE)
    d.point((cx + 7, y + 3), EYE)
    d.point((cx + 8, y + 2), EYE)
    d.point((cx + 9, y + 3), EYE)
    d.point((cx + 10, y + 4), EYE)
    d.point((cx + 7, y + 2), EYE)
    d.point((cx + 9, y + 2), EYE)


def draw_mouth_normal(d, cx=32, my=25, dy=0):
    """Small horizontal line mouth"""
    y = my + dy
    d.line([(cx - 2, y), (cx + 2, y)], fill=MOUTH, width=1)


def draw_mouth_happy(d, cx=32, my=25, dy=0):
    """Happy w-shaped smile"""
    y = my + dy
    # w shape: two small arcs
    pts = [
        (cx - 4, y), (cx - 3, y + 1), (cx - 2, y + 2), (cx - 1, y + 1),
        (cx, y), (cx + 1, y + 1), (cx + 2, y + 2), (cx + 3, y + 1),
        (cx + 4, y),
    ]
    for px, py in pts:
        d.point((px, py), MOUTH)


def draw_mouth_alert(d, cx=32, my=25, dy=0):
    """Surprised O mouth"""
    y = my + dy
    d.ellipse([cx - 2, y - 1, cx + 2, y + 2], fill=MOUTH)


def draw_mouth_closed(d, cx=32, my=25, dy=0):
    y = my + dy
    d.point((cx, y), MOUTH)
    d.point((cx - 1, y), MOUTH)


def draw_blush(d, cx=32, by=22, dy=0):
    """Blush marks"""
    y = by + dy
    for gy in range(y, y + 3):
        for gx in range(-14, -11):
            d.point((cx + gx, gy), BLUSH)
        for gx in range(11, 14):
            d.point((cx + gx, gy), BLUSH)


def draw_bowtie(d, cx=32, bty=29, dy=0):
    """Butler red bowtie"""
    y = bty + dy
    # Center knot
    d.rectangle([cx - 2, y - 1, cx + 1, y + 2], fill=BOWTIE_DK)
    # Left wing (triangle)
    d.polygon([(cx - 2, y), (cx - 8, y - 3), (cx - 8, y + 4), (cx - 2, y + 1)], fill=BOWTIE)
    d.line([(cx - 8, y - 3), (cx - 3, y)], fill=BOWTIE_LT, width=1)
    # Right wing
    d.polygon([(cx + 1, y), (cx + 7, y - 3), (cx + 7, y + 4), (cx + 1, y + 1)], fill=BOWTIE)
    d.line([(cx + 7, y - 3), (cx + 2, y)], fill=BOWTIE_LT, width=1)


def draw_feet(d, cx=32, fy=38, dy=0, spread=0):
    """Small stubby feet"""
    y = fy + dy
    # Left foot
    lx = cx - 8 - spread
    d.ellipse([lx, y, lx + 7, y + 5], fill=LIMB)
    d.point((lx + 1, y + 1), BODY)
    d.point((lx + 2, y + 1), BODY)
    # Right foot
    rx = cx + 1 + spread
    d.ellipse([rx, y, rx + 7, y + 5], fill=LIMB)
    d.point((rx + 4, y + 1), BODY)
    d.point((rx + 5, y + 1), BODY)


def draw_hands_down(d, cx=32, hy=22, dy=0):
    """Hands hanging down naturally"""
    y = hy + dy
    d.ellipse([cx - 22, y, cx - 17, y + 6], fill=LIMB)
    d.point((cx - 21, y + 1), BODY)
    d.ellipse([cx + 17, y, cx + 22, y + 6], fill=LIMB)
    d.point((cx + 21, y + 1), BODY)


def draw_hands_front(d, cx=32, hy=30, dy=0):
    """Hands in front (bowing)"""
    y = hy + dy
    d.ellipse([cx - 5, y, cx - 1, y + 4], fill=LIMB)
    d.ellipse([cx + 1, y, cx + 5, y + 4], fill=LIMB)


def draw_hand_raised(d, cx=32, hy=22, dy=0):
    """Right hand raised"""
    y = hy + dy
    # Left hand normal
    d.ellipse([cx - 22, y, cx - 17, y + 6], fill=LIMB)
    d.point((cx - 21, y + 1), BODY)
    # Right hand raised high
    d.ellipse([cx + 18, y - 8, cx + 23, y - 2], fill=LIMB)
    d.point((cx + 21, y - 7), BODY)


def draw_hands_wave(d, cx=32, hy=22, dy=0, frame=0):
    """Both hands waving (happy)"""
    y = hy + dy
    if frame == 0:
        d.ellipse([cx - 23, y - 7, cx - 18, y - 1], fill=LIMB)
        d.ellipse([cx + 18, y - 3, cx + 23, y + 3], fill=LIMB)
    else:
        d.ellipse([cx - 23, y - 3, cx - 18, y + 3], fill=LIMB)
        d.ellipse([cx + 18, y - 7, cx + 23, y - 1], fill=LIMB)


def draw_ground_shadow(d, cx=32, sy=47, w=30):
    """Ground shadow"""
    d.ellipse([cx - w // 2, sy, cx + w // 2, sy + 4], fill=SHADOW)


def draw_exclamation(d, x=57, ey=3, dy=0):
    """Red exclamation mark (top-right, no overlap with hand)"""
    y = ey + dy
    d.rectangle([x, y, x + 2, y + 7], fill=EXCLAM)
    d.rectangle([x, y + 10, x + 2, y + 12], fill=EXCLAM)


def draw_stars(d, positions):
    """Small sparkle stars"""
    for (x, y) in positions:
        d.point((x, y), STAR)
        d.point((x - 1, y), STAR)
        d.point((x + 1, y), STAR)
        d.point((x, y - 1), STAR)
        d.point((x, y + 1), STAR)
        # Diagonal glow
        d.point((x - 1, y - 1), (255, 220, 80, 100))
        d.point((x + 1, y - 1), (255, 220, 80, 100))
        d.point((x - 1, y + 1), (255, 220, 80, 100))
        d.point((x + 1, y + 1), (255, 220, 80, 100))


# ────────────────────────────────────────────
# Animation states
# ────────────────────────────────────────────

def gen_idle_1():
    """Breathing cycle: base position"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d)
    draw_body(d)
    draw_eyes_normal(d)
    draw_mouth_normal(d)
    draw_blush(d)
    draw_bowtie(d)
    draw_hands_down(d)
    return img


def gen_idle_2():
    """Breathing cycle: slight rise"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, dy=-1)
    draw_body(d, dy=-1)
    draw_eyes_normal(d, dy=-1)
    draw_mouth_normal(d, dy=-1)
    draw_blush(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hands_down(d, dy=-1)
    return img


def gen_idle_3():
    """Breathing cycle: highest point"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, dy=-2)
    draw_body(d, dy=-2)
    draw_eyes_normal(d, dy=-2)
    draw_mouth_normal(d, dy=-2)
    draw_blush(d, dy=-2)
    draw_bowtie(d, dy=-2)
    draw_hands_down(d, dy=-2)
    return img


def gen_idle_4():
    """Breathing cycle: descending"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, dy=-1)
    draw_body(d, dy=-1)
    draw_eyes_normal(d, dy=-1)
    draw_mouth_normal(d, dy=-1)
    draw_blush(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hands_down(d, dy=-1)
    return img


def gen_bow_1():
    """Bow start: slight lean"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d)
    draw_body(d, dy=1)
    draw_eyes_normal(d, dy=1)
    draw_mouth_closed(d, dy=1)
    draw_bowtie(d, dy=1)
    draw_hands_down(d, dy=1)
    return img


def gen_bow_2():
    """Bowing: shallow bow"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d)
    draw_body(d, dy=2)
    draw_eyes_closed(d, dy=2)
    draw_mouth_closed(d, dy=2)
    draw_bowtie(d, dy=2)
    draw_hands_front(d, dy=2)
    return img


def gen_bow_3():
    """Bow lowest: deep bow"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d)
    draw_body(d, dy=4)
    draw_eyes_closed(d, dy=4)
    draw_mouth_closed(d, dy=4)
    draw_bowtie(d, dy=4)
    draw_hands_front(d, dy=4)
    return img


def gen_bow_4():
    """Bow rising: gradually returning"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d)
    draw_body(d, dy=3)
    draw_eyes_closed(d, dy=3)
    draw_mouth_closed(d, dy=3)
    draw_bowtie(d, dy=3)
    draw_hands_front(d, dy=3)
    return img


def gen_alert_1():
    """Alert: surprised lift"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, spread=1)
    draw_body(d, dy=-1)
    draw_eyes_alert(d, dy=-1)
    draw_mouth_alert(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hand_raised(d, dy=-1)
    draw_exclamation(d, dy=-1)
    return img


def gen_alert_2():
    """Alert: higher + exclamation offset (flashing effect)"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, spread=1)
    draw_body(d, dy=-2)
    draw_eyes_alert(d, dy=-2)
    draw_mouth_alert(d, dy=-2)
    draw_bowtie(d, dy=-2)
    draw_hand_raised(d, dy=-2)
    draw_exclamation(d, dy=0)  # Exclamation stays still, creating flashing effect
    return img


def gen_alert_3():
    """Alert: falling back + wider stance"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, spread=2)
    draw_body(d, dy=-1)
    draw_eyes_alert(d, dy=-1)
    draw_mouth_alert(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hand_raised(d, dy=-1)
    draw_exclamation(d, dy=-2)  # Exclamation shifted up
    return img


def gen_alert_4():
    """Alert: bounce up again + exclamation reset"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, spread=2)
    draw_body(d, dy=-2)
    draw_eyes_alert(d, dy=-2)
    draw_mouth_alert(d, dy=-2)
    draw_bowtie(d, dy=-2)
    draw_hand_raised(d, dy=-2)
    draw_exclamation(d, dy=-1)
    return img


def gen_happy_1():
    """Jump start: crouch down"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d, w=28)
    draw_feet(d, dy=-2, spread=1)
    draw_body(d, dy=-2)
    draw_eyes_happy(d, dy=-2)
    draw_mouth_happy(d, dy=-2)
    draw_blush(d, dy=-2)
    draw_bowtie(d, dy=-2)
    draw_hands_wave(d, dy=-2, frame=0)
    draw_stars(d, [(8, 14)])
    return img


def gen_happy_2():
    """Jump peak"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d, w=20)
    draw_feet(d, dy=-6, spread=2)
    draw_body(d, dy=-6)
    draw_eyes_happy(d, dy=-6)
    draw_mouth_happy(d, dy=-6)
    draw_blush(d, dy=-6)
    draw_bowtie(d, dy=-6)
    draw_hands_wave(d, dy=-6, frame=0)
    draw_stars(d, [(6, 10), (57, 8)])
    return img


def gen_happy_3():
    """Jump descending"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d, w=24)
    draw_feet(d, dy=-4, spread=1)
    draw_body(d, dy=-4)
    draw_eyes_happy(d, dy=-4)
    draw_mouth_happy(d, dy=-4)
    draw_blush(d, dy=-4)
    draw_bowtie(d, dy=-4)
    draw_hands_wave(d, dy=-4, frame=1)
    draw_stars(d, [(9, 12), (55, 11)])
    return img


def gen_happy_4():
    """Jump landing"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d, w=28)
    draw_feet(d, dy=-1, spread=1)
    draw_body(d, dy=-1)
    draw_eyes_happy(d, dy=-1)
    draw_mouth_happy(d, dy=-1)
    draw_blush(d, dy=-1)
    draw_bowtie(d, dy=-1)
    draw_hands_wave(d, dy=-1, frame=1)
    draw_stars(d, [(55, 13)])
    return img


def draw_typing_dots(d, cx=32, frame=0):
    """Typing dots animation (...), positioned above character head, does not move with body"""
    y = 1  # Fixed at top, does not follow dy
    # Three 2x2 dots, appearing one by one per frame: 0->1 dot, 1->2 dots, 2->3 dots
    positions = [(cx - 6, y), (cx - 1, y), (cx + 4, y)]
    for i, (px, py) in enumerate(positions):
        if i <= frame:
            d.point((px, py), EYE_SHINE)
            d.point((px + 1, py), EYE_SHINE)
            d.point((px, py + 1), EYE_SHINE)
            d.point((px + 1, py + 1), EYE_SHINE)


def gen_working_1():
    """Working: leaning forward, focused squint eyes, 1 dot"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, dy=2)
    draw_body(d, dy=3)
    draw_eyes_happy(d, dy=3)
    draw_mouth_closed(d, dy=3)
    draw_blush(d, dy=3)
    draw_bowtie(d, dy=3)
    draw_hands_front(d, dy=1)
    draw_typing_dots(d, frame=0)
    return img


def gen_working_2():
    """Working: leaning more forward, 2 dots"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, dy=2)
    draw_body(d, dy=4)
    draw_eyes_happy(d, dy=4)
    draw_mouth_closed(d, dy=4)
    draw_blush(d, dy=4)
    draw_bowtie(d, dy=4)
    draw_hands_front(d, dy=2)
    draw_typing_dots(d, frame=1)
    return img


def gen_working_3():
    """Working: slightly returning, all 3 dots lit"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, dy=1)
    draw_body(d, dy=2)
    draw_eyes_happy(d, dy=2)
    draw_mouth_closed(d, dy=2)
    draw_blush(d, dy=2)
    draw_bowtie(d, dy=2)
    draw_hands_front(d, dy=0)
    draw_typing_dots(d, frame=2)
    return img


def gen_working_4():
    """Working: leaning forward again, no dots (pause)"""
    img = canvas()
    d = ImageDraw.Draw(img)
    draw_ground_shadow(d)
    draw_feet(d, dy=2)
    draw_body(d, dy=3)
    draw_eyes_happy(d, dy=3)
    draw_mouth_normal(d, dy=3)
    draw_blush(d, dy=3)
    draw_bowtie(d, dy=3)
    draw_hands_front(d, dy=1)
    # Frame 4 has no dots (pause before loop restarts)
    return img


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
