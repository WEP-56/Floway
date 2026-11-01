"""Generate monochrome (white) Floway mark PNGs for Android notification/tile icons.

Notification small icons and QS tile icons are drawn as a white silhouette: the
system tints whatever alpha the drawable has. The branding PNG already carries
the mark as an alpha channel, so it is cropped, squared and downsampled.
"""

from PIL import Image

SRC = r"D:\FLVPcore\assets\branding\floway.png"
OUT = r"D:\FLVPcore\android\service\src\main\res"

# Density buckets: drawable size in px for a 24dp icon.
DENSITIES = {
    "mdpi": 24,
    "hdpi": 36,
    "xhdpi": 48,
    "xxhdpi": 72,
    "xxxhdpi": 96,
}

# The mark sits inside a 24dp box with a little breathing room.
PADDING_RATIO = 0.06


def main() -> None:
    image = Image.open(SRC).convert("RGBA")
    alpha = image.getchannel("A")

    bbox = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
    if bbox is None:
        raise SystemExit("no opaque pixels found")

    glyph = image.crop(bbox)
    side = max(glyph.size)
    padded = int(round(side * (1 + PADDING_RATIO * 2)))
    square = Image.new("RGBA", (padded, padded), (255, 255, 255, 0))
    square.paste(
        glyph,
        ((padded - glyph.width) // 2, (padded - glyph.height) // 2),
    )

    # Solid white silhouette: keep the alpha shape, drop the blue gradients.
    white = Image.new("RGBA", square.size, (255, 255, 255, 0))
    white.putalpha(square.getchannel("A"))

    for density, size in DENSITIES.items():
        resized = white.resize((size, size), Image.LANCZOS)
        path = f"{OUT}\\drawable-{density}\\ic_service.png"
        resized.save(path)
        print(f"{density}: {size}px -> {path}")

    # The Documents provider shows the icon in colour, not tinted.
    for density, size in DENSITIES.items():
        resized = square.resize((size, size), Image.LANCZOS)
        path = f"{OUT}\\drawable-{density}\\ic_documents.png"
        resized.save(path)
        print(f"{density}: {size}px -> {path}")


if __name__ == "__main__":
    main()
