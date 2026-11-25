// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 缺封面时的默认封面：「柔光玻璃」系列。
/// 由 “专辑|歌手” 或 “歌名|歌手” 哈希出确定的参数：同一张专辑永远同一张图，不同的歌各不相同。
/// 画面构成（由下到上）：深色底 → 三团大面积柔光（OKLab 低饱和）→ 一个玻璃母题 → 暗角 → 细颗粒 → 小字。
/// Python 样图渲染器（design/render_default_covers.py）与 macOS 端 CoreGraphics 渲染器共用这一份规则，
/// 测试里用 Fixtures/default_cover_specs.json 校验两边算出的参数逐位一致。
public struct DefaultCoverSpec: Codable, Equatable, Sendable {
    public struct Palette: Codable, Equatable, Sendable {
        public var name: String
        public var base: UInt32
        public var a: UInt32
        public var b: UInt32
        public var c: UInt32
    }
    public enum Motif: Int, Codable, CaseIterable, Sendable {
        case aurora = 0      // 只有柔光
        case ring = 1        // 细玻璃环 + 磨砂圆片
        case horizon = 2     // 一道横向柔光（像窗外的天际线）
        case arc = 3         // 大弧线
        case panes = 4       // 两片错位叠放的玻璃
        case orb = 5         // 一颗有高光的玻璃球
    }
    public struct Blob: Codable, Equatable, Sendable {
        public var x: Double, y: Double, r: Double   // 单位坐标 0…1（y 向下）
    }

    public var seed: String
    public var hash: UInt64
    public var paletteIndex: Int
    public var motif: Motif
    public var angle: Double          // 底部渐变角度（度）
    public var blobs: [Blob]          // 3 个，对应 palette a/b/c
    public var motifX: Double         // 母题中心
    public var motifY: Double
    public var motifSize: Double
    public var grainSeed: UInt32

    public static let palettes: [Palette] = [
        Palette(name: "雾紫", base: 0x221E36, a: 0x8C7BD1, b: 0xC9A7E0, c: 0x5E6FB8),
        Palette(name: "青瓷", base: 0x172A2A, a: 0x7FB3A8, b: 0xCFE3D6, c: 0x4E7F86),
        Palette(name: "暮橙", base: 0x2E1E1B, a: 0xE0957A, b: 0xF2C9A6, c: 0x9C5A6A),
        Palette(name: "深海", base: 0x0F1726, a: 0x3F6FA8, b: 0x8FB8DE, c: 0x2C3E73),
        Palette(name: "樱粉", base: 0x2F1D27, a: 0xE7A1B6, b: 0xF6D5DC, c: 0xA46A8C),
        Palette(name: "苔绿", base: 0x182219, a: 0x8EA77A, b: 0xD7DFB8, c: 0x4F6B4E),
        Palette(name: "沙金", base: 0x262017, a: 0xC8A770, b: 0xEADBB8, c: 0x8A6E4B),
        Palette(name: "月白", base: 0x1C2027, a: 0x9AA7B8, b: 0xE3E7EE, c: 0x5D6878),
        Palette(name: "黛蓝", base: 0x141A30, a: 0x5B6EC2, b: 0xA9B4EA, c: 0x7E5CA8),
        Palette(name: "胭脂", base: 0x26161B, a: 0xB86A78, b: 0xE8B7B3, c: 0x6E3A55),
        Palette(name: "极光", base: 0x101C22, a: 0x4FB2A6, b: 0xA7D8C9, c: 0x6E7FCF),
        Palette(name: "烟岚", base: 0x212325, a: 0xA39A8E, b: 0xDCD6CC, c: 0x6F7A80),
    ]

    /// 32 套高审美、更鲜活丰富的艺术调色板（用于所有风格化随机封面，兼容上面 12 套基准调色板不破坏既有测试）
    public static let richPalettes: [Palette] = [
        // 1–12 东方釉色与经典氛围升级版
        Palette(name: "雾紫电光", base: 0x1D1138, a: 0x8B5CF6, b: 0xE0C3FC, c: 0x4F46E5),
        Palette(name: "青瓷冰玉", base: 0x0F2929, a: 0x2DD4BF, b: 0xCCFBF1, c: 0x0EA5E9),
        Palette(name: "落日暮橙", base: 0x2D130A, a: 0xF97316, b: 0xFED7AA, c: 0xEA580C),
        Palette(name: "深海蔚蓝", base: 0x081B33, a: 0x0284C7, b: 0x7DD3FC, c: 0x1D4ED8),
        Palette(name: "樱花奶桃", base: 0x341426, a: 0xF472B6, b: 0xFCE7F3, c: 0xDB2777),
        Palette(name: "森系苔绿", base: 0x112614, a: 0x22C55E, b: 0xD9F99D, c: 0x15803D),
        Palette(name: "流金香槟", base: 0x291E08, a: 0xEAB308, b: 0xFEF9C3, c: 0xCA8A04),
        Palette(name: "月光清银", base: 0x182030, a: 0x94A3B8, b: 0xF1F5F9, c: 0x64748B),
        Palette(name: "黛蓝群青", base: 0x09112E, a: 0x1E3A8A, b: 0x818CF8, c: 0x4F46E5),
        Palette(name: "丝绒胭脂", base: 0x2B0813, a: 0xE11D48, b: 0xFECDD3, c: 0x9F1239),
        Palette(name: "北境极光", base: 0x081D26, a: 0x10B981, b: 0xA7F3D0, c: 0x9333EA),
        Palette(name: "暖陶烟岚", base: 0x241B15, a: 0xB4825A, b: 0xF3E2D2, c: 0x7C5840),
        // 13–32 全新有趣鲜活艺术色盘（波普、赛博、印象派、复古黑胶、敦煌、热带、蒸汽波等）
        Palette(name: "珊瑚晚霞", base: 0x1E1028, a: 0xFF5E62, b: 0xFFBE76, c: 0x7B2CBF),
        Palette(name: "电光青柠", base: 0x0B241E, a: 0x00F5A0, b: 0xE9FF70, c: 0x00BBF9),
        Palette(name: "京都绯金", base: 0x240B14, a: 0xE63946, b: 0xFFB703, c: 0xFB8500),
        Palette(name: "赛博霓虹", base: 0x0D0628, a: 0xFF2A85, b: 0x00F0FF, c: 0x7B2CBF),
        Palette(name: "莫奈睡莲", base: 0x12263A, a: 0x48CAE4, b: 0xF4ACB7, c: 0x90E0EF),
        Palette(name: "焦糖黑胶", base: 0x24140B, a: 0xE07A5F, b: 0xF2CC8F, c: 0x81B29A),
        Palette(name: "克莱因蓝", base: 0x060D2E, a: 0x0047AB, b: 0x60A5FA, c: 0xF43F5E),
        Palette(name: "薄荷汽水", base: 0x0E2926, a: 0x2EC4B6, b: 0xCBF3F0, c: 0xFF9F1C),
        Palette(name: "蜜桃乌龙", base: 0x2E161C, a: 0xFF758F, b: 0xFFD6A5, c: 0xC77DFF),
        Palette(name: "热带雨林", base: 0x0B2418, a: 0x10B981, b: 0xFACC15, c: 0x06B6D4),
        Palette(name: "普罗旺斯", base: 0x1A1033, a: 0x9D4EDD, b: 0xFF9EBB, c: 0x4CC9F0),
        Palette(name: "松石熔金", base: 0x092229, a: 0x06B6D4, b: 0xF59E0B, c: 0xEC4899),
        Palette(name: "奶油草莓", base: 0x2D1120, a: 0xFF4D6D, b: 0xFFF0F3, c: 0xFF8FA3),
        Palette(name: "星际靛紫", base: 0x0B0B2B, a: 0x4361EE, b: 0xF72585, c: 0x4CC9F0),
        Palette(name: "抹茶柚子", base: 0x162414, a: 0x65A30D, b: 0xFDE047, c: 0x38BDF8),
        Palette(name: "敦煌飞天", base: 0x1D1B2A, a: 0xD97706, b: 0x14B8A6, c: 0xE11D48),
        Palette(name: "冰川极昼", base: 0x0C1B2E, a: 0x38BDF8, b: 0xE0F2FE, c: 0xA78BFA),
        Palette(name: "红丝绒爵士", base: 0x220910, a: 0xB91C1C, b: 0xFBBF24, c: 0x7C2D12),
        Palette(name: "多巴胺果糖", base: 0x1B1035, a: 0xFF006E, b: 0xFFBE0B, c: 0x3A86FF),
        Palette(name: "青绿山水", base: 0x0B1F1E, a: 0x0D9488, b: 0xD4A373, c: 0x3B82F6),
    ]

    public static func make(seed: String) -> DefaultCoverSpec {
        let h = fnv1a64(seed)
        var rng = SplitMix64(state: h)
        let pi = Int(rng.next() % UInt64(palettes.count))
        let motif = Motif(rawValue: Int(rng.next() % 6))!
        let angle = (rng.unit() * 360).rounded()
        var blobs: [Blob] = []
        // 三团光大致落在三个象限，避免挤在一起变成一坨
        let anchors: [(Double, Double)] = [(0.22, 0.25), (0.78, 0.35), (0.45, 0.82)]
        let rot = Int(rng.next() % 3)
        for k in 0..<3 {
            let (ax, ay) = anchors[(k + rot) % 3]
            let x = ax + (rng.unit() - 0.5) * 0.22
            let y = ay + (rng.unit() - 0.5) * 0.22
            let r = 0.42 + rng.unit() * 0.28
            blobs.append(Blob(x: round3(x), y: round3(y), r: round3(r)))
        }
        let mx = round3(0.35 + rng.unit() * 0.30)
        let my = round3(0.30 + rng.unit() * 0.25)
        let ms = round3(0.28 + rng.unit() * 0.16)
        let gs = UInt32(truncatingIfNeeded: rng.next())
        return DefaultCoverSpec(seed: seed, hash: h, paletteIndex: pi, motif: motif, angle: angle, blobs: blobs,
                                motifX: mx, motifY: my, motifSize: ms, grainSeed: gs)
    }

    public var palette: Palette { Self.palettes[paletteIndex] }
    public var richPalette: Palette { Self.richPalettes[Int((hash >> 16) % UInt64(Self.richPalettes.count))] }

    static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    public static func fnv1a64(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 { h ^= UInt64(byte); h = h &* 0x100000001b3 }
        return h
    }
}

public struct SplitMix64: Sendable {
    public var state: UInt64
    public init(state: UInt64) { self.state = state }
    public mutating func next() -> UInt64 {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    /// [0,1) 均匀分布（53 位精度，与 Python 端一致）
    public mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
}
