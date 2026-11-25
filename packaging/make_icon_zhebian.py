# 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
# 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
# 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
# Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
# products or client work) is prohibited without written permission from Luna Fantasy Lab.

"""Regenerate AppIcon.iconset from packaging/AppIcon-1024.png (t244u 折边扇定稿).
Does not redesign the mark. Official vector: official-06-zhebian.svg.
The 1024 master already has a single 824 macOS-grid plate and transparent corners;
it must not be replaced by the full-bleed official PNG (that PNG already has a
rounded red plate and would double-wrap).
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
MASTER = os.path.join(HERE, "AppIcon-1024.png")
DEST = os.path.join(HERE, "AppIcon.iconset")
os.makedirs(DEST, exist_ok=True)
im = Image.open(MASTER)
if im.size != (1024, 1024):
    raise SystemExit(f"unexpected master size {im.size}")
for s in (16, 32, 128, 256, 512):
    im.resize((s, s), Image.Resampling.LANCZOS).save(os.path.join(DEST, f"icon_{s}x{s}.png"))
    im.resize((s * 2, s * 2), Image.Resampling.LANCZOS).save(os.path.join(DEST, f"icon_{s}x{s}@2x.png"))
print("iconset ok from AppIcon-1024.png")
