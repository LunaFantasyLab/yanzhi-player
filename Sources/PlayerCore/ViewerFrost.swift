// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 全屏专辑观赏页：第一款（底部通栏 + 右侧小封面）的几何与 86 档柔和参数。
///
/// 档名 86 是相对柔和强度，由预览 80 与 90 **线性插值**得到，不是模糊 API 或透明度的百分比。
/// 对照（1920 宽）：v4 半径 16 / veil 0.10；70 = 40 / 0.11；80 = 80 / 0.13；90 = 160 / 0.18。
/// 86 = 80 + 0.6×(90−80) → 半径 128、veil_base 0.16、veil_breath 0.02（与 70/80/90 相同呼吸幅度）。
public enum ViewerFrost {
    public static let grade = 86
    public static let designWidth: Double = 1920
    public static let designHeight: Double = 1080
    public static let blurRadiusAtDesign: Double = 80 + 0.6 * (160 - 80) // 128
    public static let veilBase: Double = 0.13 + 0.6 * (0.18 - 0.13)     // 0.16
    public static let veilBreath: Double = 0.02
    /// 呼吸完整光滑周期（秒）：半正弦往返一次 9 秒。
    public static let breathPeriod: Double = 18
    public static let cornerRatio: Double = 0.085 * 0.62 / 0.91
    public static let progressThickness: Double = 3
    public static let progressThumbRadius: Double = 5
    public static let artistSizeAtDesign: Double = 30
    public static let albumSizeAtDesign: Double = 22
    public static let iconAtDesign: Double = 44
    public static let controlGapAtDesign: Double = 18
    public static let washHeightAtDesign: Double = 360
    public static let washAlpha: Double = 56.0 / 255.0
    public static let nearBlackLuma: Double = 8.0 / 255.0

    public static func blurRadius(forWidth width: Double) -> Double {
        guard width > 0 else { return 0 }
        return blurRadiusAtDesign * (width / designWidth)
    }

    /// 呼吸包络 [0, 1]。暂停或「减少动态」时冻结为 0，只保留 veilBase。
    public static func breathEnvelope(time t: Double, playing: Bool, reduceMotion: Bool) -> Double {
        if reduceMotion || !playing { return 0 }
        return 0.5 - 0.5 * cos(2 * Double.pi * t / breathPeriod)
    }

    public static func veil(time t: Double, playing: Bool, reduceMotion: Bool) -> Double {
        veilBase + veilBreath * breathEnvelope(time: t, playing: playing, reduceMotion: reduceMotion)
    }

    public struct Point: Equatable, Sendable { public var x: Double, y: Double }
    public struct SizeBox: Equatable, Sendable { public var x: Double, y: Double, size: Double }
    public struct Bar: Equatable, Sendable { public var x: Double, y: Double, width: Double }
    public struct Rect: Equatable, Sendable {
        public var x: Double, y: Double, width: Double, height: Double
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
    }

    public struct Layout: Equatable, Sendable {
        public var scale: Double
        public var originX: Double
        public var originY: Double
        public var cover: SizeBox
        public var title: Point
        public var titleSize: Double
        public var artist: Point
        public var artistSize: Double
        public var album: Point
        public var albumSize: Double
        public var controls: Point
        public var icon: Double
        public var controlHit: Double
        public var progress: Bar
        public var progressThickness: Double
        public var washHeight: Double
        public var coverCornerRadius: Double
        public var controlRow: Rect
    }

    /// 以 1920×1080 设计稿均匀缩放，底对齐、水平居中，封面保持正方形。
    public static func layout(inWidth w: Double, height h: Double) -> Layout {
        let s = min(w / designWidth, h / designHeight)
        let boxW = designWidth * s
        let boxH = designHeight * s
        let ox = (w - boxW) / 2
        let oy = h - boxH
        func X(_ x: Double) -> Double { ox + x * s }
        func Y(_ y: Double) -> Double { oy + y * s }
        let icon = 44 * s
        let hit = max(48 * s, icon + 14 * s)
        let gap = 18 * s
        let coverSize = 300 * s
        let rowW = 4 * hit + 3 * gap
        return Layout(
            scale: s,
            originX: ox,
            originY: oy,
            // 2026-11-24：专辑较原 732 上移自身高度的 1/6（50px → y=682，底边 982）；播放进度条底边与专辑底边 982 严格齐平
            cover: SizeBox(x: X(1572), y: Y(682), size: coverSize),
            title: Point(x: X(64), y: Y(735)),
            titleSize: 72 * s,
            artist: Point(x: X(64), y: Y(825)),
            artistSize: 30 * s,
            album: Point(x: X(64), y: Y(867)),
            albumSize: 22 * s,
            controls: Point(x: X(64), y: Y(907)),
            icon: icon,
            controlHit: hit,
            progress: Bar(x: X(64), y: Y(979), width: 1450 * s),
            progressThickness: 3 * s,
            washHeight: washHeightAtDesign * s,
            coverCornerRadius: coverSize * cornerRatio,
            controlRow: Rect(x: X(64), y: Y(907), width: rowW, height: hit)
        )
    }

    public static func rectsOverlap(_ a: Rect, _ b: (Double, Double, Double, Double)) -> Bool {
        let bx = b.0, by = b.1, bw = b.2, bh = b.3
        return a.x < bx + bw && a.x + a.width > bx && a.y < by + bh && a.y + a.height > by
    }

    public static func rectsOverlap(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double)) -> Bool {
        a.0 < b.0 + b.2 && a.0 + a.2 > b.0 && a.1 < b.1 + b.3 && a.1 + a.3 > b.1
    }

    /// 去掉左右近黑边（列平均亮度 ≤ 阈值），只用于铺满背景；小封面仍用完整原图。
    public static func contentBox(columnMeans: [Double], threshold: Double = 8.0 / 255.0) -> (x: Int, width: Int) {
        let n = columnMeans.count
        guard n > 0 else { return (0, 0) }
        var lo = 0, hi = n - 1
        while lo < n, columnMeans[lo] <= threshold { lo += 1 }
        while hi >= lo, columnMeans[hi] <= threshold { hi -= 1 }
        if lo > hi { return (0, n) }
        return (lo, hi - lo + 1)
    }

    public static func fallbackPalette(theme: AppTheme, systemDark: Bool, coverPalette: AmbientPalette? = nil) -> AmbientPalette {
        let t = theme.resolved(systemDark: systemDark)
        if t.followsCover { return coverPalette ?? .fallback }
        return t.palette ?? .fallback
    }

    public static func usesThemeFallbackBackground(isDefaultCover: Bool, hasCoverImage: Bool) -> Bool {
        !hasCoverImage || isDefaultCover
    }

    /// 细线进度的可点高度：希望约 22pt，但不得伸出窗口下沿（小窗口按剩余空间收缩，不改设计坐标）。
    public static func progressHitHeight(_ L: Layout, windowHeight h: Double) -> Double {
        let desired = max(L.progressThickness + 16, 22)
        let room = h - L.progress.y
        if !room.isFinite || room <= 0 { return 0 }
        return min(desired, room)
    }

    public static func playButtonCenter(_ L: Layout) -> Point {
        let gap = (L.controlRow.width - 4 * L.controlHit) / 3
        return Point(
            x: L.controlRow.x + L.controlHit + gap + L.controlHit / 2,
            y: L.controlRow.y + L.controlHit / 2
        )
    }

    public struct NamedRect: Equatable, Sendable {
        public var name: String
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double
        public var maxX: Double { x + width }
        public var maxY: Double { y + height }
    }

    /// 适应态必须落在窗内的前景（小封面、文案、四键、细线进度）。
    public static func foregroundRects(_ L: Layout, windowHeight h: Double) -> [NamedRect] {
        let hitH = progressHitHeight(L, windowHeight: h)
        return [
            NamedRect(name: "cover", x: L.cover.x, y: L.cover.y, width: L.cover.size, height: L.cover.size),
            NamedRect(name: "title", x: L.title.x, y: L.title.y, width: max(80, L.titleSize * 2), height: L.titleSize),
            NamedRect(name: "artist", x: L.artist.x, y: L.artist.y, width: max(80, L.artistSize * 4), height: L.artistSize),
            NamedRect(name: "album", x: L.album.x, y: L.album.y, width: max(80, L.albumSize * 4), height: L.albumSize),
            NamedRect(name: "controls", x: L.controlRow.x, y: L.controlRow.y, width: L.controlRow.width, height: L.controlRow.height),
            NamedRect(name: "progress", x: L.progress.x, y: L.progress.y, width: L.progress.width, height: hitH)
        ]
    }

    public static func offscreenForeground(_ L: Layout, inWidth w: Double, height h: Double) -> [NamedRect] {
        foregroundRects(L, windowHeight: h).filter { r in
            r.x < -0.51 || r.y < -0.51 || r.maxX > w + 0.51 || r.maxY > h + 0.51 || r.width <= 0 || r.height <= 0
        }
    }
}
