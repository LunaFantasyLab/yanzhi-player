// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

/// 观赏页前景：第一款底部通栏排版（标题 / 艺人 / 专辑 / 上一首·播放暂停·下一首·循环 / 细线进度）。
/// 只叠在适应态上；缩放检视时隐藏。空白处不抢点击，避免吞掉底层的单击退出。
/// 不含预览档位或「预览模拟进度」字样。
struct CoverViewerChrome: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        GeometryReader { g in
            let L = ViewerFrost.layout(inWidth: Double(g.size.width), height: Double(g.size.height))
            let item = player.current
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: Color.black.opacity(ViewerFrost.washAlpha), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: L.washHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

                Text(item?.title ?? "")
                    .font(.system(size: L.titleSize, weight: .bold))
                    .foregroundStyle(Color.white.opacity(235 / 255))
                    .shadow(color: .black.opacity(0.63), radius: 0, x: 1, y: 1)
                    .lineLimit(1)
                    .offset(x: L.title.x, y: L.title.y)
                    .allowsHitTesting(false)

                Text(item?.displayArtist ?? "")
                    .font(.system(size: L.artistSize, weight: .regular))
                    .foregroundStyle(Color.white.opacity(205 / 255))
                    .shadow(color: .black.opacity(0.63), radius: 0, x: 1, y: 1)
                    .lineLimit(1)
                    .offset(x: L.artist.x, y: L.artist.y)
                    .allowsHitTesting(false)

                Text(item?.album ?? "")
                    .font(.system(size: L.albumSize, weight: .regular))
                    .foregroundStyle(Color.white.opacity(165 / 255))
                    .shadow(color: .black.opacity(0.63), radius: 0, x: 1, y: 1)
                    .lineLimit(1)
                    .offset(x: L.album.x, y: L.album.y)
                    .allowsHitTesting(false)

                transport(L)

                let hitH = ViewerFrost.progressHitHeight(L, windowHeight: Double(g.size.height))
                let th = max(1.5, L.progressThickness)
                let hitFrameH = max(th + 8, hitH)
                // 视觉进度条严格落在 L.progress.y…(L.progress.y + th)，底边与右侧专辑底边像素级齐平；点击热区上下居中包裹
                ViewerThinProgress(layout: L, hitHeight: hitFrameH)
                    .frame(width: L.progress.width, height: hitFrameH, alignment: .center)
                    .offset(x: L.progress.x, y: L.progress.y - (hitFrameH - th) / 2)
            }
        }
    }

    @ViewBuilder private func transport(_ L: ViewerFrost.Layout) -> some View {
        let gap = (L.controlRow.width - 4 * L.controlHit) / 3
        let hit = L.controlHit
        let icon = L.icon
        HStack(spacing: gap) {
            iconButton("backward.end.fill", size: icon, hit: hit, label: "上一首") { player.scanButtonTapped(-1) }
            iconButton(player.isPlaying ? "pause.fill" : "play.fill", size: icon, hit: hit, label: "播放或暂停") { player.togglePlay() }
            iconButton("forward.end.fill", size: icon, hit: hit, label: "下一首") { player.scanButtonTapped(1) }
            let loopOn = player.queue.repeatMode != .off
            iconButton(player.queue.repeatMode == .one ? "repeat.1" : "repeat", size: icon, hit: hit, label: "循环", tinted: loopOn) { player.cycleRepeat() }
        }
        .offset(x: L.controlRow.x, y: L.controlRow.y)
    }

    private func iconButton(_ symbol: String, size: Double, hit: Double, label: String, tinted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tinted ? Color(player.palette.accent) : Color.white.opacity(235 / 255))
                .shadow(color: .black.opacity(0.55), radius: 0, x: 1, y: 1)
                .frame(width: hit, height: hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// 细线进度：真实时长与播放位置，可拖动跳转。不是预览模拟进度。
private struct ViewerThinProgress: View {
    @Environment(PlayerController.self) private var player
    let layout: ViewerFrost.Layout
    var hitHeight: Double
    var body: some View {
        let dur = max(0, player.duration ?? 0)
        let pos = dur > 0 ? min(max(0, player.position), dur) : 0
        let frac = dur > 0 ? pos / dur : 0
        let th = max(1.5, layout.progressThickness)
        let thumb = max(4, ViewerFrost.progressThumbRadius * layout.scale)
        let accent = Color(player.palette.accent)
        GeometryReader { g in
            let w = g.size.width
            let y = th / 2
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(64 / 255)).frame(height: th)
                Capsule().fill(accent).frame(width: max(th, w * frac), height: th)
                Circle().fill(accent)
                    .frame(width: thumb * 2, height: thumb * 2)
                    .offset(x: max(0, min(w, w * frac)) - thumb, y: 0)
            }
            .frame(height: max(th + 8, hitHeight), alignment: .center)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                guard dur > 0 else { return }
                let t = min(max(0, v.location.x / max(w, 1)), 1) * dur
                if player.isScrubbing { player.scrub(to: t) } else { player.beginScrub(); player.scrub(to: t) }
            }.onEnded { v in
                guard dur > 0 else { return }
                let t = min(max(0, v.location.x / max(w, 1)), 1) * dur
                if player.isScrubbing { player.endScrub(at: t) } else { player.seek(to: t) }
            })
            .accessibilityLabel("播放进度")
            .accessibilityValue(Text(dur > 0 ? String(format: "%.0f / %.0f 秒", pos, dur) : "未知"))
            .position(x: w / 2, y: y + 8)
        }
    }
}
