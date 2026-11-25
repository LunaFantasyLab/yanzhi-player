// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 主进度条上的循环点拖选（进入设置循环点模式后，在原曲时间轴上框选 A-B）。
public enum LoopScrubHit: Equatable, Sendable {
    case seek
    case select(origin: Double)
    case handleA
    case handleB
}

public enum LoopScrub {
    public static let minInterval = 0.2

    /// 循环区展开时：直接拖选（不必按 ⌥，按住 ⌥ 同样可以）；靠近已有端点则拖边界。收起时只跳转。
    public static func hit(editorOpen: Bool, optionHeld: Bool, t0: Double, a: Double?, b: Double?, duration: Double, grab: Double) -> LoopScrubHit {
        _ = optionHeld
        _ = duration
        if editorOpen, let a, b != nil, abs(t0 - a) < grab { return .handleA }
        if editorOpen, a != nil, let b, abs(t0 - b) < grab { return .handleB }
        if editorOpen { return .select(origin: t0) }
        return .seek
    }

    /// 区间在原曲进度条上的标识色：与主题强调色错开一个色相，不改 14 套主题色本身。
    /// 暖色强调（红/黄/粉）用青色；冷色强调用琥珀色。
    public static func rangeRGB(accentR: Double, accentG: Double, accentB: Double) -> (Double, Double, Double) {
        let mx = max(accentR, accentG, accentB), mn = min(accentR, accentG, accentB)
        let d = mx - mn
        var h = 0.0
        if d > 1e-6 {
            if mx == accentR { h = (accentG - accentB) / d }
            else if mx == accentG { h = 2 + (accentB - accentR) / d }
            else { h = 4 + (accentR - accentG) / d }
            h *= 60
            if h < 0 { h += 360 }
        }
        if h < 80 || h > 300 { return (0.15, 0.78, 0.88) }
        return (0.98, 0.72, 0.16)
    }

    public static func commit(start: Double, end: Double, duration: Double, minInterval: Double = minInterval) -> (Double, Double)? {
        var a = min(start, end), b = max(start, end)
        if duration > 0 {
            a = max(0, min(a, duration))
            b = max(0, min(b, duration))
        } else {
            a = max(0, a); b = max(0, b)
        }
        guard b - a >= minInterval else { return nil }
        return (a, b)
    }

    /// 循环从不改写总时长：界面与内核仍用原曲 duration。
    public static func displayedDuration(original: Double, loop: (Double, Double)?) -> Double { original }

    /// 播放进度仍按原曲时间轴（0...duration）计算，不把区间映射成新的 0...1。
    public static func progressFraction(position: Double, duration: Double, loop: (Double, Double)?) -> Double {
        guard duration > 0 else { return 0 }
        var t = position
        if let (a, b) = loop {
            if t > a - 0.8, t < a { t = a }
            else if t > b { t = b }
        }
        return min(max(t / duration, 0), 1)
    }

    public static func cursorIndicatesSelect(_ editorOpen: Bool) -> Bool { editorOpen }
}
