#!/usr/bin/env python3
"""NiriMac app icon generator — column tiling WM concept"""

import os
import math
from PIL import Image, ImageDraw

SIZE = 1024
RADIUS = 220  # macOS rounded rect radius


def rounded_rect_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def draw_icon(size=1024):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # --- background gradient (dark navy → dark blue-gray)
    bg = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    for y in range(size):
        t = y / size
        r = int(18 + t * 10)
        g = int(22 + t * 15)
        b = int(42 + t * 20)
        bg_draw.line([(0, y), (size, y)], fill=(r, g, b, 255))

    mask = rounded_rect_mask(size, RADIUS)
    img.paste(bg, (0, 0), mask)

    draw = ImageDraw.Draw(img)

    # --- column layout: 3 columns + gaps
    pad = int(size * 0.12)
    gap = int(size * 0.04)
    col_area_w = size - pad * 2
    col_area_h = size - pad * 2
    col_count = 3
    col_w = (col_area_w - gap * (col_count - 1)) // col_count

    col_colors = [
        (99, 179, 237),   # light blue (pinned column accent)
        (154, 215, 160),  # green
        (99, 179, 237),   # light blue
    ]
    window_colors = [
        [(99, 179, 237, 220), (66, 153, 210, 180)],
        [(154, 215, 160, 220), (100, 180, 110, 180), (130, 200, 140, 200)],
        [(99, 179, 237, 180), (66, 153, 210, 140)],
    ]

    col_radius = int(size * 0.025)
    win_radius = int(size * 0.018)

    for ci in range(col_count):
        cx = pad + ci * (col_w + gap)
        cy = pad

        # draw windows inside column
        wins = window_colors[ci]
        win_gap = int(size * 0.025)
        win_h = (col_area_h - win_gap * (len(wins) - 1)) // len(wins)

        for wi, wc in enumerate(wins):
            wy = cy + wi * (win_h + win_gap)
            # window body
            draw.rounded_rectangle(
                [cx, wy, cx + col_w, wy + win_h],
                radius=col_radius,
                fill=wc,
            )
            # subtle title bar strip
            bar_h = int(win_h * 0.14)
            bar_color = (wc[0], wc[1], wc[2], min(255, wc[3] + 30))
            draw.rounded_rectangle(
                [cx, wy, cx + col_w, wy + bar_h],
                radius=col_radius,
                fill=bar_color,
            )
            # traffic-light dots (tiny)
            dot_r = max(4, int(size * 0.008))
            dot_y = wy + bar_h // 2
            for di, dc in enumerate([(255, 95, 87), (255, 189, 46), (39, 201, 63)]):
                dot_x = cx + dot_r * 2 + di * (dot_r * 2 + int(size * 0.006))
                draw.ellipse(
                    [dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r],
                    fill=dc + (200,),
                )

    # --- subtle vignette overlay
    vign = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    vd = ImageDraw.Draw(vign)
    for r in range(size // 2, 0, -1):
        alpha = int(60 * (1 - r / (size / 2)) ** 2)
        vd.ellipse(
            [size // 2 - r, size // 2 - r, size // 2 + r, size // 2 + r],
            outline=(0, 0, 0, alpha),
        )
    img = Image.alpha_composite(img, vign)

    # re-apply mask to keep rounded corners
    final = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    final.paste(img, (0, 0), mask)
    return final


def build_iconset(base_img, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes:
        resized = base_img.resize((s, s), Image.LANCZOS)
        resized.save(os.path.join(out_dir, f"icon_{s}x{s}.png"))
        if s <= 512:
            resized2 = base_img.resize((s * 2, s * 2), Image.LANCZOS)
            resized2.save(os.path.join(out_dir, f"icon_{s}x{s}@2x.png"))


if __name__ == "__main__":
    print("Generating icon...")
    icon = draw_icon(SIZE)
    iconset_dir = "NiriMac.iconset"
    build_iconset(icon, iconset_dir)
    icon.save("icon_preview_1024.png")
    print(f"Saved iconset to {iconset_dir}/ and preview to icon_preview_1024.png")
