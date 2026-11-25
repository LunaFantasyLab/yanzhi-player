# 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
# 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
# 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
# Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
# products or client work) is prohibited without written permission from Luna Fantasy Lab.

"""App 图标入口（t248u 起）：正常折扇定稿。

栅格由 packaging/AppIcon-1024.png 缩放写入 AppIcon.iconset。
官方矢量：packaging/official-fan-normal.svg（朱红底板由 Icon Composer 填充，
图层不含预画圆角底板，避免二次套板）。扇轴朝左，不镜像、不改设计。
"""
import runpy
import os

if __name__ == "__main__":
    runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_icon_normal.py"), run_name="__main__")
