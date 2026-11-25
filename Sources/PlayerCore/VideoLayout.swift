// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 视频在容器里按片源比例完整放下（不拉伸、不裁剪），多余处留黑。
public struct VideoFit: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var letterboxTop: Double
    public var letterboxBottom: Double
    public var letterboxLeft: Double
    public var letterboxRight: Double

    public var aspect: Double { height > 0 ? width / height : 0 }
}

/// 窗口 / 全屏舞台的可用区与片源适应。窗口态与全屏播放视频时都不再留播放器容器装饰边距。
public enum VideoLayout {
    /// 历史窗口态舞台边距（t249u 起窗口态也为 0，仅作记录）。
    public static let windowedStagePadding: Double = 36
    public static let windowedStagePaddingCompact: Double = 12
    public static let windowedContentVerticalPadding: Double = 12

    /// 视频舞台在容器四周额外留出的边距（不含片源比例留黑）。
    /// 窗口态与全屏播放视频时均为 0，只按比例适应可用区。
    public static func stagePadding(fullscreen: Bool, compact: Bool) -> (horizontal: Double, vertical: Double) {
        _ = fullscreen
        _ = compact
        return (0, 0)
    }

    public static func isImmersiveVideo(fullscreen: Bool, videoStageOpen: Bool, mini: Bool, nowPlaying: Bool) -> Bool {
        // 全屏与窗口态在「正在播放」的视频舞台上同样沉浸；迷你窗除外。
        _ = fullscreen
        return videoStageOpen && !mini && nowPlaying
    }

    /// 窗口态与全屏主舞台无装饰圆角；仅迷你窗保留小圆角。
    public static func stageCornerRadius(fullscreen: Bool, mini: Bool) -> Double {
        if mini && !fullscreen { return 14 }
        return 0
    }

    /// 装饰性描边只留给迷你窗；窗口态主舞台不再画玻璃画框。
    public static func showsDecorativeBorder(fullscreen: Bool, mini: Bool) -> Bool {
        mini && !fullscreen
    }

    /// 应用自己的顶部界面（返回、分段、主题、曲名/编码条）。视频主舞台（窗口态与全屏）不显示；音频封面、空工程、列表/均衡器、迷你窗保持原样。
    public static func showsApplicationHeader(videoStageOpen: Bool, mini: Bool, nowPlaying: Bool) -> Bool {
        !(videoStageOpen && !mini && nowPlaying)
    }

    /// 叠在画面上的曲名/编码信息条。主舞台与迷你窗都不叠，以免被当成播放器顶栏；片源字幕与烧录时间码不走这里。
    public static func showsTitleOverlay(videoStageOpen: Bool, mini: Bool) -> Bool {
        _ = videoStageOpen
        _ = mini
        return false
    }

    /// 底部播放控制条：视频窗口仍要保留（可由现有静止计时淡出）。
    public static func showsPlayChrome(videoStageOpen: Bool, mini: Bool, nowPlaying: Bool) -> Bool {
        _ = videoStageOpen
        _ = mini
        _ = nowPlaying
        return true
    }

    /// 片源外挂字幕、内封字幕、烧录时间码不属于应用顶栏，不得按顶栏策略隐藏或改片源。
    public static let applicationHeaderIncludesSourceSubtitles = false

    /// 在给定容器内按 aspect（宽/高）居中适应。
    public static func fitted(containerWidth: Double, containerHeight: Double, aspect: Double) -> VideoFit {
        let a = max(0.3, aspect)
        let maxW = max(0, containerWidth), maxH = max(0, containerHeight)
        let w = min(maxW, maxH * a)
        let h = w / a
        let x = (maxW - w) / 2
        let y = (maxH - h) / 2
        return VideoFit(x: x, y: y, width: w, height: h,
                        letterboxTop: y, letterboxBottom: maxH - y - h,
                        letterboxLeft: x, letterboxRight: maxW - x - w)
    }
}
