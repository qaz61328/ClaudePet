# Pixel Sprite Generator

Generate or improve 64x64 pixel art sprites for ClaudePet personas using Python + Pillow.

## When to Use

- `/pixel-sprite` — standalone invocation to create or improve sprites
- During `/create-persona` Step 3 — when generating the sprite script for a new persona
- When the user wants to refine an existing persona's appearance

## Required Reading

Before generating any sprite code, read these references:

1. [references/pixel-art-techniques.md] — pixel art theory and 64x64 best practices
2. [references/utility-functions.py] — ready-to-use Python utility functions

## Mandatory Techniques

Every sprite script you generate or improve MUST apply all of the following:

### 1. Auto-Outline (post-processing)
- After drawing all sprite components, apply `auto_outline()` from utility-functions.py
- Use **adaptive mode** (`color=None`) so each region gets an outline matching its own hue
- Use 8-connected mode (includes diagonals) for smoother outlines
- Use `alpha_threshold=128` (the default) to skip semi-transparent pixels like ground shadows
- For parts that overlap the body (hands in working state), use **inset outline** — see pixel-art-techniques.md §1b
- External limbs (hands at sides, feet) use plain fill — `auto_outline()` handles them

### 2. 3-Tone Shading
- Use `make_palette(base_rgb, n=4)` to generate highlight/light/base/shadow colors
- Apply consistently: highlight at top-left, shadow at bottom-right, base everywhere else
- Light source is always top-left

### 3. Palette Discipline
- Total unique colors per character: 8-16 (excluding transparency and outline)
- Define all colors as named constants at the top of the script
- Use `make_palette()` to derive related tones from a base color

### 4. Gradient Ground Shadow
- Replace single-ellipse shadows with `gradient_shadow()` from utility-functions.py
- 3 layers of decreasing opacity for soft, natural shadow

### 5. Eye Quality
- Eyes are the character's soul — follow the eye template guidelines in pixel-art-techniques.md
- Every eye style needs 4 variants: normal, closed, alert, happy
- Shine highlight must be consistent across all frames (same relative position)

### 6. Sub-Pixel Precision
- At 64x64, every pixel matters — mouth, nose, accessories must be pixel-perfect
- Use the dithering helper for color transitions wider than 2px

### 7. Canvas Headroom
- Start the body at **y=9** (not y=6) to leave room for auto_outline + max jump offset (dy=-6)
- Ground shadow stays at a **fixed Y** (does not follow dy), shrinks when character jumps
- See pixel-art-techniques.md §8 for the full Y-position reference table

## Workflow

### Mode A: New Persona Sprites (from `/create-persona` or standalone)

1. Ask for character concept if not already provided (appearance, colors, accessories)
2. Generate `generate_sprites.py` based on `scripts/generate_sprites.py` template in the project
3. Apply all mandatory techniques above
4. Include `auto_outline()` and other utility functions directly in the script (copy from utility-functions.py, do not import from external path)
5. Run the script to produce 20 PNGs
6. Generate 4x enlarged preview for visual check
7. Show preview path to user; iterate if requested

### Mode B: Improve Existing Sprites

1. Read the target persona's `generate_sprites.py`
2. Identify missing techniques (outline, shading depth, palette issues, shadow quality)
3. Apply improvements while preserving the character's design
4. Re-run to generate improved PNGs
5. Generate 4x preview for before/after comparison

## Script Structure Requirements

The generated `generate_sprites.py` must follow this structure:

```
1. Imports (PIL only)
2. Constants: SIZE, T (transparent), color palette
3. Utility functions (auto_outline, make_palette, gradient_shadow, etc.)
4. Drawing primitives (draw_body, draw_eyes_*, draw_mouth_*, etc.)
5. Animation state generators (gen_idle_1..4, gen_bow_1..4, etc.)
6. main() with output to script's own directory
```

Key rules:
- Output path: `os.path.dirname(os.path.abspath(__file__))` (same directory as the script)
- No preview or spritesheet in persona scripts (only the 20 PNGs)
- All 20 files: `{state}_{frame}.png` where state is idle/bow/alert/happy/working, frame is 1-4
- Apply `auto_outline()` to every frame before saving
- Canvas: 64x64 RGBA, transparent background

## Preview Generation

After generating sprites, always create a 4x enlarged preview:

```python
# In a separate one-off script or at the end of generate_sprites.py
for name, img in sprites.items():
    outlined = auto_outline(img, outline_color)
    outlined.resize((256, 256), Image.NEAREST).save(f"preview_{name}.png")
```

Show the preview directory path so the user can visually inspect the results.
