// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import AppKit
import QuartzCore
import OpenGL.GL3
import SwiftUI

/// 整个 App 只有一个视频视图实例（mpv 初始化时就要拿到它的 layer），SwiftUI 只是把它摆到合适的位置。
final class VideoSurfaceView: NSView {
    let glLayer = MPVGLLayer()
    var onDoubleClick: (() -> Void)?
    /// 右键菜单（由 MenuCatalog.videoSurface 生成，和 SwiftUI 那边的菜单是同一份数据）
    var menuProvider: (() -> NSMenu?)?
    /// 拖文件到画面上：经过时点亮、松手立即播放
    var onDragHover: ((Bool) -> Void)?
    var onDropURLs: (([URL]) -> Void)?

    /// 圆角裁切放在外层普通 CALayer 上：直接给 CAMetalLayer 设 cornerRadius 时，系统可能把它当硬件叠加层直出，
    /// 圆角只有部分生效（2026-11-18 真机截图：四角里三角是直角）。外层容器裁切则始终正确。
    let clipLayer = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        glLayer.backgroundColor = NSColor.black.cgColor
        glLayer.isOpaque = true
        clipLayer.backgroundColor = NSColor.black.cgColor
        clipLayer.cornerCurve = .continuous
        clipLayer.masksToBounds = true
        clipLayer.addSublayer(glLayer)
        layer = clipLayer       // layer-hosting
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 参数卡片打开时把视频画面轻轻模糊。滤镜挂在视频图层上，半径动画交给系统合成器逐帧插值（不占主线程）；
    /// 收起后整个拿掉滤镜，平时零开销。
    private var blurNow: CGFloat = 0
    func setBlur(_ r: CGFloat, duration: Double = 0.28) {
        guard r != blurNow else { return }
        let from = blurNow
        blurNow = r
        if glLayer.filters?.isEmpty ?? true, let f = CIFilter(name: "CIGaussianBlur") {
            f.name = "blur"; f.setValue(from, forKey: kCIInputRadiusKey)
            glLayer.filters = [f]
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.blurNow == 0 else { return }
                self.glLayer.removeAnimation(forKey: "blur"); self.glLayer.filters = nil
            }
        }
        let a = CABasicAnimation(keyPath: "filters.blur.inputRadius")
        a.fromValue = (glLayer.presentation()?.value(forKeyPath: "filters.blur.inputRadius") as? CGFloat) ?? from
        a.toValue = r
        a.duration = duration
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        glLayer.setValue(r, forKeyPath: "filters.blur.inputRadius")
        glLayer.add(a, forKey: "blur")
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        syncLayerSize()
    }

    /// layer-hosting 视图在 SwiftUI 改尺寸时不一定走 layout()，所以改帧尺寸、换窗口时也同步一次。
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncLayerSize()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        syncLayerSize()
    }

    /// 视频层跟着视图同步改尺寸（不带隐式动画）。CAOpenGLLayer 开了 needsDisplayOnBoundsChange，
    /// 尺寸一变就在同一个 CA 事务里按新尺寸重画当前帧，所以拖窗口、全屏、迷你窗、改比例时不会露出黑帧。
    private func syncLayerSize() {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if clipLayer.contentsScale != scale { clipLayer.contentsScale = scale }
        if glLayer.contentsScale != scale { glLayer.contentsScale = scale }
        if glLayer.frame != bounds { glLayer.frame = bounds }
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        syncLayerSize()
        glLayer.setNeedsDisplay()
    }

    func setCornerRadius(_ r: CGFloat, animated: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(!animated)
        if animated {
            let a = CASpringAnimation(keyPath: "cornerRadius")
            a.fromValue = clipLayer.presentation()?.cornerRadius ?? clipLayer.cornerRadius
            a.toValue = r
            a.mass = 1; a.stiffness = 260; a.damping = 30
            a.duration = a.settlingDuration
            a.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
            clipLayer.add(a, forKey: "cr")
        }
        clipLayer.cornerRadius = r
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
    }
    override var mouseDownCanMoveWindow: Bool { false }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    // MARK: 拖放（画面是 AppKit 视图，SwiftUI 的 onDrop 收不到，这里直接接）
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard Self.fileURLs(sender.draggingPasteboard).isEmpty == false else { return [] }
        onDragHover?(true); return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingExited(_ sender: NSDraggingInfo?) { onDragHover?(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { onDragHover?(false) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(sender.draggingPasteboard)
        onDragHover?(false)
        guard !urls.isEmpty else { return false }
        onDropURLs?(urls); return true
    }
    static func fileURLs(_ pb: NSPasteboard) -> [URL] {
        (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }
}

struct VideoSurfaceRepresentable: NSViewRepresentable {
    let surface: VideoSurfaceView
    var cornerRadius: CGFloat
    func makeNSView(context: Context) -> VideoSurfaceView { surface }
    func updateNSView(_ v: VideoSurfaceView, context: Context) {
        if abs(v.clipLayer.cornerRadius - cornerRadius) > 0.5 { v.setCornerRadius(cornerRadius, animated: true) }
    }
}
