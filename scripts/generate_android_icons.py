# -*- coding: utf-8 -*-
"""Generates Android launcher icon assets from the supplied brand mark.

Applies the two guides the user asked for, translated to what this project
actually ships (Android only -- no iOS platform target exists in this
Flutter project):

- Android/Play Store adaptive icon spec: separate foreground + background
  layers, foreground content kept inside the ~66dp safe zone of a 108dp
  canvas so it isn't clipped by circle/squircle/rounded-square launcher
  masks. No baked-in rounded corners or shadow -- the system applies its
  own mask, and Apple's parallel guidance (full-bleed square, no baked
  shadow/gloss) is the same principle, applied here since this project has
  no iOS target to apply it to directly.
- Uses the existing `arangcada_icon.svg` mark (already the single source
  used everywhere else in the app -- login, splash, about) rather than
  re-deriving the mark from the two new reference SVGs, so the launcher
  icon and every in-app logo trace back to the same artwork per CLAUDE.md's
  "do not redraw the mark" rule.
- Background color (#C67139) matches the two reference SVGs the user
  supplied, not the in-app AppColors.primary button color (#B4552F) -- the
  reference assets are the explicit brand decision for the icon specifically.
"""
import math
import pymupdf
from PIL import Image

MARK_SVG = "assets/branding/arangcada_icon_monochrome.svg"
MARK_VIEWBOX = (752.0, 1117.0)  # width, height, from the SVG's own viewBox
BG_HEX = "#C67139"

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

RES_DIR = "android/app/src/main/res"  # run from apps/mobile/

aspect = MARK_VIEWBOX[0] / MARK_VIEWBOX[1]  # width / height
CANVAS_UNITS = 108.0
SAFE_RADIUS = 33.0
mark_height_units = (2 * SAFE_RADIUS) / math.sqrt(1 + aspect**2)
mark_width_units = mark_height_units * aspect
print(
    f"Safe-zone fit: mark {mark_width_units:.1f}x{mark_height_units:.1f} "
    f"of {CANVAS_UNITS:.0f} canvas units "
    f"({mark_height_units / CANVAS_UNITS:.1%} of canvas height)"
)

_doc = pymupdf.open(MARK_SVG)
_page = _doc[0]


def render_mark_png(px_width: int) -> Image.Image:
    px_height = round(px_width / aspect)
    zoom_x = px_width / _page.rect.width
    zoom_y = px_height / _page.rect.height
    pix = _page.get_pixmap(
        matrix=pymupdf.Matrix(zoom_x, zoom_y), alpha=True
    )
    mode = "RGBA" if pix.alpha else "RGB"
    img = Image.frombytes(mode, (pix.width, pix.height), pix.samples)
    return img.convert("RGBA")


def foreground_layer(canvas_px: int) -> Image.Image:
    canvas = Image.new("RGBA", (canvas_px, canvas_px), (0, 0, 0, 0))
    mark_px_width = round(canvas_px * (mark_width_units / CANVAS_UNITS))
    mark = render_mark_png(mark_px_width)
    x = (canvas_px - mark.width) // 2
    y = (canvas_px - mark.height) // 2
    canvas.alpha_composite(mark, (x, y))
    return canvas


def hex_to_rgb(hex_color: str):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i : i + 2], 16) for i in (0, 2, 4))


def legacy_icon(canvas_px: int) -> Image.Image:
    canvas = Image.new("RGBA", (canvas_px, canvas_px), hex_to_rgb(BG_HEX) + (255,))
    mark_px_width = round(canvas_px * (mark_width_units / CANVAS_UNITS) * 1.15)
    mark = render_mark_png(mark_px_width)
    x = (canvas_px - mark.width) // 2
    y = (canvas_px - mark.height) // 2
    canvas.alpha_composite(mark, (x, y))
    return canvas.convert("RGB")


def main():
    for suffix, px in ADAPTIVE_DENSITIES.items():
        out_dir = f"{RES_DIR}/mipmap-{suffix}"
        img = foreground_layer(px)
        img.save(f"{out_dir}/ic_launcher_foreground.png")
        print("wrote", f"{out_dir}/ic_launcher_foreground.png", img.size)

    for suffix, px in LEGACY_DENSITIES.items():
        out_dir = f"{RES_DIR}/mipmap-{suffix}"
        img = legacy_icon(px)
        img.save(f"{out_dir}/ic_launcher.png")
        print("wrote", f"{out_dir}/ic_launcher.png", img.size)

    store_icon = legacy_icon(512)
    store_icon.save("assets/branding/play_store_icon_512.png")
    print("wrote assets/branding/play_store_icon_512.png", store_icon.size)


if __name__ == "__main__":
    main()
