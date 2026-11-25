// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

/// 窗口背景：跟着当前封面的主色走。
/// 三层：封面大模糊（预先算好的位图，不在帧里模糊）→ 三团缓慢漂移的柔光 → 暗部渐变 + 颗粒。
/// 换歌时整层 1.1 秒交叉淡入淡出，颜色过渡在 OKLab 里已经“驯化”成低饱和，不会出现撞色。
struct AmbientBackground: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        let key = player.paletteKey
        let theme = player.look
        // 只有「跟随封面」才铺封面大模糊；固定主题优先使用宣传片同款三色块柔光光谱（softLightPalette），跟随封面使用提亮柔光（softLight）
        let art = theme.followsCover ? player.current.flatMap { player.art(for: $0) } : nil
        let activePalette = player.palette   // 已是 softLightPalette / softLight（见 PlayerController.palette）
        ZStack {
            Color(theme.isLight ? .white : .black)
            if theme.isPureBlack {
                Color.black.id(key).transition(.opacity)
            } else {
                AmbientLayer(palette: activePalette, backdrop: art?.backdrop, light: theme.isLight)
                    .id(key)
                    .transition(.opacity)
            }
        }
        // t180u：朱青不再在窗口背景铺左上/右下赤金细线云（避免与卡片页原四重复，且设置窗也会用到本背景）。
        .animation(Motion.palette, value: key)
        .ignoresSafeArea()
    }
}

private struct AmbientLayer: View {
    let palette: AmbientPalette
    let backdrop: CGImage?
    /// 「白」主题：暗角减到很轻，保持干净明亮
    var light = false

    var body: some View {
        GeometryReader { geo in
            let m = max(geo.size.width, geo.size.height)
            ZStack {
                Color(palette.primary)
                if let backdrop {
                    Image(decorative: backdrop, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(1.35)
                        .opacity(0.50)
                        .clipped()
                }
                // 宣传片同款：三团大尺度缓慢漂移的流体柔光（扩大半径、提升通透度，营造丝滑无边界的三色块柔光漫射）
                DriftingBlobs(blobs: [
                    .init(color: palette.secondary, size: 1.18, opacity: 0.68, from: CGPoint(x: -0.28, y: -0.10), to: CGPoint(x: -0.16, y: -0.22), duration: 18),
                    .init(color: palette.tertiary, size: 0.96, opacity: 0.54, from: CGPoint(x: 0.22, y: -0.14), to: CGPoint(x: 0.32, y: 0.08), duration: 22),
                    .init(color: palette.accent, size: 0.76, opacity: 0.32, from: CGPoint(x: 0.08, y: 0.24), to: CGPoint(x: -0.04, y: 0.34), duration: 26),
                ])
                // 极轻的底部自然衬底（去除了旧版 0.38 黑灰脏遮罩，保持柔光色彩纯净通透）
                LinearGradient(stops: [
                    .init(color: .black.opacity(light ? 0.0 : 0.02), location: 0),
                    .init(color: .black.opacity(light ? 0.01 : 0.05), location: 0.60),
                    .init(color: .black.opacity(light ? 0.04 : 0.16), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.clear, .black.opacity(light ? 0.03 : 0.10)], center: .center, startRadius: m * 0.35, endRadius: m * 0.85)
                GrainOverlay(opacity: 0.055)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}

/// 漂移柔光（Core Animation 版）。每团：径向渐变（中心 opacity → 一半处 0.4·opacity → 边缘透明），
/// 位置 = 窗口中心 + (窗口宽, 高) × 偏移系数，在 from ↔ to 之间 easeInOut 往返、无限循环。
private struct DriftingBlobs: NSViewRepresentable {
    struct Blob: Equatable { var color: RGB; var size: CGFloat; var opacity: Double; var from: CGPoint; var to: CGPoint; var duration: Double }
    let blobs: [Blob]
    final class V: NSView {
        var blobs: [Blob] = []
        private var layers: [CAGradientLayer] = []
        private var laidOut: CGSize = .zero
        /// 所有动画共用一个起点，窗口改变大小时重新挂动画也不会“跳相位”
        private let t0 = CACurrentMediaTime()
        override var isFlipped: Bool { true }
        override func hitTest(_ p: NSPoint) -> NSView? { nil }
        override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
        required init?(coder: NSCoder) { fatalError() }
        func setBlobs(_ b: [Blob]) {
            guard b != blobs else { return }
            blobs = b; layers.forEach { $0.removeFromSuperlayer() }; layers = []
            for x in b {
                let g = CAGradientLayer(); g.type = .radial
                g.startPoint = CGPoint(x: 0.5, y: 0.5); g.endPoint = CGPoint(x: 1, y: 1)
                func c(_ a: Double) -> CGColor { CGColor(srgbRed: x.color.r, green: x.color.g, blue: x.color.b, alpha: a) }
                g.colors = [c(x.opacity), c(x.opacity * 0.4), c(0)]
                g.locations = [0, 0.5, 1]
                layer?.addSublayer(g); layers.append(g)
            }
            laidOut = .zero; needsLayout = true
        }
        override func layout() {
            super.layout()
            guard bounds.size != laidOut, bounds.width > 0 else { return }
            laidOut = bounds.size
            let w = bounds.width, h = bounds.height, m = max(w, h)
            let scale = window?.backingScaleFactor ?? 2
            CATransaction.begin(); CATransaction.setDisableActions(true)
            for (g, b) in zip(layers, blobs) {
                g.contentsScale = scale
                let d = m * b.size
                g.bounds = CGRect(x: 0, y: 0, width: d, height: d)
                let p0 = CGPoint(x: w / 2 + w * b.from.x, y: h / 2 + h * b.from.y)
                let p1 = CGPoint(x: w / 2 + w * b.to.x, y: h / 2 + h * b.to.y)
                g.position = p0
                let a = CABasicAnimation(keyPath: "position")
                a.fromValue = NSValue(point: p0); a.toValue = NSValue(point: p1)
                a.duration = b.duration; a.autoreverses = true; a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                a.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
                a.beginTime = g.convertTime(t0, from: nil); a.fillMode = .both; a.isRemovedOnCompletion = false
                g.add(a, forKey: "drift")
            }
            CATransaction.commit()
        }
    }
    func makeNSView(context: Context) -> V { let v = V(frame: .zero); v.setBlobs(blobs); return v }
    func updateNSView(_ v: V, context: Context) { v.setBlobs(blobs) }
}
