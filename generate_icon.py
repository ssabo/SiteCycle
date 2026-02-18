#!/usr/bin/env python3
"""Generate SiteCycle app icon - 1024x1024 PNG.

Design: location pin (the "site") centered inside two circular
rotation arrows (the "cycle") on a deep teal background.
"""

from PIL import Image, ImageDraw
import math

RENDER_SIZE = 2048   # Draw at 2x then downsample for smooth edges
OUTPUT_SIZE  = 1024


def sc(x):
    """Scale a value from 1024-space to render-space."""
    return int(x * RENDER_SIZE / OUTPUT_SIZE)


def pt(cx, cy, r, deg):
    """Point on circle at PIL angle deg (0=right, increases clockwise)."""
    rad = math.radians(deg)
    return (cx + r * math.cos(rad), cy + r * math.sin(rad))


def arrowhead(draw, tip, point_deg, size, color):
    """Filled triangular arrowhead.

    tip        – (x, y) apex of the arrow
    point_deg  – PIL angle the tip points toward
    size       – length from base to tip
    """
    rad  = math.radians(point_deg)
    perp = math.radians(point_deg + 90)
    tx, ty = tip
    bx = tx - size * math.cos(rad)
    by = ty - size * math.sin(rad)
    hw = size * 0.58
    b1 = (bx + hw * math.cos(perp), by + hw * math.sin(perp))
    b2 = (bx - hw * math.cos(perp), by - hw * math.sin(perp))
    draw.polygon([tip, b1, b2], fill=color)


def main():
    S  = RENDER_SIZE
    CX = S // 2
    CY = S // 2

    # ── Canvas ──────────────────────────────────────────────────────────
    img  = Image.new('RGBA', (S, S), (20, 108, 128, 255))
    draw = ImageDraw.Draw(img)

    # ── Background ──────────────────────────────────────────────────────
    # Deep medical teal
    BG = (20, 108, 128)
    draw.rounded_rectangle([0, 0, S - 1, S - 1], radius=sc(200), fill=BG)

    # Subtle lighter-center radial highlight to suggest depth
    for i in range(10):
        r_val = S // 2 - i * (S // 22)
        alpha = 5 + i * 2
        overlay = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        od = ImageDraw.Draw(overlay)
        od.ellipse([CX - r_val, CY - r_val, CX + r_val, CY + r_val],
                   fill=(255, 255, 255, alpha))
        img = Image.alpha_composite(img, overlay)

    draw = ImageDraw.Draw(img)

    # ── Cycle arrows ────────────────────────────────────────────────────
    # Two curved arcs forming a clockwise rotation ring around the pin.
    # PIL angle convention: 0° = 3 o'clock, increases clockwise (Y-down).
    #   270° = 12 o'clock (top)
    #    90° = 6 o'clock  (bottom)
    A_CX    = CX
    A_CY    = CY
    A_R     = sc(270)
    A_W     = sc(62)
    A_COLOR = (255, 255, 255, 228)

    GAP = 22   # degrees of gap at each endpoint (room for arrowheads)

    # Arc 1 – upper semicircle: lower-left → top → upper-right
    a1_s, a1_e = 180 + GAP, 360 - GAP   # 202° → 338°

    # Arc 2 – lower semicircle: upper-right → bottom → lower-left
    a2_s, a2_e = GAP, 180 - GAP          # 22°  → 158°

    bbox = [A_CX - A_R, A_CY - A_R, A_CX + A_R, A_CY + A_R]
    draw.arc(bbox, start=a1_s, end=a1_e, fill=A_COLOR, width=A_W)
    draw.arc(bbox, start=a2_s, end=a2_e, fill=A_COLOR, width=A_W)

    # Arrowheads at the clockwise endpoint of each arc.
    # Clockwise tangent direction at PIL angle θ  ≈  θ + 90°.
    tip1 = pt(A_CX, A_CY, A_R, a1_e)
    arrowhead(draw, tip1, a1_e + 90, sc(85), A_COLOR)

    tip2 = pt(A_CX, A_CY, A_R, a2_e)
    arrowhead(draw, tip2, a2_e + 90, sc(85), A_COLOR)

    # ── Location pin ────────────────────────────────────────────────────
    # Classic teardrop pin: circle head + downward triangular tail.
    # The head sits above centre; the tail tip stays well within the arrow ring.
    PIN_CX = CX
    PIN_CY = CY - sc(52)    # head centre, shifted above middle
    PIN_R  = sc(118)        # head radius

    WHITE      = (255, 255, 255, 255)
    tail_tip_y = int(PIN_CY + PIN_R + sc(132))

    # Draw tail first, then head on top for a clean teardrop silhouette
    draw.polygon([
        (PIN_CX - PIN_R, PIN_CY),
        (PIN_CX + PIN_R, PIN_CY),
        (PIN_CX,         tail_tip_y)
    ], fill=WHITE)

    draw.ellipse([
        PIN_CX - PIN_R, PIN_CY - PIN_R,
        PIN_CX + PIN_R, PIN_CY + PIN_R
    ], fill=WHITE)

    # Inner dot — teal, representing the actual injection site
    INNER_R = sc(48)
    draw.ellipse([
        PIN_CX - INNER_R, PIN_CY - INNER_R,
        PIN_CX + INNER_R, PIN_CY + INNER_R
    ], fill=BG)

    # ── Downsample (2x → 1x) for smooth anti-aliased edges ─────────────
    img = img.resize((OUTPUT_SIZE, OUTPUT_SIZE), Image.LANCZOS)

    # ── Flatten to RGB (App Store rejects icons with alpha channel) ────
    rgb_img = Image.new('RGB', img.size, BG)
    rgb_img.paste(img, mask=img.split()[3])
    img = rgb_img

    # ── Save ────────────────────────────────────────────────────────────
    out = ('SiteCycle/Assets.xcassets'
           '/AppIcon.appiconset/AppIcon.png')
    img.save(out, 'PNG')
    print(f"Saved {OUTPUT_SIZE}×{OUTPUT_SIZE} icon → {out}")


if __name__ == '__main__':
    main()
