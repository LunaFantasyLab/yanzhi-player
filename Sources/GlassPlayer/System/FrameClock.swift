// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import AppKit
import QuartzCore
import SwiftUI

/// 全局帧时钟：CADisplayLink（macOS 14+ 的 NSView.displayLink），请求 120Hz。
/// 轮播物理、进度条插值、均衡器动画都挂在这一条时钟上，和屏幕刷新严格同步，不会出现“两个时钟打架”的抖动。
/// 没有东西在动时自动暂停，省电；有东西要动时立即恢复。
@MainActor
final class FrameClock {
    static let shared = FrameClock()
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var subscribers: [UUID: (Double, CFTimeInterval) -> Bool] = [:]
    private(set) var measuredFPS: Double = 0
    private var fpsAccum: (frames: Int, time: Double) = (0, 0)

    /// 由窗口里的 FrameClockView 安装（display link 必须绑定到某个屏幕上的视图）。
    func attach(to view: NSView) {
        link?.invalidate()
        let l = view.displayLink(target: self, selector: #selector(step(_:)))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)   // .common：拖动、调整窗口大小时也照常跑
        l.isPaused = subscribers.isEmpty
        link = l
    }

    /// 订阅帧回调。回调返回 false 表示“我这帧之后不需要再动了”，自动退订。
    @discardableResult
    func subscribe(_ id: UUID = UUID(), _ f: @escaping (_ dt: Double, _ now: CFTimeInterval) -> Bool) -> UUID {
        subscribers[id] = f
        if link?.isPaused == true { lastTimestamp = nil; link?.isPaused = false }
        return id
    }

    func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty { link?.isPaused = true; lastTimestamp = nil }
    }

    @objc private func step(_ l: CADisplayLink) {
        let now = l.targetTimestamp
        let dt = lastTimestamp.map { max(1.0 / 240, min(0.1, now - $0)) } ?? (l.targetTimestamp - l.timestamp)
        lastTimestamp = now
        fpsAccum.frames += 1; fpsAccum.time += dt
        if fpsAccum.time >= 1 { measuredFPS = Double(fpsAccum.frames) / fpsAccum.time; fpsAccum = (0, 0) }
        for (id, f) in subscribers where !f(dt, now) { subscribers[id] = nil }
        if subscribers.isEmpty { l.isPaused = true; lastTimestamp = nil }
    }
}

/// 隐形的锚点视图：进入窗口后把帧时钟绑到它所在的屏幕（换屏时自动重绑，外接 120Hz 屏立刻生效）。
struct FrameClockAnchor: NSViewRepresentable {
    final class AnchorView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            MainActor.assumeIsolated { FrameClock.shared.attach(to: self) }
            NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSWindow.didChangeScreenNotification, object: window)
        }
        @objc func screenChanged() { MainActor.assumeIsolated { FrameClock.shared.attach(to: self) } }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> AnchorView { AnchorView(frame: .zero) }
    func updateNSView(_ nsView: AnchorView, context: Context) {}
}
