// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

/// 视频舞台：放 mpv 的 Metal 画面（同一个 NSView 常驻，切换页面不重建、不黑屏）。
/// 窗口态与全屏都无装饰画框、无应用顶栏（曲名/编码条）；仅迷你窗保留小圆角。底部控制条由 RootView 叠放，静止后淡出。
struct VideoStage: View {
    @Environment(PlayerController.self) private var player
    var mini = false
    @State private var swipe = VideoSwipeCatcher()

    var body: some View {
        GeometryReader { geo in
            let maxW = geo.size.width, maxH = geo.size.height
            let a = max(0.3, player.videoAspect)
            let w = min(maxW, maxH * a), h = w / a
            let radius: CGFloat = VideoLayout.stageCornerRadius(fullscreen: player.windowFullScreen, mini: mini)
            ZStack(alignment: .top) {
                // 这里只占位：真正的视频视图由 RootView 里常驻的 VideoHost 摆到这个位置。
                // 进出迷你窗、切页时视频视图不会被拆下重挂，所以不会露出黑底或空一帧。
                Color.clear
                    .frame(width: w, height: h)
                    .anchorPreference(key: VideoSlotKey.self, value: .bounds) {
                        [VideoSlot(bounds: $0, radius: radius, mini: mini, fullScreen: player.windowFullScreen)]
                    }
                    .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.24), lineWidth: 1)
                        .opacity(VideoLayout.showsDecorativeBorder(fullscreen: player.windowFullScreen, mini: mini) ? 1 : 0)
                        .allowsHitTesting(false))
                if VideoLayout.showsTitleOverlay(videoStageOpen: player.videoStageOpen, mini: mini), player.chromeVisible, let cur = player.current {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(cur.title).font(.system(size: 15, weight: .semibold))
                            if let f = cur.formatLine { Text(f).font(.system(size: 11)).opacity(0.65) }
                        }
                        Spacer()
                        if player.isBuffering {
                            ProgressView().controlSize(.small).tint(.white).transition(.opacity)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).padding(.vertical, 14)
                    .frame(width: w)
                    .background(LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: radius, topTrailingRadius: radius, style: .continuous)))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(width: maxW, height: maxH)
            .animation(Motion.panel, value: player.chromeVisible)
            .animation(Motion.panel, value: player.windowFullScreen)
            .animation(Motion.panel, value: player.videoAspect)
        }
        .onAppear {
            player.syncWindowFullScreen()
            player.videoSurface.onDoubleClick = { [weak player] in
                MainActor.assumeIsolated {
                    // 双击视频卡进来时，第二下落在刚出现的画面上：不算「双击画面 = 全屏」
                    guard let player, CACurrentMediaTime() - player.videoStageEnteredAt > 0.6 else { return }
                    player.toggleFullScreen()
                }
            }
            if !mini { swipe.install(player) }
        }
        .onDisappear { if !mini { swipe.uninstall() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in player.syncWindowFullScreen() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in player.syncWindowFullScreen() }
    }
}

/// 视频占位：VideoStage 报告“视频该放在哪、圆角多大”，VideoHost 按它摆放唯一的视频视图
struct VideoSlot {
    let bounds: Anchor<CGRect>
    let radius: CGFloat
    let mini: Bool
    let fullScreen: Bool
}

struct VideoSlotKey: PreferenceKey {
    static let defaultValue: [VideoSlot] = []
    static func reduce(value: inout [VideoSlot], nextValue: () -> [VideoSlot]) { value.append(contentsOf: nextValue()) }
}

/// 常驻的视频宿主：整个窗口生命周期里只挂一次视频视图，只改它的位置、尺寸、圆角和透明度。
struct VideoHost: View {
    @Environment(PlayerController.self) private var player
    let slots: [VideoSlot]
    @State private var memo = Memo()
    final class Memo { var rect: CGRect = .zero; var radius: CGFloat = 22; var fullScreen = false }

    var body: some View {
        GeometryReader { g in
            // 过渡期间新旧两棵树都在报告位置：优先取当前模式（迷你 / 正常）那一个
            let slot = slots.last(where: { $0.mini == player.isPinnedMini }) ?? slots.last
            let wanted = player.isVideo && (player.isPinnedMini || (player.videoStageOpen && player.tab == .nowPlaying && !player.queue.items.isEmpty))
            let r = slot.map { g[$0.bounds] } ?? memo.rect
            let radius = slot?.radius ?? memo.radius
            let fs = slot?.fullScreen ?? memo.fullScreen
            let _ = { if slot != nil { memo.rect = r; memo.radius = radius; memo.fullScreen = fs } }()
            VideoSurfaceRepresentable(surface: player.videoSurface, cornerRadius: radius)
                .frame(width: max(2, r.width), height: max(2, r.height))
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .shadow(color: .black.opacity(fs ? 0 : 0.22), radius: 20, y: 10)
                .position(x: r.midX, y: r.midY)
                .opacity(wanted && slot != nil ? 1 : 0)
                .allowsHitTesting(wanted && slot != nil)
                .animation(Motion.tab, value: wanted && slot != nil)
        }
    }
}

/// 视频舞台上的触控板双指横扫 → 回到封面轮播（和专辑卡翻面时「左右滑翻回」一致）
@MainActor
final class VideoSwipeCatcher {
    private var monitor: Any?
    func install(_ player: PlayerController) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak player] e in
            guard let player, e.hasPreciseScrollingDeltas, e.momentumPhase.isEmpty,
                  player.videoStageOpen, player.tab == .nowPlaying, !player.isPinnedMini, e.window === player.mainWindow else { return e }
            player.videoSwipe(dx: e.scrollingDeltaX, dy: e.scrollingDeltaY, began: e.phase.contains(.began),
                              ended: e.phase.contains(.ended) || e.phase.contains(.cancelled))
            return e
        }
    }
    func uninstall() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
}
