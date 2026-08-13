#!/usr/bin/env python3
"""Generate Favorites collection artwork for every shipped RetroFE layout.

Each layout draws a system's menu entry from files under
collections/<System>/system_artwork/. The Favorites collection needs the same
files, so this renders a star mark plus a FAVORITES wordmark at whatever sizes
and filenames a given layout already uses for its other systems, in that
layout's own font and sampled from its own palette.
"""

import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

USAGE = "usage: gen-favorites-artwork.py <layouts-dir>\n\n" \
        "  e.g. FunKey/board/funkey/rootfs-overlay/usr/games/layouts\n"

# Star gold, kept constant across layouts: it is the one colour that reads as
# "favorite" regardless of the surrounding theme.
GOLD_LIGHT = (255, 214, 92)
GOLD_DARK = (240, 156, 18)
GOLD_EDGE = (140, 84, 6)

SS = 4  # supersampling factor for smooth edges at these small sizes


def star_polygon(cx, cy, outer, inner, points=5, rotation=-math.pi / 2):
    pts = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = rotation + i * math.pi / points
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def draw_star(size, radius, center=None, glow=True):
    """Return an RGBA image of a gold star, supersampled then downscaled."""
    w, h = size
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    cx, cy = center if center is not None else (w / 2, h / 2)
    cx, cy = cx * SS, cy * SS
    r = radius * SS

    if glow:
        halo = Image.new("RGBA", img.size, (0, 0, 0, 0))
        ImageDraw.Draw(halo).polygon(
            star_polygon(cx, cy, r * 1.18, r * 0.5), fill=GOLD_DARK + (70,)
        )
        halo = halo.filter(ImageFilter.GaussianBlur(radius=r * 0.12))
        img = Image.alpha_composite(img, halo)
        d = ImageDraw.Draw(img)

    # Body, then a lighter inner star to fake a top-lit gradient.
    d.polygon(star_polygon(cx, cy, r, r * 0.44), fill=GOLD_DARK,
              outline=GOLD_EDGE, width=max(1, int(r * 0.045)))
    d.polygon(star_polygon(cx, cy - r * 0.06, r * 0.72, r * 0.32), fill=GOLD_LIGHT)

    return img.resize((w, h), Image.LANCZOS)


_FONT_CACHE = {}


def load_font(path, size):
    # The fitting loop below asks for ~80 sizes per wordmark; without this that
    # is 80 reads and parses of the same file.
    key = (path, size)
    if key not in _FONT_CACHE:
        font = ImageFont.load_default()
        for candidate in (path, "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
            if candidate and os.path.exists(candidate):
                try:
                    font = ImageFont.truetype(candidate, size)
                    break
                except OSError:
                    continue
        _FONT_CACHE[key] = font
    return _FONT_CACHE[key]


def text_size(d, text, font, tracking=0):
    """Width by advance, height by ink.

    Advancing by the glyph's ink extent would drop the side bearings the font
    builds into each character, packing the letters together; the tracking here
    is meant to open the wordmark up, not to replace the font's own spacing.
    Height stays ink-based because it is used to centre the strip vertically.
    """
    if not text:
        return 0, 0
    total = 0
    height = 0
    for ch in text:
        total += d.textlength(ch, font=font) + tracking
        box = d.textbbox((0, 0), ch, font=font)
        height = max(height, box[3] - box[1])
    return total - tracking, height


def draw_tracked_text(d, xy, text, font, fill, tracking=0):
    # Must advance exactly as text_size measures, or the centring drifts.
    x, y = xy
    for ch in text:
        d.text((x, y), ch, font=font, fill=fill)
        x += d.textlength(ch, font=font) + tracking


def wordmark(size, fontpath, color, text="FAVORITES", pad=2, shadow=None):
    """Render the wordmark to fill a wide, short strip."""
    w, h = size
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Grow the point size until the tracked text just fits the strip.
    best, best_track = None, 0
    for pt in range(4, h * SS * 2):
        f = load_font(fontpath, pt)
        track = max(1, pt // 12)
        tw, th = text_size(d, text, f, track)
        if tw > (w - pad * 2) * SS or th > (h - pad) * SS:
            break
        best, best_track = f, track
    if best is None:
        best = load_font(fontpath, 8)

    tw, th = text_size(d, text, best, best_track)
    box = d.textbbox((0, 0), text, font=best)
    x = (w * SS - tw) / 2
    y = (h * SS - th) / 2 - box[1]

    if shadow:
        draw_tracked_text(d, (x + SS, y + SS), text, best, shadow, best_track)
    draw_tracked_text(d, (x, y), text, best, color, best_track)

    return img.resize((w, h), Image.LANCZOS)


def sample_palette(theme_dir):
    """Average colour of the layout's existing backgrounds, for the gradient."""
    base = os.path.join(theme_dir, "collections")
    samples = []
    if os.path.isdir(base):
        # Skip our own output, or a second run samples the backgrounds the
        # first run wrote and the palette drifts a little further every time.
        systems = [s for s in sorted(os.listdir(base)) if s != "Favorites"]

        for system in systems[:6]:
            for name in ("bg.png", "system_bg.png", "screenshot.png"):
                p = os.path.join(base, system, "system_artwork", name)
                if os.path.exists(p):
                    try:
                        im = Image.open(p).convert("RGB").resize((16, 16))
                    except OSError:
                        continue
                    samples.extend(im.getdata())
    if not samples:
        return (24, 24, 28)
    n = len(samples)
    avg = tuple(sum(c[i] for c in samples) // n for i in range(3))
    # Darken so the menu text on top stays readable.
    return tuple(max(8, int(v * 0.55)) for v in avg)


def background(size, base, fontpath):
    w, h = size
    img = Image.new("RGB", (w, h), base)
    d = ImageDraw.Draw(img)

    top = tuple(min(255, int(v * 1.7) + 12) for v in base)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(
            int(top[i] * (1 - t) + base[i] * t) for i in range(3)))

    # Faint star watermark so the page reads as Favorites even behind the menu.
    mark = draw_star((w, h), radius=w * 0.30, center=(w * 0.5, h * 0.42), glow=False)
    mark.putalpha(mark.getchannel("A").point(lambda a: int(a * 0.16)))
    img = Image.alpha_composite(img.convert("RGBA"), mark).convert("RGB")

    return img


def tile(size, fontpath, label_color, with_label=True):
    """The big square art: star above, wordmark below, transparent ground."""
    w, h = size
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    if with_label:
        star_r = w * 0.30
        star = draw_star((w, h), radius=star_r, center=(w / 2, h * 0.40))
        img = Image.alpha_composite(img, star)

        strip_h = max(12, int(h * 0.13))
        mark = wordmark((int(w * 0.86), strip_h), fontpath, label_color,
                        shadow=(0, 0, 0, 160))
        img.alpha_composite(mark, (int(w * 0.07), int(h * 0.76)))
    else:
        star = draw_star((w, h), radius=w * 0.36, center=(w / 2, h / 2))
        img = Image.alpha_composite(img, star)

    return img


# filename -> (kind, size). kind: tile | wide | background | wordmark
THEMES = {
    "Artbook-sml":    {"font": "Gilroy-Bold.ttf",     "files": {"device_W240.png": ("tile", (240, 240)), "bg.png": ("background", (240, 240))}},
    "Daijismol":      {"font": "Gilroy-Bold.ttf",     "files": {"device_W240.png": ("tile", (240, 240)), "bg.png": ("background", (240, 240))}},
    "DarkUI":         {"font": "Gilroy-Bold.ttf",     "files": {"device_W240.png": ("tile", (240, 240)), "bg.png": ("background", (240, 240))}},
    "GameBoy":        {"font": "Gilroy-Bold.ttf",     "files": {"device_W240.png": ("tile", (240, 240)), "bg.png": ("background", (240, 240))}},
    "PixxelPlus":     {"font": "markpro-bold.ttf",     "files": {"device_W240.png": ("tile", (240, 240)), "bg.png": ("background", (240, 240))}},
    "RetroRoomCovers": {"font": "Gilroy-Bold.ttf",    "files": {"device_W240.png": ("tile", (240, 240)), "bg.png": ("background", (240, 240))}},
    "Classic":        {"font": "Roboto-Bold.ttf",     "files": {"device.png": ("tile", (256, 256)), "fallback.png": ("tile", (256, 256)), "logo.png": ("wordmark", (103, 20)), "system.png": ("wordmark", (108, 20))}},
    "Flat":           {"font": "Cabin-Bold-TTF.ttf",  "files": {"device.png": ("tile", (256, 256)), "fallback.png": ("tile", (256, 256)), "logo.png": ("wordmark", (103, 20)), "logo_h20.png": ("wordmark", (139, 20)), "system_bg.png": ("background", (240, 240))}},
    "FunKey":         {"font": "OpenSans-Bold.ttf",   "files": {"device.png": ("tile", (256, 256)), "fallback.png": ("tile", (256, 256)), "device_W140.png": ("tile", (140, 140)), "logo.png": ("wordmark", (103, 20))}},
    "FunKeyRed":      {"font": "OpenSans-Bold.ttf",   "files": {"device.png": ("tile", (256, 256)), "fallback.png": ("tile", (256, 256)), "device_W140.png": ("tile", (140, 140)), "logo.png": ("wordmark", (103, 20))}},
    "FunKeyYellow":   {"font": "OpenSans-Bold.ttf",   "files": {"device.png": ("tile", (256, 256)), "fallback.png": ("tile", (256, 256)), "device_W140.png": ("tile", (140, 140)), "logo.png": ("wordmark", (103, 20))}},
    "Superlopez":     {"font": "Roboto-Bold.ttf",     "files": {"fallback.png": ("tile", (256, 256)), "screenshot.png": ("background", (240, 240)), "system.png": ("wordmark", (108, 20))}},
    "TFT":            {"font": "Cabin-Bold-TTF.ttf",  "files": {"device.png": ("tile", (256, 256)), "fallback.png": ("tile", (256, 256)), "controller_h120.png": ("wide", (205, 120)), "logo.png": ("wordmark", (103, 20)), "logo_h20.png": ("wordmark", (90, 20))}},
}


def main():
    # Exit rather than default to the working directory: silently rendering 41
    # files into the wrong tree is worse than being told the argument is needed.
    if len(sys.argv) != 2:
        sys.stderr.write(USAGE)
        return 2

    layouts = os.path.abspath(sys.argv[1])
    if not os.path.isdir(layouts):
        sys.stderr.write("not a directory: %s\n" % layouts)
        return 2

    made = 0
    for theme, spec in sorted(THEMES.items()):
        theme_dir = os.path.join(layouts, theme)
        if not os.path.isdir(theme_dir):
            print(f"  !! missing theme {theme}")
            continue

        fontpath = os.path.join(theme_dir, spec["font"])
        if not os.path.exists(fontpath):
            fontpath = None

        out = os.path.join(theme_dir, "collections", "Favorites", "system_artwork")
        os.makedirs(out, exist_ok=True)

        base = sample_palette(theme_dir)
        # Wordmarks sit on the theme's own chrome; white with a shadow is the
        # safest reading on every one of these layouts.
        label = (255, 255, 255, 255)

        for name, (kind, size) in sorted(spec["files"].items()):
            path = os.path.join(out, name)
            if kind == "tile":
                img = tile(size, fontpath, label)
            elif kind == "wide":
                img = tile(size, fontpath, label, with_label=False)
            elif kind == "background":
                img = background(size, base, fontpath)
            elif kind == "wordmark":
                img = wordmark(size, fontpath, label, shadow=(0, 0, 0, 150))
            img.save(path)
            made += 1

        print(f"  {theme:16s} font={spec['font'] if fontpath else 'DejaVu(fallback)':22s} "
              f"bg={base} files={len(spec['files'])}")

    print(f"\nGenerated {made} files.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
