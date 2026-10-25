"""Compose the README hero image from the screenshots in docs/img.

    pip install pillow
    python e2e/make_hero.py              # reads and writes docs/img

A desktop dashboard with two phone screens in front of it, on the same
midnight canvas the app uses.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

IMG = sys.argv[1] if len(sys.argv) > 1 else "docs/img"
W, H = 2000, 1150
MIDNIGHT = (5, 6, 15)


def rounded(im, radius):
    im = im.convert("RGBA")
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width - 1, im.height - 1), radius, fill=255)
    out = Image.new("RGBA", im.size, (0, 0, 0, 0))
    out.paste(im, (0, 0), mask)
    # a hairline edge, like the glass cards
    ImageDraw.Draw(out).rounded_rectangle(
        (0, 0, im.width - 1, im.height - 1), radius, outline=(186, 215, 247, 70), width=2)
    return out


def with_shadow(canvas, im, pos, blur=40, offset=(0, 30), alpha=150):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    box = Image.new("RGBA", im.size, (0, 0, 0, alpha))
    shadow.paste(box, (pos[0] + offset[0], pos[1] + offset[1]), im.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow)
    canvas.alpha_composite(im, pos)


def spotlight():
    """Canvas with the soft glow that sits behind the hero."""
    glow = Image.new("RGBA", (W, H), MIDNIGHT + (255,))
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse((W * 0.18, -H * 0.45, W * 0.82, H * 0.55), fill=(124, 145, 182, 95))
    layer = layer.filter(ImageFilter.GaussianBlur(160))
    glow.alpha_composite(layer)
    grid = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(grid)
    for x in range(0, W, 100):
        d.line((x, 0, x, H), fill=(186, 215, 247, 14))
    for y in range(0, H, 100):
        d.line((0, y, W, y), fill=(186, 215, 247, 14))
    glow.alpha_composite(grid)
    return glow


def load(name):
    return Image.open(os.path.join(IMG, name))


canvas = spotlight()

desktop = load("dashboard.png")
desktop = desktop.resize((1300, int(desktop.height * 1300 / desktop.width)), Image.LANCZOS)
with_shadow(canvas, rounded(desktop, 22), (50, 160))

for name, x, y, height in (("phone-dashboard.png", 1395, 110, 900), ("phone-expenses.png", 1600, 250, 800)):
    phone = load(name)
    phone = phone.resize((int(phone.width * height / phone.height), height), Image.LANCZOS)
    with_shadow(canvas, rounded(phone, 46), (x, y), blur=50, offset=(0, 40), alpha=190)

out = os.path.join(IMG, "hero.png")
canvas.convert("RGB").save(out, optimize=True)
print("wrote", out, canvas.size)
