import math
import os
import struct
import zlib


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def blend(dst, src):
    sr, sg, sb, sa = src
    if sa <= 0:
        return dst
    if sa >= 255:
        return (sr, sg, sb, 255)
    dr, dg, db, da = dst
    a = sa / 255
    inv = 1 - a
    return (
        round(sr * a + dr * inv),
        round(sg * a + dg * inv),
        round(sb * a + db * inv),
        255,
    )


def lerp(a, b, t):
    return round(a + (b - a) * t)


def mix(c1, c2, t):
    return tuple(lerp(c1[i], c2[i], t) for i in range(3)) + (255,)


def set_px(pixels, size, x, y, color):
    if 0 <= x < size and 0 <= y < size:
        i = y * size + x
        pixels[i] = blend(pixels[i], color)


def draw_circle(pixels, size, cx, cy, radius, color):
    x0 = max(0, int(cx - radius))
    x1 = min(size - 1, int(cx + radius))
    y0 = max(0, int(cy - radius))
    y1 = min(size - 1, int(cy + radius))
    r2 = radius * radius
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r2:
                set_px(pixels, size, x, y, color)


def draw_ring(pixels, size, cx, cy, radius, width, color):
    x0 = max(0, int(cx - radius))
    x1 = min(size - 1, int(cx + radius))
    y0 = max(0, int(cy - radius))
    y1 = min(size - 1, int(cy + radius))
    inner = max(0, radius - width)
    r2 = radius * radius
    i2 = inner * inner
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            d2 = (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2
            if i2 <= d2 <= r2:
                set_px(pixels, size, x, y, color)


def draw_line(pixels, size, ax, ay, bx, by, width, color):
    x0 = max(0, int(min(ax, bx) - width))
    x1 = min(size - 1, int(max(ax, bx) + width))
    y0 = max(0, int(min(ay, by) - width))
    y1 = min(size - 1, int(max(ay, by) + width))
    dx = bx - ax
    dy = by - ay
    denom = dx * dx + dy * dy
    radius = width / 2
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if denom == 0:
                dist = math.hypot(x - ax, y - ay)
            else:
                t = max(0, min(1, ((x + 0.5 - ax) * dx + (y + 0.5 - ay) * dy) / denom))
                px = ax + t * dx
                py = ay + t * dy
                dist = math.hypot(x + 0.5 - px, y + 0.5 - py)
            if dist <= radius:
                set_px(pixels, size, x, y, color)


def point_in_polygon(x, y, points):
    inside = False
    j = len(points) - 1
    for i in range(len(points)):
        xi, yi = points[i]
        xj, yj = points[j]
        if ((yi > y) != (yj > y)) and (
            x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi
        ):
            inside = not inside
        j = i
    return inside


def draw_polygon(pixels, size, points, color):
    x0 = max(0, int(min(p[0] for p in points)))
    x1 = min(size - 1, int(max(p[0] for p in points)))
    y0 = max(0, int(min(p[1] for p in points)))
    y1 = min(size - 1, int(max(p[1] for p in points)))
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if point_in_polygon(x + 0.5, y + 0.5, points):
                set_px(pixels, size, x, y, color)


def rounded_rect_mask(x, y, size, margin, radius):
    left = margin
    top = margin
    right = size - margin
    bottom = size - margin
    if left + radius <= x <= right - radius and top <= y <= bottom:
        return True
    if top + radius <= y <= bottom - radius and left <= x <= right:
        return True
    corners = [
        (left + radius, top + radius),
        (right - radius, top + radius),
        (left + radius, bottom - radius),
        (right - radius, bottom - radius),
    ]
    return any((x - cx) ** 2 + (y - cy) ** 2 <= radius * radius for cx, cy in corners)


def draw_icon(size):
    if size <= 128:
        scale = 4
    elif size <= 512:
        scale = 2
    else:
        scale = 1
    big = size * scale
    pixels = [(16, 17, 20, 255)] * (big * big)

    for y in range(big):
        for x in range(big):
            nx = x / big
            ny = y / big
            t = min(1, max(0, (nx + ny) / 2))
            base = mix((16, 17, 20), (8, 10, 13), t)
            teal_glow = max(0, 1 - math.hypot(nx - 0.5, ny - 0.48) / 0.54)
            r = min(255, base[0] + round(16 * teal_glow))
            g = min(255, base[1] + round(48 * teal_glow))
            b = min(255, base[2] + round(44 * teal_glow))
            pixels[y * big + x] = (r, g, b, 255)

    margin = 168 / 1024 * big
    radius = 92 / 1024 * big
    for y in range(big):
        for x in range(big):
            if rounded_rect_mask(x + 0.5, y + 0.5, big, margin, radius):
                set_px(pixels, big, x, y, (21, 26, 31, 238))

    for side_x in (220 / 1024 * big, 760 / 1024 * big):
        for yy in (310, 446, 582):
            cx = side_x + 22 / 1024 * big
            cy = yy / 1024 * big + 30 / 1024 * big
            draw_circle(pixels, big, cx, cy, 25 / 1024 * big, (38, 52, 58, 210))

    top = (512 / 1024 * big, 358 / 1024 * big)
    left = (350 / 1024 * big, 660 / 1024 * big)
    right = (674 / 1024 * big, 660 / 1024 * big)
    draw_line(pixels, big, *left, *top, 36 / 1024 * big, (56, 232, 198, 218))
    draw_line(pixels, big, *top, *right, 36 / 1024 * big, (0, 163, 255, 218))
    draw_line(pixels, big, *left, *right, 28 / 1024 * big, (255, 189, 89, 232))

    for center, stroke, dot in [
        (top, (56, 232, 198, 255), (239, 255, 251, 255)),
        (left, (255, 189, 89, 255), (255, 246, 217, 255)),
        (right, (0, 163, 255, 255), (231, 247, 255, 255)),
    ]:
        draw_circle(pixels, big, center[0], center[1], 68 / 1024 * big, (10, 11, 13, 255))
        draw_ring(pixels, big, center[0], center[1], 68 / 1024 * big, 30 / 1024 * big, stroke)
        draw_circle(pixels, big, center[0], center[1], 18 / 1024 * big, dot)

    center = (512 / 1024 * big, 536 / 1024 * big)
    draw_circle(pixels, big, *center, 146 / 1024 * big, (9, 10, 12, 255))
    draw_ring(pixels, big, *center, 146 / 1024 * big, 24 / 1024 * big, (38, 52, 58, 245))

    play = [
        (472 / 1024 * big, 450 / 1024 * big),
        (472 / 1024 * big, 622 / 1024 * big),
        (626 / 1024 * big, 536 / 1024 * big),
    ]
    draw_polygon(pixels, big, play, (56, 232, 198, 255))

    return downsample(pixels, big, scale)


def downsample(pixels, big, scale):
    size = big // scale
    out = []
    for y in range(size):
        for x in range(size):
            total = [0, 0, 0, 0]
            for yy in range(scale):
                for xx in range(scale):
                    p = pixels[(y * scale + yy) * big + (x * scale + xx)]
                    for i in range(4):
                        total[i] += p[i]
            count = scale * scale
            out.append(tuple(round(v / count) for v in total))
    return out


def png_bytes(width, height, pixels):
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixels[y * width + x])

    def chunk(kind, data):
        return (
            struct.pack(">I", len(data))
            + kind
            + data
            + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
        )

    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def write_png(path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    data = png_bytes(size, size, draw_icon(size))
    with open(path, "wb") as f:
        f.write(data)
    return data


def write_ico(path):
    sizes = [16, 32, 48, 64, 128, 256]
    images = [png_bytes(size, size, draw_icon(size)) for size in sizes]
    header = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    entries = bytearray()
    for size, data in zip(sizes, images):
        entries.extend(
            struct.pack(
                "<BBBBHHII",
                0 if size == 256 else size,
                0 if size == 256 else size,
                0,
                0,
                1,
                32,
                len(data),
                offset,
            )
        )
        offset += len(data)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(header + entries + b"".join(images))


def main():
    for name, size in [
        ("web/favicon.png", 32),
        ("web/icons/Icon-192.png", 192),
        ("web/icons/Icon-512.png", 512),
        ("web/icons/Icon-maskable-192.png", 192),
        ("web/icons/Icon-maskable-512.png", 512),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png", 16),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png", 32),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png", 64),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png", 128),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png", 256),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png", 512),
        ("macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png", 1024),
    ]:
        write_png(os.path.join(ROOT, name), size)
    write_ico(os.path.join(ROOT, "windows/runner/resources/app_icon.ico"))


if __name__ == "__main__":
    main()
