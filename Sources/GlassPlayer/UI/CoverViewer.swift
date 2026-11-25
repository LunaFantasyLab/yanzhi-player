// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import QuartzCore
import ImageIO
import CoreImage
import AVFoundation
import PlayerCore

/// 封面观赏模式（TANCO 2026-11-20）：把专辑封面放到最大看，可缩放、拖动，也能一步步退出来。
/// TANCO 拍板：不要任何手势，全部鼠标 + 键盘可用；双击进入观赏，单击翻面。
/// 18:15 补充：观赏里单击封面（无论是否放大）立即飞回原入口，点空白也退出；拖动超过数个像素只平移。观赏内双击不再切换适应/原图，缩放用滚轮和 ⌘+ ⌘− ⌘0，右键保留「原图 100% / 适应窗口」。
///
/// 结构：观赏层（CoverViewerView，纯 CALayer + 帧时钟逐帧驱动）一直挂在窗口最上面、平时隐藏；
/// 打开时不新建任何视图，只把封面从卡片 / 播放栏小图标的位置飞到居中。
/// 菜单、RootView 都不读观赏状态（第 8 轮查到：菜单跟着状态重建会卡一帧），只有观赏层自己和“隐藏原封面”的小修饰读。

/// 观赏是从哪里打开的（退出时飞回哪里）
enum ViewerSource: String {
    case carousel   // 轮播里的专辑卡封面
    case lifted     // 翻到背面（简介与歌词）的中间卡：从整张卡飞出
    case playbar    // 播放栏的小封面
    case playlist   // 播放列表某一行（右键「观赏封面」）：从那一行的小封面飞出
    case mini       // 迷你窗的封面：先回到大窗口再观赏，退出时回到迷你窗
}

@MainActor
@Observable
final class CoverViewerModel {
    /// 观赏层是否显示（含飞入、飞出过程）
    private(set) var isOpen = false
    /// 关闭按钮是否显示（鼠标静止几秒后淡出）
    var chromeVisible = true
    /// 正在被“拿走”的原封面（位置键，如 card:<id>、playbar）：原位置先隐藏，飞回落地后再出现，看起来是同一张图
    private(set) var hiddenKey: String?

    @ObservationIgnored var source: ViewerSource = .carousel
    @ObservationIgnored var itemID: String?
    /// 各入口封面在窗口里的位置（SwiftUI 全局坐标，左上为原点）和圆角。键：card:<id>（中间卡封面）、lifted:<id>、playbar、row:<id>、mini
    @ObservationIgnored var rects: [String: (rect: CGRect, radius: CGFloat)] = [:]
    /// 轮播区域在窗口里的位置（算旁边卡片的位置用）
    @ObservationIgnored var carouselFrame: CGRect = .zero
    @ObservationIgnored weak var view: CoverViewerView?
    /// 全屏是观赏模式里按 F 进的：退出观赏时一并退出全屏
    @ObservationIgnored var fullscreenByViewer = false
    /// 从迷你窗进来的：退出后回到迷你窗
    @ObservationIgnored var restoreMini = false
    @ObservationIgnored var closing = false
    @ObservationIgnored var opening = false
    @ObservationIgnored var openingSince: CFTimeInterval = 0
    @ObservationIgnored private var chromeWork: Task<Void, Never>?

    func setOpen(_ on: Bool) { if isOpen != on { isOpen = on } }
    func hide(_ k: String?) { if hiddenKey != k { hiddenKey = k } }

    /// 鼠标动了：关闭按钮浮现，静止 2.5 秒后淡出（光标也一起藏起来，动一下就回来）
    func poke() {
        if !chromeVisible { withAnimation(.easeInOut(duration: 0.25)) { chromeVisible = true } }
        chromeWork?.cancel()
        chromeWork = after(2.5) { [weak self] in
            guard let self, self.isOpen, !self.closing else { return }
            withAnimation(.easeInOut(duration: 0.45)) { self.chromeVisible = false }
            if !TestHooks.active { NSCursor.setHiddenUntilMouseMoves(true) }
        }
    }
    func stopChromeTimer() { chromeWork?.cancel(); chromeWork = nil }
}

// MARK: - 原图（最高分辨率）

enum FullCover {
    /// 真·原图无损解码（不走缩略图捷径；≤ 8000px 且无 EXIF 旋转时直出原生主图，超 8000px 才压到 8000）
    nonisolated static func decodeFull(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = (props?[kCGImagePropertyPixelWidth] as? Int) ?? 0
        let h = (props?[kCGImagePropertyPixelHeight] as? Int) ?? 0
        let orient = (props?[kCGImagePropertyOrientation] as? Int) ?? 1
        if w > 0, h > 0, max(w, h) <= 8000, orient == 1 {
            let fullOpts: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
            if let full = CGImageSourceCreateImageAtIndex(src, 0, fullOpts as CFDictionary) {
                return full
            }
        }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: max(1, min(8000, max(w, h))),
                                     kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceShouldCacheImmediately: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    /// 文件自带的封面：优先本地侧车自定义封面，其次重新读出原始字节（内嵌 → FFmpeg → 同目录图片），最高保留 8K 原图
    nonisolated static func fileCoverData(_ url: URL) async -> Data? {
        if let custom = CustomTags.shared.entry(for: url) {
            if custom.coverRemoved { return nil }
            if let d = CustomTags.shared.coverData(for: url), decodeFull(d) != nil { return d }
        }
        let asset = AVURLAsset(url: url)
        if let common = try? await asset.load(.commonMetadata) {
            for m in common where m.commonKey == .commonKeyArtwork {
                if let d = try? await m.load(.dataValue), decodeFull(d) != nil { return d }
            }
        }
        if let p = FFmpegProbe.probe(url), let d = p.coverData, decodeFull(d) != nil { return d }
        let dir = url.deletingLastPathComponent()
        if let list = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            let images = list.filter { MediaFormats.imageExts.contains($0.pathExtension.lowercased()) }
            let stem = url.deletingPathExtension().lastPathComponent.lowercased()
            var pick = images.first { $0.deletingPathExtension().lastPathComponent.lowercased() == stem }
            if pick == nil { for n in MediaFormats.coverNames { if let h = images.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == n }) { pick = h; break } } }
            if pick == nil, images.count == 1 { pick = images[0] }
            if let u = pick, let d = try? Data(contentsOf: u) { return d }
        }
        return nil
    }
}

// MARK: - 观赏层（AppKit）

@MainActor
final class CoverViewerView: NSView {
    weak var player: PlayerController?
    private var model: CoverViewerModel? { player?.viewer }

    private let backdrop = CALayer()       // 86 档重度模糊专辑背景（预先算好，不在帧里模糊）
    private let oldBackdrop = CALayer()    // 切歌时交叉淡出的旧背景
    private let flowLights: [CAGradientLayer] = (0..<3).map { _ in CAGradientLayer() } // 鉴赏背景缓慢游弋的柔光晕
    private let tint = CALayer()           // 黑色压暗 veil（86：base 0.16 + 微弱呼吸）
    private let wash = CAGradientLayer()   // 底部无边框软暗带，只为字可读，不是玻璃板
    private let host = CALayer()           // 阴影
    private let playHaloLayer = CALayer()  // 播放中专辑外圈同步呼吸柔光（与卡片轮播相位/色温一致）
    private let imageLayer = CALayer()     // 封面
    private let oldImage = CALayer()       // 切歌时交叉淡出的旧封面
    private let playRimLayer = CAShapeLayer() // 播放中专辑边缘纤细琉璃光圈
    private var playGlowLevel: Double = 0  // 0..1 柔和平滑过渡，暂停时缓缓呼出熄灭
    private var flowPhase: Double = 0      // 背景流光时间累积（播放时略活跃，暂停时静谧缓流）

    private(set) var image: CGImage?
    private var pixelSize = CGSize(width: 1, height: 1)
    private(set) var isFullRes = false
    private(set) var scale: CGFloat = 1          // 每个图像像素显示成多少点
    private(set) var origin: CGPoint = .zero     // 图像左上角在视图里的位置（左上为原点）
    private var cornerRadius: CGFloat = 4
    /// 与 CoverCard 封面一致：卡片外圆角 side×0.085，封面边长 side−2×pad（pad=side×0.045 → 0.91×side），封面圆角为外圆角的 0.62。
    static let coverCornerRatio: CGFloat = 0.085 * 0.62 / 0.91
    static func coverCornerRadius(displayedSide: CGFloat) -> CGFloat { max(0, displayedSide * coverCornerRatio) }

    private enum Phase { case idle, flyingIn, open, flyingOut }
    private var phase: Phase = .idle
    private var clock: UUID?
    private var waitFrames = 0

    // 飞入 / 飞出
    private var flyT: Double = 0
    private var flyFrom = CGRect.zero, flyTo = CGRect.zero
    private var flyR0: CGFloat = 0, flyR1: CGFloat = 4
    private var flyDone: (() -> Void)?
    private var backdropFrom: Float = 0, backdropTo: Float = 1

    // 缩放动画
    private var zoomAnim: (t: Double, s0: CGFloat, s1: CGFloat, o0: CGPoint, o1: CGPoint)?
    /// 用户要的是“适应窗口”（没放大）。改窗口大小、进出全屏、换上原图时都保持适应，不会因为中途尺寸变化变成“放大了”
    private var fitLocked = true
    // 拖动 + 惯性
    private var dragging = false, didDrag = false
    private var downPoint = CGPoint.zero, originAtDown = CGPoint.zero
    private var velocity = CGPoint.zero
    private var lastDragPoint = CGPoint.zero, lastDragTime: CFTimeInterval = 0
    private var momentum = false
    private var settling = false

    /// 测试用：最近一次切歌是否走了交叉淡入
    private(set) var lastCrossfade: CFTimeInterval = 0
    /// 测试用：最近一次惯性滑行的距离
    private(set) var lastMomentumDistance: CGFloat = 0
    /// 无真实封面（默认封面）时，背景用当前主题色，不拿生成图去模糊冒充专辑图
    private(set) var usesThemeFallback = false
    private var frostOutputSize: CGSize = .zero
    private var breathToken: UUID?
    private var chromeHost: PassThroughHostingView<AnyView>?
    private var chromeGesture: ChromeHit?
    private var chromeDown = false
    private var chromeLockUntil: CFTimeInterval = 0

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        let root = CALayer()
        root.masksToBounds = true
        layer = root
        for l in [backdrop, oldBackdrop] {
            l.contentsGravity = .resizeAspectFill
            l.magnificationFilter = .linear; l.minificationFilter = .trilinear
            l.opacity = 0
            root.addSublayer(l)
        }
        for fl in flowLights {
            fl.type = .radial
            fl.startPoint = CGPoint(x: 0.5, y: 0.5)
            fl.endPoint = CGPoint(x: 1.0, y: 1.0)
            fl.locations = [0.0, 0.46, 1.0]
            fl.opacity = 0
            root.addSublayer(fl)
        }
        tint.opacity = 0
        tint.backgroundColor = NSColor.black.cgColor
        root.addSublayer(tint)
        wash.colors = [NSColor.clear.cgColor, NSColor(white: 0, alpha: ViewerFrost.washAlpha).cgColor]
        wash.startPoint = CGPoint(x: 0.5, y: 0)
        wash.endPoint = CGPoint(x: 0.5, y: 1)
        wash.opacity = 0
        root.addSublayer(wash)
        host.shadowColor = NSColor.black.cgColor
        host.shadowOpacity = 0
        host.shadowRadius = 34
        host.shadowOffset = CGSize(width: 0, height: 14)
        root.addSublayer(host)
        playHaloLayer.cornerCurve = .continuous
        playHaloLayer.backgroundColor = NSColor.black.cgColor
        playHaloLayer.shadowOffset = .zero
        playHaloLayer.shadowOpacity = 0
        playHaloLayer.opacity = 0
        host.addSublayer(playHaloLayer)
        for l in [oldImage, imageLayer] {
            l.contentsGravity = .resizeAspectFill
            l.masksToBounds = true
            l.magnificationFilter = .linear; l.minificationFilter = .trilinear
            l.cornerCurve = .continuous
            host.addSublayer(l)
        }
        playRimLayer.fillColor = nil
        playRimLayer.lineWidth = 1.4
        playRimLayer.opacity = 0
        host.addSublayer(playRimLayer)
        oldImage.opacity = 0
        isHidden = true
        disableActions()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func disableActions() {
        let none: [String: CAAction] = ["position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "contents": NSNull(), "opacity": NSNull(),
                                        "cornerRadius": NSNull(), "shadowPath": NSNull(), "shadowOpacity": NSNull(), "shadowRadius": NSNull(),
                                        "shadowColor": NSNull(), "backgroundColor": NSNull(), "hidden": NSNull(), "path": NSNull(),
                                        "strokeColor": NSNull(), "colors": NSNull()]
        for l in [backdrop, oldBackdrop, tint, wash, host, playHaloLayer, imageLayer, oldImage, playRimLayer] + flowLights { l.actions = none }
    }

    private var tracking: NSTrackingArea?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, tracking == nil else { return }
        let ta = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(ta); tracking = ta
    }

    /// 空白处仍由本视图接收（单击退出）；前景控件交给子视图上的 NSHostingView，避免窗口态把点击全部吞掉。
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, phase != .idle else { return nil }
        return super.hitTest(point)
    }

    // MARK: 几何

    private var margins: NSEdgeInsets {
        let full = window?.styleMask.contains(.fullScreen) ?? false
        return full ? NSEdgeInsets(top: 28, left: 28, bottom: 28, right: 28) : NSEdgeInsets(top: 56, left: 44, bottom: 40, right: 44)
    }
    private var backing: CGFloat { window?.backingScaleFactor ?? 2 }
    /// 适应态：第一款右侧小封面（正方形），不再把原图铺满窗口。缩放仍可进入检视。
    var schemeLayout: ViewerFrost.Layout { ViewerFrost.layout(inWidth: Double(bounds.width), height: Double(bounds.height)) }
    func schemeCoverRect() -> CGRect {
        let L = schemeLayout
        return CGRect(x: L.cover.x, y: L.cover.y, width: L.cover.size, height: L.cover.size)
    }
    var fitScale: CGFloat { schemeCoverRect().width / max(pixelSize.width, 0.0001) }
    /// 检视态（放大后平移 / 以指针为中心缩放）仍按「整张图适应窗口」计算，这样画面才能大于窗口。
    var inspectFitScale: CGFloat {
        let m = margins
        let aw = max(40, bounds.width - m.left - m.right), ah = max(40, bounds.height - m.top - m.bottom)
        return min(aw / pixelSize.width, ah / pixelSize.height, 2 / backing)
    }
    /// 原图 100%：一个图像像素 = 一个屏幕像素
    var actualScale: CGFloat { 1 / backing }
    /// 放大上限：原图 4 倍像素，至少是适应尺寸的 3 倍
    var maxScale: CGFloat { max(inspectFitScale * 3, 4 / backing) }
    var isZoomed: Bool { phase == .open && scale > fitScale * 1.01 }
    var zoomFactor: CGFloat { scale / max(fitScale, 0.0001) }
    var imageRect: CGRect {
        if phase == .open && fitLocked && scale <= fitScale * 1.01 { return schemeCoverRect() }
        return CGRect(origin: origin, size: CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale))
    }
    var isLowRes: Bool { fitScale >= 2 / backing - 0.0001 && (min((bounds.width - margins.left - margins.right) / pixelSize.width, (bounds.height - margins.top - margins.bottom) / pixelSize.height) > 2 / backing) }
    var pixelInfo: String { "原图 \(Int(pixelSize.width)) × \(Int(pixelSize.height)) 像素" + (isLowRes ? "（小图，按原样显示，不硬拉大）" : "") }

    private func centeredOrigin(_ s: CGFloat) -> CGPoint {
        CGPoint(x: (bounds.width - pixelSize.width * s) / 2, y: (bounds.height - pixelSize.height * s) / 2 + (margins.top - margins.bottom) / 2)
    }
    private func fitRect() -> CGRect { schemeCoverRect() }
    private func fitOrigin() -> CGPoint { schemeCoverRect().origin }

    /// 平移的合法范围：图比窗口小的方向居中，比窗口大的方向不露边
    private func bounds(for s: CGFloat) -> (x: ClosedRange<CGFloat>, y: ClosedRange<CGFloat>) {
        let w = pixelSize.width * s, h = pixelSize.height * s
        let c = centeredOrigin(s)
        let xr: ClosedRange<CGFloat> = w <= bounds.width ? c.x...c.x : (bounds.width - w)...0
        let yr: ClosedRange<CGFloat> = h <= bounds.height ? c.y...c.y : (bounds.height - h)...0
        return (xr, yr)
    }
    private func clamp(_ o: CGPoint, _ s: CGFloat) -> CGPoint {
        let b = bounds(for: s)
        return CGPoint(x: min(max(o.x, b.x.lowerBound), b.x.upperBound), y: min(max(o.y, b.y.lowerBound), b.y.upperBound))
    }
    /// 越界阻尼（橡皮筋）：越拉越费劲
    private func rubber(_ v: CGFloat, _ r: ClosedRange<CGFloat>, _ dim: CGFloat) -> CGFloat {
        func f(_ x: CGFloat) -> CGFloat { (1 - 1 / (x * 0.55 / max(dim, 1) + 1)) * dim }
        if v < r.lowerBound { return r.lowerBound - f(r.lowerBound - v) }
        if v > r.upperBound { return r.upperBound + f(v - r.upperBound) }
        return v
    }

    private func toView(_ global: CGRect) -> CGRect {
        guard let w = window, let cv = w.contentView else { return global }
        let wr = CGRect(x: global.minX, y: cv.frame.height - global.maxY, width: global.width, height: global.height)
        return convert(wr, from: nil)
    }

    // MARK: 渲染

    private func apply(rect: CGRect? = nil, radius: CGFloat? = nil) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let sc = backing
        for l in [backdrop, oldBackdrop, tint, wash, host, playHaloLayer, imageLayer, oldImage, playRimLayer] + flowLights {
            if l.contentsScale != sc { l.contentsScale = sc }
        }
        let r = rect ?? imageRect
        host.frame = bounds
        imageLayer.frame = r
        let cr = radius ?? Self.coverCornerRadius(displayedSide: min(r.width, r.height))
        cornerRadius = cr
        imageLayer.cornerRadius = cr
        let rp = CGPath(roundedRect: r, cornerWidth: cr, cornerHeight: cr, transform: nil)
        host.shadowPath = rp
        // 同步呼吸光晕（略缩 1pt 藏于封面正后方）与封面边缘纤细光圈
        let haloRect = r.insetBy(dx: 1, dy: 1)
        playHaloLayer.frame = haloRect
        playHaloLayer.cornerRadius = max(0, cr - 1)
        playHaloLayer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: haloRect.size),
                                          cornerWidth: max(0, cr - 1), cornerHeight: max(0, cr - 1), transform: nil)
        playRimLayer.frame = bounds
        playRimLayer.path = CGPath(roundedRect: r.insetBy(dx: 0.7, dy: 0.7),
                                   cornerWidth: max(0, cr - 0.7), cornerHeight: max(0, cr - 0.7), transform: nil)
        let bg = bounds.insetBy(dx: -64, dy: -64)
        backdrop.frame = bg; oldBackdrop.frame = bg; tint.frame = bounds
        let washH = CGFloat(schemeLayout.washHeight)
        wash.frame = CGRect(x: 0, y: bounds.height - washH, width: bounds.width, height: washH)
        let fit = fitLocked && scale <= fitScale * 1.01
        host.shadowRadius = fit ? 10 : 34
        host.shadowOffset = fit ? CGSize(width: 0, height: 4) : CGSize(width: 0, height: 14)
        updateLivingAtmosphere(now: CACurrentMediaTime(), dt: 0)
        CATransaction.commit()
        syncChromeHost()
    }

    override func layout() {
        super.layout()
        relayout()
    }
    override func setFrameSize(_ newSize: NSSize) {
        let oldFit = phase == .open ? fitScale : 0, oldZoom = zoomFactor
        let oldCenter = phase == .open ? CGPoint(x: (bounds.midX - origin.x) / scale, y: (bounds.midY - origin.y) / scale) : .zero
        super.setFrameSize(newSize)
        guard phase == .open, oldFit > 0 else { apply(); return }
        // 改窗口大小（含进出全屏）：适应状态始终适应；放大状态保持“相对适应尺寸的倍数”和画面中心那一点不变，逐帧跟随，不闪
        if let z = zoomAnim { fitLocked = z.s1 <= fitScale * 1.001 && fitLocked }
        zoomAnim = nil
        scale = fitLocked ? fitScale : fitScale * max(1, oldZoom)
        if fitLocked || oldZoom <= 1.01 { origin = fitOrigin() }
        else { origin = clamp(CGPoint(x: bounds.midX - oldCenter.x * scale, y: bounds.midY - oldCenter.y * scale), scale) }
        if phase == .open { refreshFrostIfNeeded() }
        apply()
    }
    private func relayout() {
        if phase == .open && zoomAnim == nil && !dragging && !momentum && !settling {
            if fitLocked || scale <= fitScale * 1.01 || scale < fitScale { scale = fitScale; origin = fitOrigin() }
            else { origin = clamp(origin, scale) }
        }
        apply()
    }

    /// 窗口态 NSView 会盖住 SwiftUI 兄弟层：把底栏放进本视图的子 NSHostingView，才能与模糊背景同层可见、可点。
    private func installChromeHostIfNeeded() {
        guard chromeHost == nil, let player else { return }
        let root = AnyView(CoverViewerChrome().environment(player).ignoresSafeArea())
        let host = PassThroughHostingView(rootView: root)
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.isOpaque = false
        if #available(macOS 14.0, *) { host.safeAreaRegions = [] }
        addSubview(host)
        chromeHost = host
    }

    private func syncChromeHost() {
        installChromeHostIfNeeded()
        let show = phase == .open && !isFlying && !isZoomed && !(player?.viewer.closing ?? false)
        chromeHost?.isHidden = !show
        if show { chromeHost?.frame = bounds }
    }

    private enum ChromeHit { case prev, play, next, loop, progress }

    /// 窗口态 SwiftUI 控件没有独立 NSView，HostingView.hitTest 会落到本视图。这里按几何处理真实点击，避免变成单击退出。
    private func chromeHit(at p: CGPoint) -> ChromeHit? {
        guard phase == .open, !isFlying, !isZoomed, !(player?.viewer.closing ?? false), chromeHost?.isHidden == false else { return nil }
        let L = schemeLayout
        let hitH = max(L.progressThickness + 8, ViewerFrost.progressHitHeight(L, windowHeight: Double(bounds.height)))
        let prog = CGRect(x: L.progress.x, y: L.progress.y - (hitH - L.progressThickness) / 2, width: L.progress.width, height: max(hitH, 1))
        if prog.contains(p) { return .progress }
        let gap = (L.controlRow.width - 4 * L.controlHit) / 3
        for i in 0..<4 {
            let x = L.controlRow.x + Double(i) * (L.controlHit + gap)
            let r = CGRect(x: x, y: L.controlRow.y, width: L.controlHit, height: L.controlRow.height)
            if r.contains(p) {
                return [.prev, .play, .next, .loop][i]
            }
        }
        return nil
    }

    private func chromeTime(at p: CGPoint) -> Double? {
        let L = schemeLayout
        let dur = max(0, player?.duration ?? 0)
        guard dur > 0, L.progress.width > 1 else { return nil }
        let frac = min(max(0, (Double(p.x) - L.progress.x) / L.progress.width), 1)
        return frac * dur
    }

    private func performChrome(_ hit: ChromeHit, at p: CGPoint, ended: Bool) {
        guard let player else { return }
        switch hit {
        case .prev: if ended { player.scanButtonTapped(-1) }
        case .play: if ended { player.togglePlay() }
        case .next: if ended { player.scanButtonTapped(1) }
        case .loop: if ended { player.cycleRepeat() }
        case .progress:
            guard let t = chromeTime(at: p) else { return }
            if ended {
                if player.isScrubbing { player.endScrub(at: t) } else { player.seek(to: t) }
            } else if player.isScrubbing {
                player.scrub(to: t)
            } else {
                player.beginScrub(); player.scrub(to: t)
            }
        }
    }

    private func applyTheme() {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tint.backgroundColor = NSColor.black.cgColor
        host.shadowColor = NSColor.black.cgColor
        CATransaction.commit()
        refreshLivingColors()
    }

    /// 刷新背景流动光斑色与封面呼吸灯色（贴合当前专辑主色或整体配色主题）
    func refreshLivingColors() {
        guard let p = player else { return }
        let artPal = p.current.flatMap { p.art(for: $0)?.palette }
        let useCover = !usesThemeFallback && artPal != nil
        let pal: AmbientPalette = {
            if useCover, let ap = artPal { return ap }
            return ViewerFrost.fallbackPalette(theme: p.theme, systemDark: !p.look.isLight, coverPalette: p.palette)
        }()
        let glowRGB = PlayingBreathGlow.rgb(artPalette: artPal, appPalette: p.palette, followCover: p.theme.followsCover || useCover)
        let orbRGBs: [RGB] = [pal.accent, pal.tertiary, pal.secondary]
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for (i, fl) in flowLights.enumerated() {
            let c = orbRGBs[i % orbRGBs.count]
            let c0 = CGColor(srgbRed: min(1, c.r * 1.08 + 0.08), green: min(1, c.g * 1.08 + 0.08), blue: min(1, c.b * 1.08 + 0.08), alpha: 0.42)
            let c1 = CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 0.16)
            let c2 = CGColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 0.0)
            fl.colors = [c0, c1, c2]
        }
        let glowCG = CGColor(srgbRed: glowRGB.r, green: glowRGB.g, blue: glowRGB.b, alpha: 1)
        playHaloLayer.shadowColor = glowCG
        CATransaction.commit()
    }

    /// 逐帧更新鉴赏模式「缓慢流动光效」+「与卡片轮播同频同步的呼吸光圈」
    private func updateLivingAtmosphere(now: CFTimeInterval, dt: Double) {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let playing = player?.isPlaying ?? false
        let backdropVis = Double(backdrop.opacity)
        if !reduce && dt > 0 {
            flowPhase += dt * (playing ? 1.0 : 0.42)
        }
        let t = flowPhase
        let w = bounds.width, h = bounds.height
        if w > 10 && h > 10 {
            // 1. 背景极缓慢的有机微漂移（不露边，让原本静态的模糊封面活起来）
            let dx = reduce ? 0 : CGFloat(sin(t * 0.23) * 18.0)
            let dy = reduce ? 0 : CGFloat(cos(t * 0.17) * 14.0)
            let baseBG = bounds.insetBy(dx: -64, dy: -64)
            backdrop.frame = baseBG.offsetBy(dx: dx, dy: dy)

            // 2. 三团大尺度柔光晕沿非重复利萨如轨迹缓慢游弋
            let diag = max(w, h)
            let specs: [(cx: Double, cy: Double, ax: Double, ay: Double, fx: Double, fy: Double, size: Double, alpha: Double)] = [
                (0.24, 0.30, 0.20, 0.16, 0.39, 0.27, 0.78, 0.56),
                (0.76, 0.64, 0.18, 0.18, -0.29, 0.33, 0.72, 0.48),
                (0.52, 0.24, 0.24, 0.14, 0.21, -0.25, 0.66, 0.40),
            ]
            for (i, fl) in flowLights.enumerated() {
                let s = specs[i]
                let px = w * CGFloat(s.cx + (reduce ? 0 : sin(t * s.fx + Double(i) * 2.1) * s.ax))
                let py = h * CGFloat(s.cy + (reduce ? 0 : cos(t * s.fy + Double(i) * 1.4) * s.ay))
                let pulse = reduce ? 1.0 : (0.92 + 0.08 * sin(t * 0.45 + Double(i) * 1.9))
                let side = diag * CGFloat(s.size * pulse)
                fl.frame = CGRect(x: px - side / 2, y: py - side / 2, width: side, height: side)
                let shimmer = reduce ? 1.0 : (0.82 + 0.18 * sin(t * 0.52 + Double(i) * 2.3))
                fl.opacity = Float(s.alpha * shimmer * backdropVis)
            }
        }

        // 3. 专辑封面外圈呼吸灯（与 CoverCarousel 完全同源 PlayingBreathGlow）
        let targetGlow = (phase == .open && playing && !isZoomed) ? 1.0 : 0.0
        if dt > 0 {
            let k = 1.0 - exp(-dt * 4.5)
            playGlowLevel += (targetGlow - playGlowLevel) * k
            if abs(playGlowLevel - targetGlow) < 0.002 { playGlowLevel = targetGlow }
        } else if phase == .idle {
            playGlowLevel = 0
        }
        if playGlowLevel > 0.002, let p = player {
            let b = PlayingBreathGlow.breath(at: now)
            let artPal = p.current.flatMap { p.art(for: $0)?.palette }
            let useCover = !usesThemeFallback && artPal != nil
            let glowRGB = PlayingBreathGlow.rgb(artPalette: artPal, appPalette: p.palette, followCover: p.theme.followsCover || useCover)
            let rimA = PlayingBreathGlow.rimAlpha(breath: b) * playGlowLevel
            let haloA = PlayingBreathGlow.haloOpacity(breath: b) * playGlowLevel
            let haloR = PlayingBreathGlow.haloRadius(breath: b, scale: 1.08)
            playHaloLayer.opacity = Float(playGlowLevel)
            playHaloLayer.shadowColor = CGColor(srgbRed: glowRGB.r, green: glowRGB.g, blue: glowRGB.b, alpha: 1)
            playHaloLayer.shadowRadius = haloR
            playHaloLayer.shadowOpacity = Float(haloA)
            playRimLayer.opacity = 1
            playRimLayer.strokeColor = CGColor(srgbRed: min(1, glowRGB.r * 0.85 + 0.15),
                                               green: min(1, glowRGB.g * 0.85 + 0.15),
                                               blue: min(1, glowRGB.b * 0.85 + 0.15),
                                               alpha: rimA)
        } else {
            playHaloLayer.opacity = 0
            playHaloLayer.shadowOpacity = 0
            playRimLayer.opacity = 0
        }
    }

    // MARK: 打开 / 关闭

    /// 从 fromGlobal（入口封面在窗口里的位置）飞到右侧小封面
    func open(image img: CGImage, backdrop bd: CGImage, fromGlobal: CGRect?, radius: CGFloat, isDefaultCover: Bool = false) {
        guard let player else { return }
        image = img
        pixelSize = CGSize(width: img.width, height: img.height)
        isFullRes = false
        usesThemeFallback = isDefaultCover || ViewerFrost.usesThemeFallbackBackground(isDefaultCover: isDefaultCover, hasCoverImage: true)
        zoomAnim = nil; momentum = false; settling = false; dragging = false
        applyTheme()
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.contents = img; imageLayer.opacity = 1
        oldImage.opacity = 0; oldBackdrop.opacity = 0
        backdrop.contents = makeFrost(from: img, fallback: usesThemeFallback); backdrop.opacity = 0
        tint.opacity = 0; wash.opacity = 0; host.shadowOpacity = 0
        CATransaction.commit()
        isHidden = false
        phase = .flyingIn
        fitLocked = true
        scale = fitScale; origin = fitOrigin()
        let target = fitRect()
        var from = fromGlobal.map(toView) ?? CGRect(x: target.midX - 60, y: target.midY - 60, width: 120, height: 120)
        if from.width < 4 || !bounds.intersects(from) { from = CGRect(x: target.midX - 60, y: target.midY - 60, width: 120, height: 120) }
        flyFrom = from; flyTo = target; flyR0 = radius
        flyR1 = Self.coverCornerRadius(displayedSide: min(target.width, target.height))
        backdropFrom = 0; backdropTo = 1
        flyT = 0
        flyDone = { [weak self] in
            guard let self else { return }
            self.phase = .open
            self.scale = self.fitScale; self.origin = self.fitOrigin()
            self.apply()
            self.startBreath()
            self.player?.viewer.opening = false
        }
        apply(rect: from, radius: radius)
        window?.makeFirstResponder(self)
        startClock()
        player.viewer.poke()
    }

    /// 换成更清晰的原图（同一张图，只是分辨率更高；位置大小不变）
    func upgrade(to full: CGImage) {
        guard phase != .idle else { return }
        let oldW = pixelSize.width
        CATransaction.begin(); CATransaction.setDisableActions(true)
        imageLayer.contents = full
        CATransaction.commit()
        image = full
        let k = oldW / CGFloat(full.width)
        pixelSize = CGSize(width: full.width, height: full.height)
        scale *= k
        if var z = zoomAnim { z.s0 *= k; z.s1 *= k; zoomAnim = z }
        isFullRes = true
        if phase == .open { if fitLocked && zoomAnim == nil || scale < fitScale * 1.01 { scale = fitScale; origin = centeredOrigin(scale) }; apply() }
        else if phase == .flyingIn { flyTo = fitRect() }
    }

    /// 切歌：新封面在适应尺寸上淡入，旧的淡出；背景一起换
    func crossfade(to img: CGImage, backdrop bd: CGImage, isDefaultCover: Bool = false) {
        guard phase == .open || phase == .flyingIn else { return }
        let oldRect = imageRect
        CATransaction.begin(); CATransaction.setDisableActions(true)
        oldImage.contents = imageLayer.contents; oldImage.frame = oldRect; oldImage.cornerRadius = cornerRadius; oldImage.opacity = 1
        oldBackdrop.contents = backdrop.contents; oldBackdrop.opacity = backdrop.opacity
        imageLayer.contents = img; imageLayer.opacity = 0
        usesThemeFallback = isDefaultCover || ViewerFrost.usesThemeFallbackBackground(isDefaultCover: isDefaultCover, hasCoverImage: true)
        backdrop.contents = makeFrost(from: img, fallback: usesThemeFallback)
        CATransaction.commit()
        refreshLivingColors()
        image = img; pixelSize = CGSize(width: img.width, height: img.height); isFullRes = false
        zoomAnim = nil; momentum = false; settling = false
        if phase == .open { scale = fitScale; origin = fitOrigin(); apply(); startBreath() }
        else { flyTo = fitRect() }
        // 交叉淡入：Core Animation 在渲染端锁定 120Hz 逐帧插值
        for (l, from, to) in [(imageLayer, Float(0), Float(1)), (oldImage, Float(1), Float(0)), (oldBackdrop, oldBackdrop.opacity, Float(0))] {
            let a = CABasicAnimation(keyPath: "opacity"); a.fromValue = from; a.toValue = to; a.duration = 0.5
            a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            a.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
            l.add(a, forKey: "xfade"); l.opacity = to
        }
        lastCrossfade = CACurrentMediaTime()
    }

    /// 飞回 toGlobal（入口位置）。没有位置就原地缩小淡出
    func close(toGlobal: CGRect?, radius: CGFloat, done: @escaping () -> Void) {
        guard phase != .idle else { done(); return }
        stopBreath(veil: 0)
        zoomAnim = nil; momentum = false; settling = false; dragging = false
        let fromRect = phase == .flyingIn ? currentFlyRect() : imageRect
        let cur = fromRect
        var to = toGlobal.map(toView) ?? CGRect(x: cur.midX - cur.width * 0.1, y: cur.midY - cur.height * 0.1, width: cur.width * 0.2, height: cur.height * 0.2)
        if to.width < 4 || !bounds.intersects(to) { to = CGRect(x: cur.midX - cur.width * 0.1, y: cur.midY - cur.height * 0.1, width: cur.width * 0.2, height: cur.height * 0.2) }
        phase = .flyingOut
        flyFrom = cur; flyTo = to; flyR0 = cornerRadius; flyR1 = radius
        backdropFrom = backdrop.opacity; backdropTo = 0
        flyT = 0
        oldImage.removeAllAnimations(); oldImage.opacity = 0
        flyDone = { [weak self] in
            guard let self else { return }
            // 原封面先回来，观赏层再隐藏两帧后再撤（避免中间空一帧）
            self.player?.viewer.hide(nil)
            self.waitFrames = 2
            self.afterWait = { [weak self] in
                guard let self else { return }
                self.phase = .idle
                self.isHidden = true
                CATransaction.begin(); CATransaction.setDisableActions(true)
                self.imageLayer.contents = nil; self.oldImage.contents = nil; self.backdrop.contents = nil; self.oldBackdrop.contents = nil
                for fl in self.flowLights { fl.opacity = 0 }
                self.playHaloLayer.opacity = 0; self.playHaloLayer.shadowOpacity = 0; self.playRimLayer.opacity = 0; self.playGlowLevel = 0
                CATransaction.commit()
                self.image = nil
                done()
            }
        }
        startClock()
    }
    private var afterWait: (() -> Void)?

    private func currentFlyRect() -> CGRect {
        let x = CGFloat(ease(flyT, omega: phase == .flyingOut ? 13 : 12))
        return lerp(flyFrom, flyTo, x)
    }
    private func ease(_ t: Double, omega w: Double) -> Double { t <= 0 ? 0 : min(1, 1 - (1 + w * t) * exp(-w * t)) }
    private func lerp(_ a: CGRect, _ b: CGRect, _ x: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * x, y: a.minY + (b.minY - a.minY) * x, width: a.width + (b.width - a.width) * x, height: a.height + (b.height - a.height) * x)
    }

    // MARK: 帧时钟

    private func startClock() {
        guard clock == nil else { return }
        clock = FrameClock.shared.subscribe { [weak self] dt, _ in
            guard let self else { return false }
            let more = self.step(dt)
            if !more { self.clock = nil }
            return more
        }
    }

    private func step(_ dt: Double) -> Bool {
        var active = false
        if waitFrames > 0 {
            waitFrames -= 1
            if waitFrames == 0, let f = afterWait { afterWait = nil; f() }
            return waitFrames > 0 || phase != .idle && (zoomAnim != nil || momentum || settling)
        }
        switch phase {
        case .flyingIn, .flyingOut:
            flyT += dt
            let w = phase == .flyingOut ? 13.0 : 12.0
            let x = CGFloat(ease(flyT, omega: w))
            if phase == .flyingIn {
                flyTo = fitRect()   // 飞的途中窗口变了也对准新的位置与圆角
                flyR1 = Self.coverCornerRadius(displayedSide: min(flyTo.width, flyTo.height))
            }
            let r = lerp(flyFrom, flyTo, x)
            let a = backdropFrom + (backdropTo - backdropFrom) * Float(min(1, x * 1.15))
            CATransaction.begin(); CATransaction.setDisableActions(true)
            backdrop.opacity = a
            tint.opacity = a * Float(ViewerFrost.veilBase)
            wash.opacity = a
            host.shadowOpacity = 0.28 * a
            CATransaction.commit()
            apply(rect: r, radius: flyR0 + (flyR1 - flyR0) * x)
            if flyT >= (phase == .flyingOut ? 0.52 : 0.6) {
                apply(rect: flyTo, radius: flyR1)
                let f = flyDone; flyDone = nil; f?()
                return waitFrames > 0 || zoomAnim != nil || phase == .open
            }
            return true
        case .idle: return false
        case .open: break
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        updateLivingAtmosphere(now: CACurrentMediaTime(), dt: dt)
        CATransaction.commit()
        if var z = zoomAnim {
            z.t += dt
            let x = CGFloat(ease(z.t, omega: 15))
            scale = z.s0 + (z.s1 - z.s0) * x
            origin = CGPoint(x: z.o0.x + (z.o1.x - z.o0.x) * x, y: z.o0.y + (z.o1.y - z.o0.y) * x)
            if z.t >= 0.5 { scale = z.s1; origin = z.o1; zoomAnim = nil } else { zoomAnim = z; active = true }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            backdrop.opacity = 1
            if zoomAnim == nil { self.startBreath() } else { self.stopBreath(veil: ViewerFrost.veilBase) }
            wash.opacity = 1
            CATransaction.commit()
            apply()
        }
        if momentum {
            origin.x += velocity.x * CGFloat(dt); origin.y += velocity.y * CGFloat(dt)
            lastMomentumDistance += hypot(velocity.x, velocity.y) * CGFloat(dt)
            let decay = CGFloat(pow(0.135, dt))   // 和系统滚动手感接近的衰减
            velocity.x *= decay; velocity.y *= decay
            let b = bounds(for: scale)
            // 撞到边：这一方向停下，交给回弹
            if !b.x.contains(origin.x) { velocity.x *= CGFloat(pow(0.0001, dt)) }
            if !b.y.contains(origin.y) { velocity.y *= CGFloat(pow(0.0001, dt)) }
            if hypot(velocity.x, velocity.y) < 8 { momentum = false; settling = true }
            active = true
            apply()
        }
        if settling && !momentum {
            let target = clamp(origin, scale)
            let k = CGFloat(1 - exp(-dt * 14))
            origin.x += (target.x - origin.x) * k; origin.y += (target.y - origin.y) * k
            if abs(target.x - origin.x) < 0.3 && abs(target.y - origin.y) < 0.3 { origin = target; settling = false } else { active = true }
            apply()
        }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let keepAmbient = phase == .open && (!reduce || playGlowLevel > 0.002 || (player?.isPlaying ?? false))
        return active || zoomAnim != nil || keepAmbient
    }

    // MARK: 缩放

    func zoom(to s1: CGFloat, at p: CGPoint?, animated: Bool) {
        guard phase == .open else { return }
        let s = min(max(s1, fitScale), maxScale)
        let leavingFit = fitLocked && s > fitScale * 1.001
        fitLocked = s <= fitScale * 1.001
        var o: CGPoint
        if fitLocked {
            o = fitOrigin()
        } else if leavingFit {
            // 离开适应态进入检视：先按「适应窗口」居中，再绕指针（或窗口中心）放到目标倍率，避免钉在右下小封面上。
            let base = inspectFitScale
            let from = centeredOrigin(base)
            let pt = p ?? CGPoint(x: bounds.midX, y: bounds.midY)
            o = CGPoint(x: pt.x - (pt.x - from.x) * (s / base), y: pt.y - (pt.y - from.y) * (s / base))
            o = clamp(o, s)
            if !animated { scale = base; origin = from }
        } else {
            let pt = p ?? CGPoint(x: bounds.midX, y: bounds.midY)
            o = CGPoint(x: pt.x - (pt.x - origin.x) * (s / scale), y: pt.y - (pt.y - origin.y) * (s / scale))
            o = clamp(o, s)
        }
        momentum = false; settling = false
        if animated {
            let fromS = leavingFit ? inspectFitScale : scale
            let fromO = leavingFit ? centeredOrigin(inspectFitScale) : origin
            if leavingFit { scale = fromS; origin = fromO }
            zoomAnim = (0, fromS, s, fromO, o); startClock()
        } else { zoomAnim = nil; scale = s; origin = o; apply() }
        if fitLocked { startBreath() } else { stopBreath(veil: ViewerFrost.veilBase) }
        player?.viewer.poke()
    }
    func zoomToFit(animated: Bool = true) { zoom(to: fitScale, at: nil, animated: animated) }
    func zoomToActual(at p: CGPoint? = nil) { zoom(to: max(actualScale, fitScale), at: p, animated: true) }
    func zoomStep(_ dir: Int) { zoom(to: scale * (dir > 0 ? 1.5 : 1 / 1.5), at: nil, animated: true) }
    /// 右键「原图 100% / 适应窗口」仍走 zoomToActual / zoomToFit。
    /// 18:15 起观赏内双击不再调用此方法（会和单击立即退出冲突）；保留实现以免误删已有缩放路径。
    func toggleZoom(at p: CGPoint) {
        if isZoomed { zoomToFit() }
        else { zoom(to: actualScale > fitScale * 1.2 ? actualScale : fitScale * 2.5, at: p, animated: true) }
    }

    /// 键盘平移（⌥ + 方向键，放大后才有用）：每按一下挪 12% 窗口，按住连续挪
    func panByKey(dx: CGFloat, dy: CGFloat) {
        guard isZoomed else { return }
        let o = clamp(CGPoint(x: origin.x - dx * bounds.width * 0.12, y: origin.y - dy * bounds.height * 0.12), scale)
        momentum = false; settling = false
        zoomAnim = (0, scale, scale, origin, o); startClock()
        player?.viewer.poke()
    }

    // MARK: 鼠标 / 触控板

    override func mouseMoved(with event: NSEvent) { if phase == .open { player?.viewer.poke() } }

    override func mouseDown(with e: NSEvent) {
        guard phase == .open else { return }
        player?.viewer.poke()
        let p = convert(e.locationInWindow, from: nil)
        downPoint = p; originAtDown = origin; lastDragPoint = p; lastDragTime = e.timestamp
        velocity = .zero; momentum = false; settling = false; zoomAnim = nil
        dragging = true; didDrag = false
        chromeGesture = chromeHit(at: p)
        chromeDown = chromeGesture != nil
        if chromeGesture == .progress { performChrome(.progress, at: p, ended: false) }
    }

    override func mouseDragged(with e: NSEvent) {
        guard phase == .open, dragging else { return }
        let p = convert(e.locationInWindow, from: nil)
        if chromeGesture == .progress {
            didDrag = true
            performChrome(.progress, at: p, ended: false)
            return
        }
        if chromeGesture != nil { return }
        if !didDrag && hypot(p.x - downPoint.x, p.y - downPoint.y) < 3 { return }
        didDrag = true
        guard isZoomed else { return }
        let b = bounds(for: scale)
        let raw = CGPoint(x: originAtDown.x + p.x - downPoint.x, y: originAtDown.y + p.y - downPoint.y)
        origin = CGPoint(x: rubber(raw.x, b.x, bounds.width), y: rubber(raw.y, b.y, bounds.height))
        let dt = max(0.001, e.timestamp - lastDragTime)
        let inst = CGPoint(x: (p.x - lastDragPoint.x) / dt, y: (p.y - lastDragPoint.y) / dt)
        velocity = CGPoint(x: velocity.x * 0.35 + inst.x * 0.65, y: velocity.y * 0.35 + inst.y * 0.65)
        lastDragPoint = p; lastDragTime = e.timestamp
        apply()
    }

    override func mouseUp(with e: NSEvent) {
        guard phase == .open else { return }
        let p = convert(e.locationInWindow, from: nil)
        let wasDrag = didDrag
        dragging = false
        // 按下发生在控件上则绝不退出；全屏里偶发第二次 mouseUp 也不能再走单击退出。
        if chromeDown || chromeGesture != nil || CACurrentMediaTime() < chromeLockUntil {
            if let hit = chromeGesture ?? chromeHit(at: p) {
                performChrome(hit, at: p, ended: true)
            }
            chromeGesture = nil
            chromeDown = false
            chromeLockUntil = CACurrentMediaTime() + 0.3
            return
        }
        if wasDrag {
            guard isZoomed || !bounds(for: scale).x.contains(origin.x) else { return }
            let still = e.timestamp - lastDragTime > 0.08
            if still { velocity = .zero }
            lastMomentumDistance = 0
            if hypot(velocity.x, velocity.y) > 30 { momentum = true } else { settling = true }
            startClock()
            return
        }
        // 18:15：单击（封面或空白、无论是否放大）立即退出并飞回原入口，不等待第二下。
        // 上面 wasDrag 已处理「拖动超过 3 点只平移、不退出」。
        player?.closeCoverViewer()
    }

    override func scrollWheel(with e: NSEvent) {
        guard phase == .open else { return }
        player?.viewer.poke()
        // 滚轮（触控板滚动等同滚轮）：以指针为中心缩放。系统惯性带来的余量不算，免得松手后还在自己缩放
        guard e.momentumPhase == [] else { return }
        wheel(dy: e.scrollingDeltaY, precise: e.hasPreciseScrollingDeltas, at: convert(e.locationInWindow, from: nil))
    }
    /// 滚轮一格 / 触控板滚动一段 → 以 p 为中心缩放（往上滚放大）
    func wheel(dy: CGFloat, precise: Bool, at p: CGPoint) {
        guard phase == .open else { return }
        let k = precise ? dy * 0.006 : dy * 0.12
        guard k != 0 else { return }
        zoom(to: scale * exp(k), at: p, animated: false)
    }
    /// 测试用：视图里的点 p 对应原图上的哪个像素
    func debugImagePoint(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale) }
    var debugOrigin: CGPoint { origin }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard phase == .open, let p = player else { return nil }
        return NSMenuBuilder.build(MenuCatalog.viewer(p))
    }

    // MARK: 86 档背景（预计算，换封面或窗口尺寸才重算）

    private func makeFrost(from img: CGImage, fallback: Bool) -> CGImage? {
        let size = bounds.size
        frostOutputSize = size
        let pal: AmbientPalette? = {
            guard fallback, let p = player else { return nil }
            return ViewerFrost.fallbackPalette(theme: p.theme, systemDark: p.look.isLight == false, coverPalette: p.palette)
        }()
        return ViewerFrostBackdrop.render(image: img, output: size, backing: backing, fallback: pal)
    }

    private func refreshFrostIfNeeded() {
        guard phase == .open, let img = image else { return }
        let size = bounds.size
        if abs(size.width - frostOutputSize.width) < 8 && abs(size.height - frostOutputSize.height) < 8 { return }
        backdrop.contents = makeFrost(from: img, fallback: usesThemeFallback)
        if !usesThemeFallback { startBreath() }
    }

    func startBreath() {
        stopBreath(veil: ViewerFrost.veilBase)
        tint.removeAnimation(forKey: "veil-breath")
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let playing = player?.isPlaying ?? false
        let base = ViewerFrost.veil(time: 0, playing: playing, reduceMotion: reduce)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tint.opacity = Float(base)
        wash.opacity = 1
        CATransaction.commit()
        if phase == .open { startClock() }
        guard !reduce, playing, !usesThemeFallback else { return }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = Float(ViewerFrost.veilBase)
        a.toValue = Float(ViewerFrost.veilBase + ViewerFrost.veilBreath)
        a.duration = ViewerFrost.breathPeriod / 2
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        a.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        a.isRemovedOnCompletion = false
        tint.add(a, forKey: "veil-breath")
    }

    func stopBreath(veil: Double) {
        tint.removeAnimation(forKey: "veil-breath")
        CATransaction.begin(); CATransaction.setDisableActions(true)
        tint.opacity = Float(veil)
        CATransaction.commit()
    }

    // MARK: 测试用

    func debugPan(by d: CGPoint, release velocityPerSec: CGPoint) {
        guard phase == .open else { return }
        origin = CGPoint(x: origin.x + d.x, y: origin.y + d.y)
        apply()
        velocity = velocityPerSec; lastMomentumDistance = 0
        momentum = hypot(velocity.x, velocity.y) > 30; settling = !momentum
        startClock()
    }
    var debugInBounds: Bool { let b = bounds(for: scale); return b.x.contains(origin.x) && b.y.contains(origin.y) }
    var isAnimating: Bool { phase == .flyingIn || phase == .flyingOut || zoomAnim != nil || momentum || settling || waitFrames > 0 }
    var isFlying: Bool { phase == .flyingIn || phase == .flyingOut }
    var debugImageRectInWindow: CGRect { convert(imageRect, to: nil) }
    /// 测试用：当前封面上的连续圆角（点）
    var displayedCornerRadius: CGFloat { cornerRadius }
}

// MARK: - SwiftUI 包装

/// NSHostingView 默认会命中整个 bounds；空区返回 nil，让底层 CoverViewerView 处理单击退出。
private final class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

struct CoverViewerRepresentable: NSViewRepresentable {
    let player: PlayerController
    func makeNSView(context: Context) -> CoverViewerView {
        let v = CoverViewerView(frame: .zero)
        v.player = player
        player.viewer.view = v
        return v
    }
    func updateNSView(_ v: CoverViewerView, context: Context) {}
}

/// 挂在窗口最上层：观赏层 + 右上角关闭按钮。只有这一小块读观赏状态
struct CoverViewerLayer: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        let m = player.viewer
        ZStack(alignment: .topTrailing) {
            CoverViewerRepresentable(player: player)
                .zIndex(0)
            if m.isOpen {
                // 底栏改由 CoverViewerView 内的 NSHostingView 绘制（窗口态 SwiftUI 兄弟层会被 NSView 盖住）。
                Button { player.closeCoverViewer() } label: { Image(systemName: "xmark") }
                    .buttonStyle(GlassIconButtonStyle(size: 34))
                    .help("退出观赏（Esc）")
                    .accessibilityLabel("退出观赏")
                    .padding(.top, 14).padding(.trailing, 18)
                    .opacity(m.chromeVisible ? 1 : 0)
                    .allowsHitTesting(m.chromeVisible)
                    .transition(.opacity)
                    .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: m.isOpen)
        .allowsHitTesting(m.isOpen)
        .ignoresSafeArea()
        .onChange(of: player.current?.id) { _, _ in if m.isOpen { player.viewerTrackChanged() } }
        .onChange(of: player.isPlaying) { _, _ in
            if m.isOpen, player.viewer.view?.isFlying == false {
                player.viewer.view?.startBreath()
                player.viewer.view?.refreshLivingColors()
            }
        }
        .onChange(of: player.theme) { _, _ in
            if m.isOpen { player.viewer.view?.refreshLivingColors() }
        }
    }
}

/// 观赏时把入口处的原封面藏起来（飞出去的就是它），飞回落地再出现。只这一层读观赏状态，卡片本身不重算
struct ViewerHide: ViewModifier {
    @Environment(PlayerController.self) private var player
    let key: String
    func body(content: Content) -> some View {
        content.opacity(player.viewer.hiddenKey == key ? 0 : 1)
    }
}

/// 记下入口封面在窗口里的位置（飞入起点、飞回终点）
struct ViewerRectProbe: View {
    @Environment(PlayerController.self) private var player
    let key: String
    let radius: CGFloat
    var body: some View {
        GeometryReader { g in
            Color.clear
                .onAppear { player.viewer.rects[key] = (g.frame(in: .global), radius) }
                .onChange(of: g.frame(in: .global)) { _, f in player.viewer.rects[key] = (f, radius) }
                .onDisappear { if player.viewer.rects[key]?.rect == g.frame(in: .global) { player.viewer.rects[key] = nil } }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 86 档背景位图（预计算）

enum ViewerFrostBackdrop {
    private static let ci = CIContext(options: [
        .workingFormat: CIFormat.RGBAh,
        .cacheIntermediates: false,
        .highQualityDownsample: true,
    ])

    static func render(image: CGImage, output: CGSize, backing: CGFloat, fallback: AmbientPalette?) -> CGImage? {
        var w = max(2, Int((output.width * max(backing, 1)).rounded()))
        var h = max(2, Int((output.height * max(backing, 1)).rounded()))
        // 全链路原生 4K（长边 ≥ 3840px）
        let long = max(w, h)
        if long > 0 && long < CoverStore.blurSide {
            let k = Double(CoverStore.blurSide) / Double(long)
            w = max(2, Int((Double(w) * k).rounded()))
            h = max(2, Int((Double(h) * k).rounded()))
        }
        if let pal = fallback { return solid(pal, width: w, height: h) }
        guard let cropped = cropToWide(image) else { return solid(.fallback, width: w, height: h) }
        let radius = ViewerFrost.blurRadius(forWidth: Double(w))
        return blur(cropped, width: w, height: h, radius: radius)
    }

    /// 主题回退：用现有主题色铺一层柔和纵渐变，不抓网络、不另造图。
    private static func solid(_ pal: AmbientPalette, width w: Int, height h: Int) -> CGImage? {
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors = [CGColor(srgbRed: pal.primary.r, green: pal.primary.g, blue: pal.primary.b, alpha: 1),
                      CGColor(srgbRed: pal.secondary.r, green: pal.secondary.g, blue: pal.secondary.b, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
        }
        return ctx.makeImage()
    }

    /// 去掉左右近黑边后，按 16:9 居中裁出铺满背景用的画面（小封面仍用完整原图）。
    private static func cropToWide(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 2, h > 2, let means = columnMeans(image) else { return image }
        let box = ViewerFrost.contentBox(columnMeans: means)
        let x0 = max(0, min(w - 1, box.x))
        let cw = max(1, min(w - x0, box.width))
        let src = image.cropping(to: CGRect(x: x0, y: 0, width: cw, height: h)) ?? image
        let sw = src.width, sh = src.height
        let srcH = min(Int((Double(sw) / (1920.0 / 1080.0)).rounded()), sh)
        let y0 = max(0, (sh - srcH) / 2)
        return src.cropping(to: CGRect(x: 0, y: y0, width: sw, height: srcH)) ?? src
    }

    private static func columnMeans(_ image: CGImage) -> [Double]? {
        let w = image.width, h = image.height
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var means = [Double](repeating: 0, count: w)
        let inv = 1.0 / Double(max(h, 1)) / 255.0
        for x in 0..<w {
            var s = 0.0
            var i = x * 4
            for _ in 0..<h {
                s += 0.2126 * Double(px[i]) + 0.7152 * Double(px[i+1]) + 0.0722 * Double(px[i+2])
                i += w * 4
            }
            means[x] = s * inv
        }
        return means
    }

    /// 真·原生 4K 全分辨率 16-bit 浮点 GPU 高斯模糊（不做降采样放大，确保大屏零色带零块状感）
    private static func blur(_ image: CGImage, width w: Int, height h: Int, radius: Double) -> CGImage? {
        var im = CIImage(cgImage: image)
        let sx = Double(w) / Double(max(image.width, 1))
        let sy = Double(h) / Double(max(image.height, 1))
        if abs(sx - 1.0) > 1e-4 || abs(sy - 1.0) > 1e-4 {
            im = im.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        }
        let targetRect = CGRect(x: im.extent.minX, y: im.extent.minY, width: CGFloat(w), height: CGFloat(h))
        im = im.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: targetRect)
        let out = ci.createCGImage(im, from: targetRect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        ci.clearCaches()
        return out
    }
}
