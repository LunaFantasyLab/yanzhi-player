// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 3D 封面轮播的物理模型。单位是“卡片”：position = 2.0 表示第 3 张正好居中。
/// 规则（来自参考笔记的五条原则）：
/// 1. 拖拽 1:1 跟手；松手按速度投射后磁吸到整数位，绝不停在半选中状态；
/// 2. 居中卡成为当前项；
/// 3. 点击侧卡直接跳过去；
/// 4. 全程弹簧，倾斜/景深由 position 连续推导，所以同步变化、没有跳变；
/// 5. 首尾橡皮筋。
public struct CarouselPhysics: Sendable {
    public private(set) var count: Int
    /// 屏幕上实际显示的位置（已含橡皮筋）。
    public private(set) var position: Double
    public private(set) var velocity: Double = 0
    public private(set) var target: Int
    public private(set) var isDragging = false
    public private(set) var isAnimating = false

    private var rawDragPosition: Double = 0
    private var params: SpringParameters = .carouselSnap
    // 速度估计（指数平滑，单位：卡/秒）
    private var lastSampleTime: Double?
    private var smoothedVelocity: Double = 0

    /// 松手后速度投射时间（秒）。越大越容易一甩多张。
    public var projectionTime: Double = 0.16
    /// 一次甩动最多跨几张。
    public var maxFlingCards: Int = 8

    public init(count: Int, index: Int = 0) {
        self.count = max(0, count)
        let i = Self.clampIndex(index, count: count)
        self.position = Double(i)
        self.target = i
    }

    public var maxIndex: Int { max(0, count - 1) }
    /// 当前“居中”的卡（四舍五入），拖拽过程中实时变化，用来做触感反馈和标题联动。
    public var centeredIndex: Int { Self.clampIndex(Int(position.rounded()), count: count) }

    static func clampIndex(_ i: Int, count: Int) -> Int { min(max(0, i), max(0, count - 1)) }

    public mutating func setCount(_ n: Int, keeping index: Int? = nil) {
        count = max(0, n)
        let i = Self.clampIndex(index ?? target, count: count)
        target = i
        if !isDragging && !isAnimating { position = Double(i) }
    }

    // MARK: 拖拽
    public mutating func beginDrag(time: Double) {
        isDragging = true
        isAnimating = false
        rawDragPosition = unbandedPosition(position)
        smoothedVelocity = velocity
        lastSampleTime = time
    }

    /// - Parameter deltaCards: 本次拖动的增量（向左拖 = 正值 = 往后翻）。
    public mutating func drag(deltaCards: Double, time: Double) {
        guard isDragging else { return }
        rawDragPosition += deltaCards
        let newPos = RubberBand.clamp(rawDragPosition, min: 0, max: Double(maxIndex))
        if let t0 = lastSampleTime {
            let dt = max(1.0 / 480.0, time - t0)
            let inst = (newPos - position) / dt
            // 时间常数约 50ms 的平滑，兼顾灵敏和稳定
            let a = 1 - exp(-dt / 0.05)
            smoothedVelocity += (inst - smoothedVelocity) * a
        }
        lastSampleTime = time
        position = newPos
        velocity = smoothedVelocity
    }

    public mutating func endDrag(time: Double) {
        guard isDragging else { return }
        isDragging = false
        // 如果松手前停住了一会儿，速度衰减为 0
        if let t0 = lastSampleTime, time - t0 > 0.08 { smoothedVelocity = 0 }
        var v = smoothedVelocity
        // 越界时不再投射，直接回弹
        let outOfBounds = position < 0 || position > Double(maxIndex)
        if outOfBounds { v *= 0.35 }
        let projected = position + (outOfBounds ? 0 : v * projectionTime)
        var t = Int(projected.rounded())
        let base = Int(position.rounded())
        t = min(max(t, base - maxFlingCards), base + maxFlingCards)
        target = Self.clampIndex(t, count: count)
        velocity = v
        params = .carouselSnap
        isAnimating = true
    }

    // MARK: 跳转（点击侧卡 / 上一首下一首 / 键盘）
    public mutating func jump(to index: Int, gentle: Bool = true) {
        target = Self.clampIndex(index, count: count)
        params = gentle ? .carouselJump : .carouselSnap
        isDragging = false
        isAnimating = true
    }

    /// 撞到首尾时的“到头了”提示：给一个朝外的速度，弹簧会自己拉回来。
    public mutating func bumpEdge(direction: Int) {
        velocity += Double(direction.signum()) * 2.6
        isAnimating = true
    }

    // MARK: 每帧推进（由 CADisplayLink 驱动，120Hz 屏上每 8.3ms 一次）
    /// - Returns: 本帧是否仍在动画中。
    @discardableResult
    public mutating func tick(dt: Double) -> Bool {
        guard isAnimating, !isDragging else { return isDragging }
        // 大 dt（窗口切后台回来）分段推进，保证轨迹稳定
        var remaining = min(dt, 0.25)
        var s = SpringState(value: position, velocity: velocity)
        while remaining > 0 {
            let h = min(remaining, 1.0 / 240.0)
            s = Spring.step(s, target: Double(target), params: params, dt: h)
            remaining -= h
        }
        position = s.value
        velocity = s.velocity
        if Spring.isSettled(s, target: Double(target)) {
            position = Double(target)
            velocity = 0
            isAnimating = false
        }
        return isAnimating
    }

    private func unbandedPosition(_ p: Double) -> Double {
        // 橡皮筋的反函数，保证再次抓住时不跳
        let hi = Double(maxIndex)
        func inv(_ y: Double) -> Double {
            let c = RubberBand.coefficient
            let yy = min(y, 0.999)
            return (1 / (1 - yy) - 1) / c
        }
        if p < 0 { return -inv(-p) }
        if p > hi { return hi + inv(p - hi) }
        return p
    }
}

/// 某张卡相对居中位置 `d`（可为小数）时的 3D 姿态。所有量都是 d 的连续函数 → 拖动时平滑过渡。
public struct CardPose: Sendable, Equatable {
    public var x: Double          // 水平偏移（以“卡片宽度”为单位）
    public var scale: Double
    public var rotationY: Double  // 度；右侧卡向内转（负），左侧卡正
    public var zIndex: Double
    public var dim: Double        // 0…1，叠加的变暗量
    public var blur: Double       // 点（pt）
    public var opacity: Double
    public var lift: Double       // 0…1 居中程度，用来驱动阴影、标题透明度

    public static func pose(relative d: Double, visibleSide: Double = 3.6) -> CardPose {
        let a = abs(d)
        let s = d < 0 ? -1.0 : 1.0
        // 居中卡与第一张侧卡之间留得开，越远越挤（像参考图那样扇形叠放）
        let spread = 0.62 * min(a, 1) + 0.30 * max(0, min(a, 2) - 1) + 0.20 * max(0, a - 2)
        let x = s * spread
        let t = min(a, 1)
        let rot = -s * (52 * smoothstep(t) + 4 * max(0, min(a, 3) - 1))
        let scale = 1 - 0.16 * smoothstep(t) - 0.06 * max(0, min(a, 3) - 1)
        let dim = 0.30 * smoothstep(t) + 0.12 * max(0, min(a, 3) - 1)
        let blur = 0.0 + 1.6 * max(0, min(a, 3) - 1)
        let fadeStart = visibleSide - 1
        let opacity = a <= fadeStart ? 1 : max(0, 1 - (a - fadeStart))
        return CardPose(x: x, scale: scale, rotationY: rot, zIndex: -a, dim: dim, blur: blur,
                        opacity: opacity, lift: 1 - t)
    }

    static func smoothstep(_ t: Double) -> Double {
        let x = min(max(t, 0), 1)
        return x * x * (3 - 2 * x)
    }
}
