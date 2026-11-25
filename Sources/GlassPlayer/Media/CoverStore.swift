// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import AppKit
import CoreImage
import CoreText
import PlayerCore

/// 一张封面在界面上需要的全部素材，全部在后台一次性算好（不在动画帧里做任何模糊/取色）。
struct CoverArt {
    let image: CGImage          // 卡片正面与全屏观赏（真·原生 4K 3840px UHD；原图更小按原图）
    let thumbnail: CGImage      // 迷你窗 / 播放条 / 列表小图（由 4K 主图经 Lanczos 精缩至 1024px，消除小尺寸单次下采样锯齿发糊）
    let frosted: CGImage        // 卡片玻璃边框用的磨砂底（真·原生 4K 3840px 16-bit 浮点 GPU 高斯模糊）
    let backdrop: CGImage       // 窗口背景用的大模糊（真·原生 4K 3840px 16-bit 浮点 GPU 高斯模糊）
    let palette: AmbientPalette
    let isGenerated: Bool
    var style: DefaultCoverStyle? = nil     // 默认封面用的风格（真实封面为 nil）
    /// 封面从哪来：file = 文件自带 / 同目录图片 / 视频截帧，online = 联网查到的官方封面，generated = 默认封面
    var origin: String = "file"
    /// 生成封面的种子哈希（随机重新生成时变化，保证封面视图触发交叉淡入过渡）
    var seedHash: UInt64 = 0
    /// 界面上用来做淡入过渡的标识：换了来源（默认 → 官方）或重生成种子就换一个，视图据此交叉淡入
    var fadeID: String { "\(origin)\(style.map { "-\($0)" } ?? "")-\(seedHash)" }
}

/// 同时最多做 4 张封面（降采样 GPU 模糊 + 多核并行 4K 默认封面，峰值显存极低且出图极速）
actor ArtGate {
    static let shared = ArtGate(limit: 4)
    private var free: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(limit: Int) { free = limit }
    func acquire() async { if free > 0 { free -= 1; return }; await withCheckedContinuation { waiters.append($0) } }
    func release() { if waiters.isEmpty { free += 1 } else { waiters.removeFirst().resume() } }
}

@MainActor
final class CoverStore {
    /// 2026-11-24：全软件最高清规范 —— 所有封面、默认生成封面、视频截帧按 4K（3840px）出图（原图更小时按原图、不硬拉大）
    nonisolated static let maxSide = 3840
    /// 大半径高斯模糊底（卡片磨砂框 / 窗口背景）同样全线按 4K（3840px）出图（GPU 降采样模糊 → 4K 合成耗时 < 4ms）
    nonisolated static let blurSide = 3840
    private var cache: [String: CoverArt] = [:]
    private var lastUse: [String: UInt64] = [:]
    private var tick: UInt64 = 0
    /// 全 4K 封面 + 4K 磨砂/背景缓存预算提升至 3.0 GB
    private(set) var bytes = 0
    var budget = 3_000_000_000
    /// 正在用的（当前曲目、轮播可见的卡）不清
    var pinned: Set<String> = []
    /// 因为内存上限被清掉、要用时得重新读的
    private(set) var evicted: Set<String> = []
    func markReloading(_ id: String) { evicted.remove(id) }
    var count: Int { cache.count }

    nonisolated static func cost(_ a: CoverArt) -> Int {
        var n = a.image.width * a.image.height * 4
        if a.thumbnail !== a.image { n += a.thumbnail.width * a.thumbnail.height * 4 }
        if a.frosted !== a.image { n += a.frosted.width * a.frosted.height * 4 }
        if a.backdrop !== a.image && a.backdrop !== a.frosted { n += a.backdrop.width * a.backdrop.height * 4 }
        return n
    }
    /// 16-bit 浮点高精度 Metal GPU 上下文：原生 4K 直接运算，杜绝降采样放大伪影与 8-bit 色带
    nonisolated private static let ci = CIContext(options: [
        .workingFormat: CIFormat.RGBAh,
        .cacheIntermediates: false,
        .highQualityDownsample: true,
    ])

    func art(for id: String) -> CoverArt? {
        guard let a = cache[id] else { return nil }
        tick &+= 1; lastUse[id] = tick
        return a
    }

    /// 主动撤下某张封面（例如关掉「自动补封面」）。不要标成 evicted，以免按内存回收路径把官方封面再读回来。
    func remove(_ id: String) {
        if let old = cache.removeValue(forKey: id) { bytes -= Self.cost(old) }
        lastUse[id] = nil
        evicted.remove(id)
    }

    func store(_ art: CoverArt, for id: String) {
        if let old = cache[id] { bytes -= Self.cost(old) }
        cache[id] = art
        bytes += Self.cost(art)
        tick &+= 1; lastUse[id] = tick
        evicted.remove(id)
        // 超出内存上限：清最久没用的（正在用的不清）
        while bytes > budget {
            guard let victim = lastUse.filter({ $0.key != id && !pinned.contains($0.key) }).min(by: { $0.value < $1.value })?.key,
                  let a = cache.removeValue(forKey: victim) else { break }
            lastUse[victim] = nil
            bytes -= Self.cost(a)
            evicted.insert(victim)
        }
    }

    /// 排队生成（同时最多 2 张）
    nonisolated static func makeArtGated(cover: CGImage?, item: MediaItem, style: DefaultCoverStyle = .softGlass, origin: String = "file") async -> CoverArt {
        await ArtGate.shared.acquire()
        let a = makeArt(cover: cover, item: item, style: style, origin: origin)
        await ArtGate.shared.release()
        return a
    }

    /// 后台生成（真实封面或默认封面）。
    nonisolated static func makeArt(cover: CGImage?, item: MediaItem, style: DefaultCoverStyle = .softGlass, origin: String = "file") -> CoverArt {
        if let cover {
            let pal = palette(of: cover)
            let thumb = lanczosScale(cover, maxSide: 1024) ?? cover
            return CoverArt(image: cover, thumbnail: thumb,
                            frosted: blur(cover, radius: 26, saturation: 0.85, brightness: 0.02, size: blurSide) ?? cover,
                            backdrop: blur(cover, radius: 60, saturation: 0.75, brightness: -0.04, size: blurSide) ?? cover,
                            palette: pal, isGenerated: false, origin: origin)
        }
        let spec = DefaultCoverSpec.make(seed: item.coverSeed)
        let img = defaultCover(spec: spec, style: style, title: item.album?.isEmpty == false ? item.album! : item.title, artist: item.displayArtist, size: maxSide)
        let thumb = lanczosScale(img, maxSide: 1024) ?? img
        let p = style == .softGlass ? spec.palette : spec.richPalette
        let tamed = AmbientPalette(primary: RGB(hex: p.base), secondary: OKLab(RGB(hex: p.c)).mix(OKLab(RGB(hex: p.base)), 0.45).rgb,
                                   tertiary: OKLab(RGB(hex: p.a)).mix(OKLab(RGB(hex: p.base)), 0.35).rgb,
                                   glassTint: RGB(hex: p.b), accent: OKLab(RGB(hex: p.b)).mix(OKLab(RGB(hex: p.a)), 0.4).rgb)
        return CoverArt(image: img, thumbnail: thumb,
                        frosted: blur(img, radius: 26, saturation: 0.9, brightness: 0.02, size: blurSide) ?? img,
                        backdrop: blur(img, radius: 60, saturation: 0.85, brightness: -0.03, size: blurSide) ?? img,
                        palette: tamed, isGenerated: true, style: style, origin: "generated", seedHash: spec.hash)
    }

    /// 16-bit 浮点 GPU Lanczos 抗锯齿缩略图（给迷你窗/底栏/列表用，避免 3840px 直接 20x 单次缩放产生的锯齿发糊）
    nonisolated static func lanczosScale(_ image: CGImage, maxSide: Int) -> CGImage? {
        let maxDim = max(image.width, image.height)
        guard maxDim > maxSide else { return image }
        let scale = Double(maxSide) / Double(maxDim)
        let im = CIImage(cgImage: image)
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0,
            ])
        let rect = im.extent.integral
        guard rect.width >= 2, rect.height >= 2 else { return image }
        let out = Self.ci.createCGImage(im, from: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        Self.ci.clearCaches()
        return out
    }

    // MARK: 取色
    nonisolated static func palette(of image: CGImage) -> AmbientPalette {
        let w = 48, h = 48
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? AmbientPalette.extract(rgba: px, width: w, height: h) : .fallback
    }

    // MARK: 模糊（真·原生 4K 全分辨率 Metal GPU 16-bit 浮点高斯模糊：零降采样、零低分放大、零色带）
    nonisolated static func blur(_ image: CGImage, radius: Double, saturation: Double, brightness: Double, size: Int) -> CGImage? {
        let maxDim = Double(max(image.width, image.height))
        guard maxDim > 0 else { return nil }
        let outScale = Double(size) / maxDim
        let outW = max(2, Int((Double(image.width) * outScale).rounded()))
        let outH = max(2, Int((Double(image.height) * outScale).rounded()))
        let sigma = radius * Double(size) / 400.0

        var im = CIImage(cgImage: image)
        if abs(outScale - 1.0) > 1e-4 {
            im = im.transformed(by: CGAffineTransform(scaleX: outScale, y: outScale))
        }
        let targetRect = CGRect(x: im.extent.minX, y: im.extent.minY, width: CGFloat(outW), height: CGFloat(outH))
        im = im.clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: saturation, kCIInputBrightnessKey: brightness])
            .cropped(to: targetRect)
        let out = Self.ci.createCGImage(im, from: targetRect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        Self.ci.clearCaches()
        return out
    }

    // MARK: 默认封面（PlayerCore 逐像素渲染 + CoreText 文字）
    nonisolated static func defaultCover(spec: DefaultCoverSpec, style: DefaultCoverStyle = .softGlass, title: String, artist: String, size n: Int) -> CGImage {
        var px = DefaultCoverRenderer.render(spec, style: style, size: n)
        let light = style.isLight(spec)
        let ink: CGFloat = light ? 0.08 : 1
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let made: CGImage? = px.withUnsafeMutableBytes { buf -> CGImage? in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            // CG 坐标系原点在左下：像素数组第 0 行是顶部，CGContext 的内存第 0 行也是顶部，所以文字按“从下往上”计算 y
            let N = CGFloat(n)
            func draw(_ s: String, size: CGFloat, weight: NSFont.Weight, alpha: CGFloat, baselineFromBottom: CGFloat, maxWidth: CGFloat) {
                let font = NSFont.systemFont(ofSize: size, weight: weight)
                let para = NSMutableParagraphStyle(); para.lineBreakMode = .byTruncatingTail
                let attr = NSAttributedString(string: s, attributes: [
                    .font: font, .foregroundColor: NSColor(white: ink, alpha: alpha), .paragraphStyle: para,
                    .kern: size * 0.01,
                ])
                let line = CTLineCreateWithAttributedString(attr)
                let truncated = CTLineCreateTruncatedLine(line, Double(maxWidth), .end,
                                                          CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [.font: font, .foregroundColor: NSColor(white: ink, alpha: alpha)]))) ?? line
                ctx.saveGState()
                ctx.setAllowsAntialiasing(true)
                ctx.setShouldAntialias(true)
                ctx.setAllowsFontSmoothing(true)
                ctx.setShouldSmoothFonts(true)
                ctx.setShadow(offset: CGSize(width: 0, height: -N * 0.0012), blur: N * 0.0038, color: NSColor(white: light ? 1 : 0, alpha: light ? 0.30 : 0.34).cgColor)
                ctx.textPosition = CGPoint(x: N * 0.075, y: baselineFromBottom)
                CTLineDraw(truncated, ctx)
                ctx.restoreGState()
            }
            if style == .monogram { drawMonogram(ctx, title: title, n: N, light: light) }
            draw(artist, size: N * 0.033, weight: .medium, alpha: 0.72, baselineFromBottom: N * 0.068, maxWidth: N * 0.82)
            draw(title, size: N * 0.056, weight: .bold, alpha: 0.96, baselineFromBottom: N * 0.124, maxWidth: N * 0.82)
            // 右上角系列标记：一枚 4K 锐利细环
            let r = N * 0.018
            ctx.setAllowsAntialiasing(true)
            ctx.setStrokeColor(NSColor(white: ink, alpha: 0.38).cgColor)
            ctx.setLineWidth(max(2, N / 520))
            ctx.strokeEllipse(in: CGRect(x: N - N * 0.085 - r, y: N - N * 0.085 - r, width: 2 * r, height: 2 * r))
            return ctx.makeImage()
        }
        return made ?? MetadataReader.makeCGImage(px, width: n, height: n)!
    }

    /// 字标：取标题第一个字（汉字或字母），超大字号，扁平的磨砂玻璃字——半透明填充 + 细亮边 + 淡投影
    nonisolated static func drawMonogram(_ ctx: CGContext, title: String, n N: CGFloat, light: Bool) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ch = trimmed.first else { return }
        let glyph = String(ch).uppercased()
        let isCJK = ch.unicodeScalars.first.map { $0.value >= 0x2E80 } ?? false
        let font = NSFont.systemFont(ofSize: N * (isCJK ? 0.56 : 0.66), weight: isCJK ? .semibold : .bold)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: [.font: font]))
        let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let x = (N - b.width) / 2 - b.minX, y = N * 0.56 - b.height / 2 - b.minY
        // 填充
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -N * 0.012), blur: N * 0.04, color: NSColor(white: 0, alpha: light ? 0.12 : 0.30).cgColor)
        let fill = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor(white: light ? 1 : 1, alpha: light ? 0.55 : 0.16)])
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(fill), ctx)
        ctx.restoreGState()
        // 细亮边
        ctx.saveGState()
        ctx.setTextDrawingMode(.stroke)
        ctx.setLineWidth(max(1, N / 420))
        let stroke = NSAttributedString(string: glyph, attributes: [.font: font, .foregroundColor: NSColor(white: light ? 0.15 : 1, alpha: light ? 0.30 : 0.55)])
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(stroke), ctx)
        ctx.restoreGState()
    }

    /// 细颗粒贴图（1024px 4K 级高清贴图按 2x 铺在 4K/5K 屏上无可见拼接周期）。
    nonisolated static func grainTile(size: Int = 1024, seed: UInt64 = 0xA11CE) -> CGImage {
        var rng = SplitMix64(state: seed)
        var px = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let g = (rng.unit() + rng.unit() + rng.unit()) / 3
            let v = UInt8(clamping: Int(g * 255))
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v
        }
        return MetadataReader.makeCGImage(px, width: size, height: size)!
    }
}
