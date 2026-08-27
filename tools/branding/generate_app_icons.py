"""Generate deterministic OldGuida application icons from Pillow primitives."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

TEAL = "#138A83"
TEAL_DARK = "#075E59"
INK = "#163A3A"
WHITE = "#FFFFFF"
ITALY_GREEN = "#159447"
ITALY_RED = "#D83A3A"

ANDROID_LEGACY = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
ANDROID_FOREGROUND = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
IOS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}
MACOS = [16, 32, 64, 128, 256, 512, 1024]
WEB = {
    "Icon-192.png": 192,
    "Icon-512.png": 512,
    "Icon-maskable-192.png": 192,
    "Icon-maskable-512.png": 512,
}
WINDOWS_ICON_SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def draw_foreground(size: int) -> Image.Image:
    """Draw the transparent steering-wheel and open-book foreground glyph."""
    scale = 4
    canvas = Image.new("RGBA", (size * scale, size * scale), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    s = size * scale

    wheel_box = (int(0.25 * s), int(0.16 * s), int(0.75 * s), int(0.66 * s))
    draw.ellipse(wheel_box, outline=WHITE, width=int(0.065 * s))
    center = (int(0.50 * s), int(0.43 * s))
    for endpoint in (
        (int(0.31 * s), int(0.31 * s)),
        (int(0.69 * s), int(0.31 * s)),
        (int(0.50 * s), int(0.62 * s)),
    ):
        draw.line((center, endpoint), fill=WHITE, width=int(0.055 * s))
    draw.ellipse((int(0.43 * s), int(0.36 * s), int(0.57 * s), int(0.50 * s)), fill=TEAL_DARK)

    left_page = [
        (int(0.20 * s), int(0.59 * s)),
        (int(0.48 * s), int(0.53 * s)),
        (int(0.48 * s), int(0.82 * s)),
        (int(0.20 * s), int(0.75 * s)),
    ]
    right_page = [
        (int(0.52 * s), int(0.53 * s)),
        (int(0.80 * s), int(0.59 * s)),
        (int(0.80 * s), int(0.75 * s)),
        (int(0.52 * s), int(0.82 * s)),
    ]
    draw.polygon(left_page, fill=WHITE)
    draw.polygon(right_page, fill=WHITE)
    draw.line((int(0.50 * s), int(0.54 * s), int(0.50 * s), int(0.82 * s)), fill=INK, width=int(0.025 * s))

    marker_y = int(0.72 * s)
    for x, color in ((0.38, ITALY_GREEN), (0.48, WHITE), (0.58, ITALY_RED)):
        draw.rounded_rectangle(
            (int(x * s), marker_y, int((x + 0.06) * s), int(0.79 * s)),
            radius=int(0.012 * s),
            fill=color,
            outline=TEAL_DARK,
            width=max(1, int(0.006 * s)),
        )

    return canvas.resize((size, size), Image.Resampling.LANCZOS)


def draw_composite(size: int, rounded: bool = False) -> Image.Image:
    """Draw the foreground over the teal application-icon background."""
    if rounded:
        base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        inset = int(size * 0.05)
        ImageDraw.Draw(base).rounded_rectangle(
            (inset, inset, size - inset, size - inset),
            radius=int(size * 0.20),
            fill=TEAL,
        )
        base.alpha_composite(draw_foreground(size))
        return base

    base = Image.new("RGBA", (size, size), TEAL)
    base.alpha_composite(draw_foreground(size))
    return base.convert("RGB")


def draw_maskable(size: int) -> Image.Image:
    """Draw an opaque web icon whose glyph stays in the 60 percent safe zone."""
    base = Image.new("RGBA", (size, size), TEAL)
    glyph_size = int(size * 0.60)
    glyph = draw_foreground(glyph_size)
    offset = (size - glyph_size) // 2
    base.alpha_composite(glyph, (offset, offset))
    return base.convert("RGB")


def draw_adaptive_foreground(size: int) -> Image.Image:
    """Draw a transparent Android foreground within its 60 percent safe zone."""
    base = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    glyph_size = int(size * 0.60)
    glyph = draw_foreground(glyph_size)
    offset = (size - glyph_size) // 2
    base.alpha_composite(glyph, (offset, offset))
    return base


def save_png(image: Image.Image, path: Path) -> None:
    """Write a PNG, creating the destination directory as needed."""
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True)


def generate(root: Path) -> list[Path]:
    """Write every platform icon below *root* and return the written paths."""
    written: list[Path] = []

    master_path = root / "assets/branding/app_icon_master.png"
    foreground_path = root / "assets/branding/app_icon_foreground.png"
    save_png(draw_composite(2048), master_path)
    save_png(draw_foreground(2048), foreground_path)
    written.extend((master_path, foreground_path))

    for density, size in ANDROID_LEGACY.items():
        path = root / f"android/app/src/main/res/mipmap-{density}/ic_launcher.png"
        save_png(draw_composite(size), path)
        written.append(path)

    for density, size in ANDROID_FOREGROUND.items():
        path = root / f"android/app/src/main/res/mipmap-{density}/ic_launcher_foreground.png"
        save_png(draw_adaptive_foreground(size), path)
        written.append(path)

    ios_directory = root / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for filename, size in IOS.items():
        path = ios_directory / filename
        save_png(draw_composite(size), path)
        written.append(path)

    macos_directory = root / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in MACOS:
        path = macos_directory / f"app_icon_{size}.png"
        save_png(draw_composite(size, rounded=True), path)
        written.append(path)

    web_directory = root / "web/icons"
    for filename, size in WEB.items():
        path = web_directory / filename
        image = draw_maskable(size) if "maskable" in filename else draw_composite(size)
        save_png(image, path)
        written.append(path)

    favicon = root / "web/favicon.png"
    save_png(draw_composite(32), favicon)
    written.append(favicon)

    ico = root / "windows/runner/resources/app_icon.ico"
    ico.parent.mkdir(parents=True, exist_ok=True)
    draw_composite(256).save(ico, format="ICO", sizes=WINDOWS_ICON_SIZES)
    written.append(ico)
    return written


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path("."), help="project root for generated icons")
    arguments = parser.parse_args()
    for path in generate(arguments.root):
        print(path)


if __name__ == "__main__":
    main()
