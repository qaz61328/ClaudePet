# Pixel Art Techniques for 64x64 Sprites

Practical guide for drawing pixel art characters at 64x64 resolution with Pillow. These rules apply to all ClaudePet persona sprites.

## 1. Outline

The single most impactful technique. A 1px dark outline around the entire character silhouette separates it from any background and adds immediate polish.

**Rules:**
- Apply as a POST-PROCESSING step after all body parts are drawn
- Use `auto_outline()` from utility-functions.py — it scans alpha channel and draws outline on adjacent transparent pixels
- Use 8-connected mode (includes diagonals) for smoother results
- Outline color: same hue as body, 40-50% lower HSV value (brightness). Use `outline_color_from(base_rgb)`
- Outline goes on a layer BEHIND the character (draw on transparent pixels only, never overwrite character pixels)
- Internal outlines (between body parts like arms and torso) are optional — only external silhouette is mandatory

**Adaptive mode (recommended):**
- Pass `color=None` to `auto_outline()` for per-region outline colors
- Each body region gets an outline matching its own hue (e.g., body gets dark orange, bowtie gets dark red, limbs get dark tan)
- Much more natural than a single global outline color

**alpha_threshold (critical for shadows):**
- Use `alpha_threshold=128` (the default) so semi-transparent pixels (like ground shadows with alpha 15-50) are excluded
- Without this, the ground shadow gets an ugly dark ring around it
- Pixels below the threshold neither trigger outlines nor receive them

**Common mistakes:**
- Outline too bright (looks like a glow instead of a border)
- Outline on EVERY internal edge (makes the character look fragmented at 64x64)
- Forgetting to outline effects like exclamation marks or typing dots
- Using a single outline color for the whole character (use adaptive mode instead)

## 1b. Inset Outline for Overlapping Parts

When a body part overlaps the main body (e.g., hands in front of the torso during working state), there's no transparent boundary for `auto_outline()` to detect. The hands become invisible against the body.

**Solution: Inset outline technique**
1. Draw the full ellipse in the outline color (acts as a 1px border)
2. Draw a smaller fill ellipse inside (1px inset on each side)

```python
# Hands overlapping body — inset outline
d.ellipse([cx - 5, y, cx - 1, y + 4], fill=LIMB_OL)      # outline ring
d.ellipse([cx - 4, y + 1, cx - 2, y + 3], fill=LIMB)      # inset fill
```

**When to use:**
- Hands in front of body (working/bow states)
- Any part that overlaps another solid region

**When NOT to use:**
- External limbs (hands at sides, feet) — `auto_outline()` handles these naturally
- Never use `_outlined_ellipse` that expands 1px outward — it creates double outlines when combined with `auto_outline()`

## 2. 3-Tone Shading

Every colored region should use at least 3 tones: highlight, base, shadow.

**Light source:** Always top-left (consistent across all ClaudePet sprites).

**Tone distribution:**
- **Highlight (15-20% of area):** Top-left edges and raised surfaces
- **Base (60-70%):** Main fill
- **Shadow (15-20%):** Bottom-right edges and recessed areas

**How to generate tones from a base color:**
```
Highlight: HSV value +20%, saturation -10%
Base:      Original color
Shadow:    HSV value -25%, saturation +10%
Specular:  HSV value +35%, saturation -20% (tiny 1-2px spots)
```

Use `make_palette(base_rgb, n=4)` to auto-generate these.

**Application pattern for a rounded rectangle body:**
```
+--HHHHHH-------+
|HHHH           |
|HH             |
|               |
|               |
|            SSS|
|           SSSS|
+-------SSSSSSS+
H = highlight, S = shadow, blank = base
```

## 3. Dithering

Use checkerboard dithering to transition between two colors. At 64x64, dithering is subtle but effective for:
- Body-to-shadow transitions
- Belly/chest lighter areas fading into body color
- Blush marks (softer edge)

**Pattern:**
```
ABA     (1px dither band)
BAB

ABAB    (2px dither band — maximum for 64x64)
BABA
ABAB
BABA
```

**Rules:**
- Maximum 2 rows of dithering at 64x64 scale — more looks noisy
- Only dither between adjacent tones (highlight↔base or base↔shadow, never highlight↔shadow)
- Use `dither_rect()` or `dither_band()` from utility-functions.py

## 4. Palette Discipline

**Target: 8-16 unique colors per character** (excluding transparency and auto-outline).

A typical breakdown:
| Category | Colors | Example |
|----------|--------|---------|
| Body tones | 4 | highlight, light, base, shadow |
| Eye | 2-3 | pupil, iris, shine |
| Mouth/nose | 1-2 | mouth, blush |
| Accessory | 2-3 | main, light, dark |
| Limbs | 2 | base, shadow |
| Effects | 2-3 | star, exclamation, shadow |
| **Total** | **13-17** | |

**Rules:**
- Define ALL colors as named constants at script top
- Never use magic color tuples inline
- Related tones should be derived from the same base using `make_palette()`
- Reuse body shadow color for limbs when possible (reduces palette)

## 5. Eyes — The Soul

Eyes are the most expressive feature at any sprite size. At 64x64, you have roughly 6-8px per eye.

### Eye Styles

**Round (default character):**
```
 .XX.        Normal: 6x6 ellipse, 2px shine at top-left
 XXXX        Shine placement: (x+2, y+1) and (x+3, y+1)
 XXXX
 .XX.
```

**Cat/Slit (feline characters):**
```
 .XAA.       A = amber/iris color, X = pupil
 XAAAX       Vertical slit pupil with iris ring
 XAXAX
 XAAAX
 .XAA.
```

**Chibi/Dot (cute/simple characters):**
```
 XX          2x2 or 3x3 solid dots
 XX          Shine: 1px at top-left corner
```

### Eye States (all styles need these 4)

| State | Visual | Key feature |
|-------|--------|-------------|
| Normal | Round/open | Standard shine highlight |
| Closed | Horizontal line (2px tall) | Used in bow state |
| Alert | 20-30% larger than normal | Wider pupils, bigger shine |
| Happy | ^^ arcs or >< squints | No pupil visible, curved lines only |

### Shine Rules
- Always 2-3px of white at the same relative position (top-left of pupil)
- Consistent across ALL frames and states (except closed eyes)
- Shine creates the "alive" feeling — never omit it

## 6. Sub-Pixel Precision

At 64x64, each pixel is roughly 1.5pt when displayed at 96pt. Tiny details matter.

**Mouth patterns:**
```
Neutral:  ---     (3-4px horizontal line)
Happy:    v_v     (w-shape, 2 small dips)
Cat:      ω       (omega shape for feline characters)
Alert:    O       (2x3 or 3x3 ellipse)
Closed:   ..      (1-2px dots)
```

**Nose (optional, for animal characters):**
```
 .X.        Inverted triangle, 3-4px
 XX.
```

**Blush:**
```
 XXX        3x3 block, offset 11-14px from center
 XXX        Use a color slightly different from body (more pink/red)
 XXX        Optional: use 1px dither border for softer edge
```

## 7. Ground Shadow

Replace the single flat ellipse with layered gradient shadow.

**Layers (inside to outside):**
```
Layer 1 (inner):  width = base_w * 0.6,  alpha = 50
Layer 2 (mid):    width = base_w * 0.8,  alpha = 30
Layer 3 (outer):  width = base_w * 1.0,  alpha = 15
```

Use `gradient_shadow()` from utility-functions.py. Shadow should:
- Shrink when character jumps (happy state) — reduce width proportionally
- Stay at fixed Y position (does not follow body dy)
- Center align with character

## 8. Canvas Headroom

At 64x64, animation offsets (dy) can push the character near the canvas edge. If the body starts at y=0, a dy=-6 jump leaves no room for `auto_outline()` above the head — the top gets truncated.

**Rule: Start the body at y=9 (not y=6)**

This provides 9px of headroom above the body top, enough for:
- `auto_outline()` (1px)
- Maximum jump offset (dy=-6)
- Stars and decorations above the head

**Practical default Y positions (body top=9):**
| Element | Default Y | Notes |
|---------|-----------|-------|
| Body top | 9 | +3px from original 6 |
| Eyes (normal) | 19 | relative to body |
| Mouth | 28 | relative to body |
| Bowtie | 32 | below mouth |
| Hands (down) | 25 | at body sides |
| Feet | 41 | below body |
| Ground shadow | 50 | fixed, does not follow dy |

**Key insight:** The ground shadow stays at a fixed Y and does NOT follow dy — it shrinks when the character jumps up (happy state) to simulate distance.

## 9. Animation Consistency

Across all 4 frames of each state:
- Outline thickness must be identical (auto_outline handles this)
- Color palette must be exactly the same (no accidental color drift)
- Body proportions must not change (only position via dy offset)
- Accessories must move with the body (same dy)
- Eyes and mouth change expression, not size (except alert state)

## 10. Accessory Design

Accessories replace the default bowtie. Common patterns:

| Accessory | Technique | Size |
|-----------|-----------|------|
| Bowtie | Two triangles + center rectangle | ~16x8px |
| Cat ears | Two triangles above body top | ~12x10px each |
| Ribbon | Asymmetric bow (one large loop, one small) | ~14x8px |
| Hat | Rectangle/arc on top of body | ~20x8px |
| Scarf | Horizontal band across body + trailing end | ~24x6px |

Rules:
- Use 2-3 tones (same technique as body shading)
- Must move with body (accept dy parameter)
- Should not obscure eyes or mouth
- Keep within 64x64 canvas even at maximum dy offset

## 11. Symmetry

For symmetrical characters (most ClaudePet personas):
- Draw the left half, then mirror to right using `mirror_half()`
- Exceptions: accessories with asymmetric elements, raised hand animations
- Check symmetry in the preview — 1px misalignment is very visible at 4x zoom
