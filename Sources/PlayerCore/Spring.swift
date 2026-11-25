// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 与 SwiftUI `.spring(response:dampingFraction:)` 同一套参数含义的弹簧。
/// 用解析解推进（不是欧拉积分），任何帧率下（60/120/144Hz）轨迹完全一致，不会因为掉帧而“抖”。
public struct SpringParameters: Sendable, Equatable {
    /// 无阻尼时一个周期的时长（秒），越小越“快”。
    public var response: Double
    /// 阻尼比：1 = 临界阻尼（无回弹），<1 有轻微回弹。
    public var dampingFraction: Double

    public init(response: Double, dampingFraction: Double) {
        self.response = max(0.01, response)
        self.dampingFraction = max(0.0, dampingFraction)
    }

    /// 轮播磁吸：轻微一次回弹，手感“落位”。
    public static let carouselSnap = SpringParameters(response: 0.46, dampingFraction: 0.82)
    /// 点击侧卡跳转：稍长、更柔和。
    public static let carouselJump = SpringParameters(response: 0.56, dampingFraction: 0.86)
    /// 中心卡抬起：带一点俏皮回弹。
    public static let lift = SpringParameters(response: 0.38, dampingFraction: 0.68)

    var omega: Double { 2 * Double.pi / response }
}

public struct SpringState: Sendable, Equatable {
    public var value: Double
    public var velocity: Double
    public init(value: Double, velocity: Double = 0) {
        self.value = value; self.velocity = velocity
    }
}

public enum Spring {
    /// 把 `state` 向 `target` 推进 `dt` 秒（解析解）。
    public static func step(_ state: SpringState, target: Double, params: SpringParameters, dt: Double) -> SpringState {
        guard dt > 0 else { return state }
        let w0 = params.omega
        let z = params.dampingFraction
        let x0 = state.value - target
        let v0 = state.velocity
        var x: Double
        var v: Double
        if z < 1 {
            let wd = w0 * (1 - z * z).squareRoot()
            let e = exp(-z * w0 * dt)
            let c = cos(wd * dt), s = sin(wd * dt)
            let b = (v0 + z * w0 * x0) / wd
            x = e * (x0 * c + b * s)
            v = e * ((-z * w0) * (x0 * c + b * s) + (-x0 * wd * s + b * wd * c))
        } else if z == 1 {
            let e = exp(-w0 * dt)
            let b = v0 + w0 * x0
            x = e * (x0 + b * dt)
            v = e * (b - w0 * (x0 + b * dt))
        } else {
            let r = (z * z - 1).squareRoot()
            let r1 = -w0 * (z - r), r2 = -w0 * (z + r)
            let c2 = (v0 - r1 * x0) / (r2 - r1)
            let c1 = x0 - c2
            x = c1 * exp(r1 * dt) + c2 * exp(r2 * dt)
            v = c1 * r1 * exp(r1 * dt) + c2 * r2 * exp(r2 * dt)
        }
        return SpringState(value: target + x, velocity: v)
    }

    /// 是否已经静止（位置误差和速度都足够小）。
    public static func isSettled(_ s: SpringState, target: Double, epsilon: Double = 0.0004) -> Bool {
        abs(s.value - target) < epsilon && abs(s.velocity) < epsilon * 8
    }
}

/// 橡皮筋阻尼（与 UIScrollView 同公式）：越往外拉，阻力越大，但永远拉得动一点点。
public enum RubberBand {
    public static let coefficient = 0.55

    /// - Parameters:
    ///   - overshoot: 超出边界的距离（≥0）
    ///   - dimension: 参考尺度（这里用“卡片宽度”=1）
    public static func dampen(_ overshoot: Double, dimension: Double = 1, c: Double = coefficient) -> Double {
        guard overshoot > 0 else { return overshoot }
        return (1 - 1 / (overshoot * c / dimension + 1)) * dimension
    }

    /// 把一个可能越界的位置映射为带橡皮筋效果的显示位置。
    public static func clamp(_ value: Double, min lo: Double, max hi: Double, dimension: Double = 1) -> Double {
        if value < lo { return lo - dampen(lo - value, dimension: dimension) }
        if value > hi { return hi + dampen(value - hi, dimension: dimension) }
        return value
    }
}
