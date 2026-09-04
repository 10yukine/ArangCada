# -*- coding: utf-8 -*-
"""Generates Android launcher icon assets from the supplied brand mark.

Third pass. History matters here because two earlier attempts each fixed
one half and broke the other:

- Pass 1 computed its own safe-zone fit from the mark's raw bounding box.
  It respected the safe zone but re-centered the asymmetric C+A lockup
  *geometrically*, throwing away the designer's optical centering.
- Pass 2 rendered the designer's reference composition verbatim. It kept
  optical centering but ignored the safe zone entirely, so Android cropped
  the mark. Its "circular mask check" masked the full 108dp canvas instead
  of the inner 72dp a launcher actually reveals, so the crop never showed
  up in verification.

This pass does both. It takes the designer's exact 1024x1024 composition
(`translate(175.87 -54.6) scale(0.873)`, from the supplied "ArangCada Icon
Organic" reference) and scales that whole square down about its own centre
until the mark's bounding box fits Android's 66dp safe circle. Scaling the
entire canvas uniformly preserves every relative position the designer
chose, including the deliberate off-centre offset that makes the lockup
read as balanced.

Measured on the reference: the mark's furthest bbox corner sits 0.473 of
the canvas from centre, against a 0.306 safe-zone radius, hence the ~0.65
scale below.
"""
import re

import pymupdf
from PIL import Image, ImageDraw

REFERENCE_SVG = "assets/branding/arangcada_app_icon_organic.svg"
MONOCHROME_SVG = "assets/branding/arangcada_icon_monochrome_1024.svg"
BG_HEX = "#1262D0"
CREAM_HEX = "#F2F8FF"

# Android adaptive icon geometry, in dp on the 108dp layer.
LAYER_DP = 108.0
SAFE_DIAMETER_DP = 66.0  # guaranteed-visible content circle
MASK_DIAMETER_DP = 72.0  # what a launcher mask actually reveals
SAFE_RADIUS_RATIO = (SAFE_DIAMETER_DP / 2) / LAYER_DP  # 0.3056

ADAPTIVE_DENSITIES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}
LEGACY_DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
RES_DIR = "android/app/src/main/res"


def make_monochrome_reference():
    """The same 1024x1024 composition with the background rect dropped and
    the mark flattened to one light tone, so it reads against the Brand Blue
    background layer. Position and scale are otherwise untouched -- the
    two-tone original made the accent letterform nearly vanish once it shared
    a hue with the background."""
    s = open(REFERENCE_SVG, encoding="utf-8").read()
    s = re.sub(r"<rect[^>]*></rect>\s*", "", s, count=1)
    # Match whatever single fill the reference currently carries. Hardcoding
    # the old cream hex here meant the monochrome layer silently stopped being
    # rewritten the moment the brand palette moved.
    s = re.sub(r'fill="#[0-9a-fA-F]{6}"', f'fill="{CREAM_HEX}"', s, count=1)
    open(MONOCHROME_SVG, "w", encoding="utf-8").write(s)


def hex_to_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def render_svg(path, px):
    doc = pymupdf.open(path)
    page = doc[0]
    zoom = px / page.rect.width
    pix = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=True)
    mode = "RGBA" if pix.alpha else "RGB"
    return Image.frombytes(mode, (pix.width, pix.height), pix.samples).convert(
        "RGBA"
    )


def safe_zone_scale():
    """How far the whole composition must shrink for the mark's bbox to fit
    the safe circle. Measured, not assumed."""
    probe = render_svg(MONOCHROME_SVG, 1024)
    bbox = probe.getchannel("A").getbbox()
    w, h = probe.size
    cx, cy = w / 2, h / 2
    corners = [
        (bbox[0], bbox[1]),
        (bbox[2], bbox[1]),
        (bbox[0], bbox[3]),
        (bbox[2], bbox[3]),
    ]
    radius = max(((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 for x, y in corners)
    ratio = radius / w
    scale = SAFE_RADIUS_RATIO / ratio
    print(
        f"Mark bbox radius {ratio:.3f} of canvas vs {SAFE_RADIUS_RATIO:.3f} "
        f"safe radius -> scaling composition to {scale:.3f}"
    )
    return scale


def foreground_layer(px, scale):
    """Transparent 108dp-equivalent canvas holding the designer's whole
    composition, scaled about the centre so it clears the safe zone."""
    canvas = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    inner_px = max(1, round(px * scale))
    mark = render_svg(MONOCHROME_SVG, inner_px)
    offset = (px - inner_px) // 2
    canvas.alpha_composite(mark, (offset, offset))
    return canvas


def legacy_icon(px):
    """Pre-API-26 icons are shown as authored, with no adaptive mask, so
    the reference composition (rounded rect background included) is used
    whole -- no safe-zone inset needed or wanted."""
    return render_svg(REFERENCE_SVG, px).convert("RGB")


def mask_preview(px, scale, out_path):
    """Simulates what a launcher actually reveals: the inner 72dp circle of
    the 108dp layer, NOT the whole canvas. Getting this wrong is exactly
    how pass 2 shipped a cropped icon that looked fine in review."""
    fg = foreground_layer(px, scale)
    bg = Image.new("RGBA", (px, px), hex_to_rgb(BG_HEX) + (255,))
    bg.alpha_composite(fg)

    mask_px = px * (MASK_DIAMETER_DP / LAYER_DP)
    inset = (px - mask_px) / 2
    mask = Image.new("L", (px, px), 0)
    ImageDraw.Draw(mask).ellipse(
        (inset, inset, px - inset, px - inset), fill=255
    )
    out = Image.new("RGBA", (px, px), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)
    out.save(out_path)


def main():
    make_monochrome_reference()
    scale = safe_zone_scale()

    for suffix, px in ADAPTIVE_DENSITIES.items():
        img = foreground_layer(px, scale)
        path = f"{RES_DIR}/mipmap-{suffix}/ic_launcher_foreground.png"
        img.save(path)
        print("wrote", path, img.size)

    for suffix, px in LEGACY_DENSITIES.items():
        img = legacy_icon(px)
        path = f"{RES_DIR}/mipmap-{suffix}/ic_launcher.png"
        img.save(path)
        print("wrote", path, img.size)

    store_icon = legacy_icon(512)
    store_icon.save("assets/branding/play_store_icon_512.png")
    print("wrote assets/branding/play_store_icon_512.png", store_icon.size)

    mask_preview(432, scale, "preview_launcher_mask.png")
    print("wrote preview_launcher_mask.png (inner 72dp circle, as shipped)")


if __name__ == "__main__":
    main()
