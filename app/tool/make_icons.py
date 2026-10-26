"""Draw the app icon (the logo mark on the midnight canvas) into app/brand/.

    pip install pillow
    python tool/make_icons.py

The PNGs are committed, so this only needs re-running if the mark changes.
`patch_web.py` and `patch_android.py` copy them into the generated projects.
"""
import pathlib

from PIL import Image, ImageDraw, ImageFilter

OUT = pathlib.Path(__file__).resolve().parent.parent / "brand"
MIDNIGHT = (5, 6, 15)
ICE, ICE_DEEP = (216, 236, 248), (152, 192, 239)
S = 1024  # drawn large, then scaled down for clean edges


def mark(scale):
    """The mark alone on a transparent square: a glass disc with three rising columns."""
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    r = S * 0.5 * scale
    c = S / 2
    d.ellipse((c - r, c - r, c + r, c + r), fill=(186, 214, 247, 24), outline=(186, 215, 247, 90), width=int(S * 0.012))
    # three rising columns (the same shape as the in-app logo), each with the
    # ice -> sky gradient; u converts the logo's 30-unit grid to pixels
    u = r / 15
    for x, h in ((8.6, 6), (13.3, 9.5), (18, 13)):
        x0, x1 = c - r + x * u, c - r + (x + 3.4) * u
        y1 = c - r + 21.5 * u
        y0 = y1 - h * u
        grad = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        gd = ImageDraw.Draw(grad)
        for i in range(int(y1 - y0) + 1):
            t = i / (y1 - y0)  # top is sky blue, bottom is ice
            col = tuple(int(ICE_DEEP[k] * (1 - t) + ICE[k] * t) for k in range(3)) + (255,)
            gd.line((x0, y0 + i, x1, y0 + i), fill=col)
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle((x0, y0, x1, y1), 1.7 * u, fill=255)
        im.paste(grad, (0, 0), mask)
    return im


def canvas(rounded, scale):
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    bg = Image.new("RGBA", (S, S), MIDNIGHT + (255,))
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((S * 0.1, -S * 0.5, S * 0.9, S * 0.45), fill=(124, 145, 182, 110))
    bg.alpha_composite(glow.filter(ImageFilter.GaussianBlur(S * 0.09)))
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), S * 0.22 if rounded else 0, fill=255)
    base.paste(bg, (0, 0), mask)
    base.alpha_composite(mark(scale))
    return base


def save(im, name, size):
    path = OUT / name
    path.parent.mkdir(parents=True, exist_ok=True)
    im.resize((size, size), Image.LANCZOS).save(path, optimize=True)
    print("wrote", path.relative_to(OUT.parent))


round_icon = canvas(True, 0.80)
full_icon = canvas(False, 0.58)  # maskable: content stays inside the safe zone

save(round_icon, "favicon.png", 64)
save(round_icon, "Icon-192.png", 192)
save(round_icon, "Icon-512.png", 512)
save(full_icon, "Icon-maskable-192.png", 192)
save(full_icon, "Icon-maskable-512.png", 512)
for folder, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
    save(round_icon, f"android/mipmap-{folder}/ic_launcher.png", px)
