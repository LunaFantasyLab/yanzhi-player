# 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
# 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
# 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
# Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
# products or client work) is prohibited without written permission from Luna Fantasy Lab.

"""与 Sources/PlayerCore/DefaultCover.swift 逐位一致的参数生成（用于样图渲染和交叉测试）。"""
import math

M64 = (1 << 64) - 1

PALETTES = [
    ("雾紫", 0x221E36, 0x8C7BD1, 0xC9A7E0, 0x5E6FB8),
    ("青瓷", 0x172A2A, 0x7FB3A8, 0xCFE3D6, 0x4E7F86),
    ("暮橙", 0x2E1E1B, 0xE0957A, 0xF2C9A6, 0x9C5A6A),
    ("深海", 0x0F1726, 0x3F6FA8, 0x8FB8DE, 0x2C3E73),
    ("樱粉", 0x2F1D27, 0xE7A1B6, 0xF6D5DC, 0xA46A8C),
    ("苔绿", 0x182219, 0x8EA77A, 0xD7DFB8, 0x4F6B4E),
    ("沙金", 0x262017, 0xC8A770, 0xEADBB8, 0x8A6E4B),
    ("月白", 0x1C2027, 0x9AA7B8, 0xE3E7EE, 0x5D6878),
    ("黛蓝", 0x141A30, 0x5B6EC2, 0xA9B4EA, 0x7E5CA8),
    ("胭脂", 0x26161B, 0xB86A78, 0xE8B7B3, 0x6E3A55),
    ("极光", 0x101C22, 0x4FB2A6, 0xA7D8C9, 0x6E7FCF),
    ("烟岚", 0x212325, 0xA39A8E, 0xDCD6CC, 0x6F7A80),
]
MOTIFS = ["aurora", "ring", "horizon", "arc", "panes", "orb"]


def fnv1a64(s: str) -> int:
    h = 0xcbf29ce484222325
    for b in s.encode("utf-8"):
        h ^= b
        h = (h * 0x100000001b3) & M64
    return h


class SplitMix64:
    def __init__(self, state):
        self.state = state

    def next(self):
        self.state = (self.state + 0x9E3779B97F4A7C15) & M64
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & M64
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & M64
        return z ^ (z >> 31)

    def unit(self):
        return (self.next() >> 11) / float(1 << 53)


def r3(v):
    return math.floor(v * 1000 + 0.5) / 1000


def make(seed: str) -> dict:
    h = fnv1a64(seed)
    rng = SplitMix64(h)
    pi = rng.next() % len(PALETTES)
    motif = rng.next() % 6
    angle = math.floor(rng.unit() * 360 + 0.5)
    anchors = [(0.22, 0.25), (0.78, 0.35), (0.45, 0.82)]
    rot = rng.next() % 3
    blobs = []
    for k in range(3):
        ax, ay = anchors[(k + rot) % 3]
        x = ax + (rng.unit() - 0.5) * 0.22
        y = ay + (rng.unit() - 0.5) * 0.22
        r = 0.42 + rng.unit() * 0.28
        blobs.append({"x": r3(x), "y": r3(y), "r": r3(r)})
    mx = r3(0.35 + rng.unit() * 0.30)
    my = r3(0.30 + rng.unit() * 0.25)
    ms = r3(0.28 + rng.unit() * 0.16)
    gs = rng.next() & 0xFFFFFFFF
    return {"seed": seed, "hash": str(h), "paletteIndex": pi, "motif": motif, "angle": float(angle),
            "blobs": blobs, "motifX": mx, "motifY": my, "motifSize": ms, "grainSeed": gs}
