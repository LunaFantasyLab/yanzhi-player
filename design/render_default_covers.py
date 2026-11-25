# 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
# 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
# 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
# Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
# products or client work) is prohibited without written permission from Luna Fantasy Lab.

"""默认封面「柔光玻璃」样图渲染器（盒子上出样图用；App 内用 CoreGraphics 版 DefaultCoverRenderer.swift 实时生成）。
运行：python3 render_default_covers.py  → default-covers/*.png + ../Tests/PlayerCoreTests/Fixtures/default_cover_specs.json
"""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from cover_spec import make, PALETTES, MOTIFS

S = 1200            # 输出尺寸
SS = 2              # 形状超采样
HERE = os.path.dirname(os.path.abspath(__file__))
FONT_TITLE = os.environ.get("COVER_FONT", "NotoSansSC-VF.ttf")  # 任意开源中文字体路径

# ---------- OKLab ----------
def srgb_to_lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)

def lin_to_srgb(c):
    c = np.clip(c, 0, None)
    return np.where(c <= 0.0031308, 12.92 * c, 1.055 * np.power(c, 1 / 2.4) - 0.055)

def rgb_to_oklab(rgb):
    r, g, b = [srgb_to_lin(rgb[..., i]) for i in range(3)]
    l = np.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    m = np.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    s = np.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return np.stack([0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                     1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                     0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s], -1)

def oklab_to_rgb(lab):
    L, a, b = lab[..., 0], lab[..., 1], lab[..., 2]
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    rgb = np.stack([4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s], -1)
    return np.clip(lin_to_srgb(rgb), 0, 1)

def hexlab(h):
    return rgb_to_oklab(np.array([[(h >> 16 & 255) / 255, (h >> 8 & 255) / 255, (h & 255) / 255]]))[0]

def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)

# ---------- 渲染 ----------
def render(spec, title, artist, size=S):
    n = size
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64)
    u, v = (xx + 0.5) / n, (yy + 0.5) / n
    name, base, ca, cb, cc = PALETTES[spec["paletteIndex"]]
    lab = np.broadcast_to(hexlab(base), (n, n, 3)).copy()

    # 1) 底部方向渐变：沿 angle 方向轻微提亮（像光从一侧进来）
    ang = math.radians(spec["angle"])
    t = ((u - 0.5) * math.cos(ang) + (v - 0.5) * math.sin(ang)) + 0.5
    lab[..., 0] += 0.05 * smoothstep(0, 1, t)

    # 2) 三团柔光（OKLab 中混色 → 过渡干净不发灰）
    for blob, col, strength in zip(spec["blobs"], (ca, cb, cc), (0.92, 0.70, 0.85)):
        d2 = ((u - blob["x"]) ** 2 + (v - blob["y"]) ** 2) / (blob["r"] ** 2)
        w = np.exp(-d2 * 2.4) * strength
        tgt = hexlab(col)
        lab += (tgt - lab) * w[..., None]

    # 3) 玻璃母题
    lab = draw_motif(lab, spec, u, v, n)

    # 4) 暗角 + 轻微整体压暗，保证白字可读
    r2 = (u - 0.5) ** 2 + (v - 0.5) ** 2
    lab[..., 0] *= 1 - 0.30 * smoothstep(0.10, 0.62, r2)
    lab[..., 0] -= 0.10 * smoothstep(0.55, 1.0, v)       # 底部留给文字

    # 5) 细颗粒（亮度通道，σ 很小，看得到质感但看不到“噪点”）
    rng = np.random.default_rng(spec["grainSeed"])
    grain = rng.normal(0, 1, (n, n))
    grain = 0.6 * grain + 0.4 * np.asarray(Image.fromarray(((grain * 40) + 128).clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7)), dtype=np.float64) / 40 - 3.2 * 0.4
    lab[..., 0] += grain * 0.011

    rgb = oklab_to_rgb(lab)
    img = Image.fromarray((rgb * 255 + 0.5).clip(0, 255).astype(np.uint8), "RGB")
    draw_text(img, title, artist, n)
    return img

def glass_layer(lab, mask, edge, u, v, cx=0.5, cy=0.5, size=0.3, lift=0.055, desat=0.86, spec_strength=0.09):
    """磨砂玻璃：区域内轻微放大折射背景、提亮、去饱和（像被磨砂层漫射），
    内部从左上到右下的亮度渐变（体积感），边缘一圈细高光（左上亮、右下暗）。"""
    n = lab.shape[0]
    # 折射：玻璃内部的背景向中心轻微放大 6%
    sx = np.clip(((u - cx) * 0.94 + cx) * n, 0, n - 1).astype(np.int32)
    sy = np.clip(((v - cy) * 0.94 + cy) * n, 0, n - 1).astype(np.int32)
    g = lab[sy, sx].copy()
    g[..., 0] += lift
    g[..., 1:] *= desat
    # 体积：左上亮、右下略暗
    k = np.clip(0.5 - ((u - cx) * 0.55 + (v - cy) * 0.85) / max(size, 1e-3), 0, 1)
    g[..., 0] += spec_strength * (k ** 1.8) - 0.025 * (1 - k)
    out = lab + (g - lab) * mask[..., None]
    out[..., 0] += edge
    return out

def disk_sdf(u, v, cx, cy, r):
    return np.sqrt((u - cx) ** 2 + (v - cy) ** 2) - r

def rrect_sdf(u, v, cx, cy, hw, hh, rad):
    qx = np.abs(u - cx) - hw + rad
    qy = np.abs(v - cy) - hh + rad
    return np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2) + np.minimum(np.maximum(qx, qy), 0) - rad

def aa(sdf, n, soft=1.0):
    px = 1.0 / n
    return np.clip(0.5 - sdf / (px * soft), 0, 1)

def edge_light(sdf, u, v, cx, cy, n, width_px=2.2, strength=0.16):
    px = 1.0 / n
    band = np.exp(-((sdf + px * 0.8) / (px * width_px)) ** 2)
    nx, ny = u - cx, v - cy
    ln = np.sqrt(nx ** 2 + ny ** 2) + 1e-9
    facing = -(nx / ln * 0.62 + ny / ln * 0.78)   # 光从左上来
    return band * strength * (0.35 + 0.65 * np.clip(facing, -0.4, 1))

def soft_shadow(lab, sdf, n, dx=0.012, dy=0.022, blur=0.06, amount=0.10):
    # 阴影：把 SDF 平移后做柔化
    return lab

def draw_motif(lab, spec, u, v, n):
    m = MOTIFS[spec["motif"]]
    cx, cy, s = spec["motifX"], spec["motifY"], spec["motifSize"]
    if m == "aurora":
        # 再叠一层更大的、很淡的光带，形成极光般的层次
        band = np.exp(-(((v - 0.42) - 0.18 * np.sin((u + spec["angle"] / 360) * math.pi * 2)) / 0.16) ** 2)
        lab[..., 0] += 0.045 * band
        return lab
    if m == "ring":
        d = disk_sdf(u, v, cx, cy, s * 0.62)
        shadow = np.exp(-np.maximum(disk_sdf(u, v, cx + 0.012, cy + 0.03, s * 0.62), 0) / 0.05) * (1 - aa(d, n))
        lab[..., 0] -= 0.06 * shadow
        mask = aa(d, n)
        lab = glass_layer(lab, mask * 0.92, edge_light(d, u, v, cx, cy, n, strength=0.15), u, v, cx, cy, s * 0.62 * 2,
                          lift=0.04, desat=0.9, spec_strength=0.11)
        ring = np.abs(disk_sdf(u, v, cx, cy, s * 0.86))
        lab[..., 0] += 0.10 * np.exp(-(ring / (1.4 / n)) ** 2) + 0.03 * np.exp(-(ring / (10 / n)) ** 2)
        return lab
    if m == "horizon":
        y0 = 0.40 + (cy - 0.42) * 0.6
        core = np.exp(-((v - y0) / 0.010) ** 2)
        glow = np.exp(-((v - y0) / 0.085) ** 2)
        fade = smoothstep(0.0, 0.35, u) * smoothstep(1.0, 0.65, u)
        lab[..., 0] += (0.16 * core + 0.07 * glow) * (0.4 + 0.6 * fade)
        lab[..., 1:] *= (1 - 0.25 * glow)[..., None]
        return lab
    if m == "arc":
        R = 0.62 + s * 0.6
        acx, acy = cx - 0.05, cy + R * 0.92
        d = np.abs(disk_sdf(u, v, acx, acy, R))
        upper = smoothstep(0.0, 0.2, (acy - v))
        lab[..., 0] += (0.13 * np.exp(-(d / (1.6 / n)) ** 2) + 0.05 * np.exp(-(d / (18 / n)) ** 2)) * upper
        inside = aa(disk_sdf(u, v, acx, acy, R), n)
        lab = glass_layer(lab, inside * 0.55, 0, u, v, acx, acy - R * 0.8, 0.8, lift=0.035, desat=0.88, spec_strength=0.03)
        return lab
    if m == "panes":
        hw = s * 0.58
        a_sdf = rrect_sdf(u, v, cx - 0.06, cy - 0.04, hw, hw, 0.06)
        b_sdf = rrect_sdf(u, v, cx + 0.07, cy + 0.08, hw * 0.92, hw * 0.92, 0.06)
        for sdf, ox, oy, k in ((a_sdf, cx - 0.06, cy - 0.04, 0.75), (b_sdf, cx + 0.07, cy + 0.08, 0.95)):
            shadow = np.exp(-np.maximum(sdf, 0) / 0.04) * (1 - aa(sdf, n))
            lab[..., 0] -= 0.045 * shadow
            lab = glass_layer(lab, aa(sdf, n) * k, edge_light(sdf, u, v, ox, oy, n, strength=0.15), u, v, ox, oy, hw * 2,
                              lift=0.045, desat=0.84, spec_strength=0.09)
        return lab
    if m == "orb":
        r = s * 0.55
        d = disk_sdf(u, v, cx, cy, r)
        shadow = np.exp(-np.maximum(disk_sdf(u, v, cx + 0.02, cy + 0.05, r * 1.02), 0) / 0.06) * (1 - aa(d, n))
        lab[..., 0] -= 0.07 * shadow
        mask = aa(d, n)
        # 球体明暗：左上高光、右下反光
        nx, ny = (u - cx) / r, (v - cy) / r
        nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2, 0, 1))
        diffuse = np.clip(-0.45 * nx - 0.55 * ny + 0.70 * nz, 0, 1)
        spec_hl = np.exp(-(((nx + 0.38) ** 2 + (ny + 0.42) ** 2) / 0.035))
        rim = smoothstep(0.75, 1.0, np.sqrt(nx ** 2 + ny ** 2))
        g = lab.copy()
        g[..., 0] += 0.05 + 0.10 * (diffuse - 0.5) + 0.20 * spec_hl + 0.06 * rim
        g[..., 1:] *= 0.82
        lab = lab + (g - lab) * mask[..., None]
        lab[..., 0] += edge_light(d, u, v, cx, cy, n, strength=0.12)
        return lab
    return lab

def draw_text(img, title, artist, n):
    d = ImageDraw.Draw(img, "RGBA")
    try:
        ft = ImageFont.truetype(FONT_TITLE, int(n * 0.050))
        ft.set_variation_by_axes([600])
        fa = ImageFont.truetype(FONT_TITLE, int(n * 0.030))
        fa.set_variation_by_axes([450])
    except Exception:
        ft = fa = ImageFont.load_default()
    x = int(n * 0.075)
    y_artist = int(n * 0.905)
    y_title = y_artist - int(n * 0.068)
    d.text((x, y_title), title, font=ft, fill=(255, 255, 255, 236))
    d.text((x, y_artist), artist, font=fa, fill=(255, 255, 255, 150))
    # 右上角极小的系列标记：一枚细环
    r = int(n * 0.018); cx, cy = n - int(n * 0.085), int(n * 0.085)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=(255, 255, 255, 84), width=max(1, n // 700))

SAMPLES = [
    ("Clair de Lune", "Debussy"),
    ("Holocene", "Bon Iver"),
    ("光年之外", "邓紫棋"),
    ("Blue in Green", "Miles Davis"),
    ("Yellow", "Coldplay"),
    ("成都", "赵雷"),
]

if __name__ == "__main__":
    out_dir = os.path.join(HERE, "default-covers")
    os.makedirs(out_dir, exist_ok=True)
    specs = []
    for i, (t, a) in enumerate(SAMPLES, 1):
        spec = make(f"track|{t}|{a}")
        specs.append(spec)
        img = render(spec, t, a)
        fn = f"{i:02d}-{MOTIFS[spec['motif']]}-{PALETTES[spec['paletteIndex']][0]}.png"
        img.save(os.path.join(out_dir, fn), optimize=True)
        print("saved", fn)
    fx = os.path.join(HERE, "..", "Tests", "PlayerCoreTests", "Fixtures")
    os.makedirs(fx, exist_ok=True)
    extra = [make(s) for s in ["album|范特西|周杰伦", "track|未命名|未知艺人", "track|🎵 emoji ✓|X", ""]]
    with open(os.path.join(fx, "default_cover_specs.json"), "w", encoding="utf-8") as f:
        json.dump(specs + extra, f, ensure_ascii=False, indent=1)
    # 联系表
    thumbs = [Image.open(os.path.join(out_dir, p)).resize((400, 400), Image.LANCZOS) for p in sorted(os.listdir(out_dir)) if p.endswith(".png") and p[0].isdigit()]
    sheet = Image.new("RGB", (3 * 400 + 4 * 24, 2 * 400 + 3 * 24), (236, 234, 240))
    for k, th in enumerate(thumbs):
        sheet.paste(th, (24 + (k % 3) * 424, 24 + (k // 3) * 424))
    sheet.save(os.path.join(out_dir, "contact-sheet.png"))
    print("contact sheet ok")
