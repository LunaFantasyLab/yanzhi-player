// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 长按快进 / 快退的速度曲线和防爆音淡入淡出（纯计算，便于单元测试）
public enum ScanMath {
    /// 长按多久之后算“快进/快退”（更短的是轻点 = 切歌）
    public static let holdThreshold = 0.35
    /// 每 0.1 秒推进一次
    public static let tick = 0.1
    /// 按得越久越快：×2 → ×4 → ×8 → ×16 → ×32
    public static func rate(held: Double) -> Double {
        switch held {
        case ..<1.2: return 2
        case ..<2.5: return 4
        case ..<4.0: return 8
        case ..<6.0: return 16
        default: return 32
        }
    }
    /// 声音淡出 / 淡入：在“实际增益”上等分（mpv 的音量是立方曲线，直接等分音量百分比会在高音量处一步跳太多）
    /// 返回每一步要设的 mpv volume（0–100+），从 from 到 to
    public static func fadeVolumes(from: Double, to: Double, steps: Int = 12) -> [Double] {
        let g0 = pow(max(0, from) / 100, 3), g1 = pow(max(0, to) / 100, 3)
        return (1...max(1, steps)).map { k in
            let g = g0 + (g1 - g0) * Double(k) / Double(steps)
            return 100 * cbrt(max(0, g))
        }
    }
    /// 淡出约 120ms（24 步 × 5ms），淡入约 170ms（28 步 × 6ms）；步越细，每一步的增益跳变越小
    public static let fadeOutSteps = 24
    public static let fadeInSteps = 28
    public static let fadeStep = 0.005
    /// 夹在 [0, duration - 0.5]
    public static func clamp(_ t: Double, duration: Double?) -> Double {
        guard let d = duration, d > 0 else { return max(0, t) }
        return min(max(0, t), max(0, d - 0.5))
    }
}
