// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import PlayerCore

/// 迷你窗（置顶小窗）：音频是一张横向玻璃卡（封面 + 曲名 + 进度 + 控制），视频是画面 + 悬浮玻璃控制条。
/// 整个小窗都能拖动移动；右键有迷你窗专用菜单；文件拖进来照样直接播放。
struct MiniPlayerView: View {
    @Environment(PlayerController.self) private var player
    @State private var hover = false

    var body: some View {
        Group {
            if player.isVideo { video } else { audio }
        }
        .contextMenu { MenuContent(nodes: MenuCatalog.blank(player)) }
        .onHover { h in withAnimation(Motion.hover) { hover = h } }
    }

    private var audio: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        return HStack(alignment: .bottom, spacing: 14) {
            ZStack {
                if let c = player.current, let art = player.art(for: c) {
                    Image(decorative: art.thumbnail, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .id(c.id + art.fadeID).transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    LinearGradient(colors: [Color(player.palette.tertiary), Color(player.palette.primary)], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 8, y: 3)
            .animation(Motion.toggle, value: player.current?.id)
            .background(ViewerRectProbe(key: "mini", radius: 15))
            .contentShape(Rectangle())
            // 单击迷你窗封面：一键展开回到大窗卡片模式
            .onTapGesture { player.togglePinnedMini() }
            .help("展开回到卡片模式")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("展开回到卡片模式")

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = player.current?.title, !title.isEmpty {
                        Text(title).font(.system(size: 15.5, weight: .semibold)).lineLimit(1)
                            .contentTransition(.opacity)
                    }
                    if let a = player.current?.knownArtist, !a.isEmpty {
                        Text(a).font(.system(size: 12)).opacity(0.68).lineLimit(1)
                    }
                }
                ProgressScrubber(hover: hover)
                    .padding(.top, 10)
                Spacer(minLength: 4)
                HStack(alignment: .bottom, spacing: 4) {
                    Button { player.previous() } label: { Image(systemName: "backward.fill") }.buttonStyle(GlassIconButtonStyle(size: 32))
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    }.buttonStyle(GlassIconButtonStyle(size: 38, prominent: true))
                    Button { player.next() } label: { Image(systemName: "forward.fill") }.buttonStyle(GlassIconButtonStyle(size: 32))
                    Spacer()
                    Text(TimeFormat.remaining(player.position, player.duration))
                        .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
                        .opacity(0.72)
                        .padding(.bottom, 5)
                    Button { player.togglePinnedMini() } label: { Image(systemName: "arrow.up.backward.and.arrow.down.forward") }
                        .buttonStyle(GlassIconButtonStyle(size: 28))
                        .padding(.bottom, 1)
                        .help("退出迷你窗（⇧⌘M）")
                }
            }
            .frame(height: 110)
            .foregroundStyle(Color.ink)
        }
        .padding(.top, 30)
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // 单层纯净黑曜石磨砂窗口本体，彻底去除外部多余双层背景框
        .glass(shape, tint: Color(player.palette.glassTint), amount: 0.08, interactive: true, variant: .clear)
        .obsidianChrome()
        .clipShape(shape)
    }

    private var video: some View {
        ZStack(alignment: .bottom) {
            VideoStage(mini: true)
            if player.chromeVisible || hover {
                HStack(spacing: 4) {
                    Button { player.seek(by: -player.seekStepSeconds) } label: { Image(systemName: "gobackward.15") }.buttonStyle(GlassIconButtonStyle(size: 30))
                    Button { player.togglePlay() } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").contentTransition(.symbolEffect(.replace.downUp.byLayer))
                    }.buttonStyle(GlassIconButtonStyle(size: 36, prominent: true))
                    Button { player.seek(by: player.seekStepSeconds) } label: { Image(systemName: "goforward.15") }.buttonStyle(GlassIconButtonStyle(size: 30))
                    ProgressScrubber(hover: true).frame(width: 180)
                    Button { player.togglePinnedMini() } label: { Image(systemName: "arrow.up.backward.and.arrow.down.forward") }
                        .buttonStyle(GlassIconButtonStyle(size: 28))
                }
                .padding(.horizontal, 10).frame(height: 48)
                .glass(Capsule(), tint: Color(player.palette.glassTint), amount: 0.06, interactive: true, variant: .clear)
                .obsidianChrome()
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.panel, value: player.chromeVisible || hover)
    }
}

/// 键盘快捷键一览（帮助 ▸ 键盘快捷键，⌘/；Esc 关闭）
struct ShortcutsOverlay: View {
    @Environment(PlayerController.self) private var player
    private let groups: [(String, [(String, String)])] = [
        ("播放", [("空格", "播放 / 暂停"), ("← →", "快退 / 快进 15 秒（按住连续快进快退）"), ("Esc", "一层层退出：卡片、翻面、全屏、迷你窗…"), ("⌘← ⌘→", "上一首 / 下一首"), ("⌘.", "停止"), ("⌘J", "跳转到时间"), ("[ ] \\", "减速 / 加速 / 正常"), ("⌘R", "循环模式"), ("⌥⌘S", "随机播放"), ("⌥⌘B", "A-B 循环")]),
        ("音频", [("↑ ↓ / ⌘↑ ⌘↓", "音量"), ("M", "静音"), ("⌥⌘E", "均衡器开关")]),
        ("视频", [("F", "全屏"), ("⌥⌘R", "旋转 90°"), ("⌥⌘C", "截图"), ("⇧⌘U", "加载外挂字幕")]),
        ("文件与列表", [("⌘O / ⇧⌘O", "打开文件 / 文件夹"), ("⌘U", "打开网址"), ("⌥⌘O", "添加到播放列表"), ("⌘S / ⇧⌘L", "保存 / 载入播放列表"), ("⌘L", "定位当前曲目"), ("⌘⌫ / ⇧⌘⌫", "移除当前 / 清空"), ("⇧⌘R", "在访达中显示")]),
        ("显示与窗口", [("点底栏封面", "卡片模式 ↔ 全屏模式一键往返"), ("⌘1 ⌘2 ⌘3", "正在播放 / 列表 / 均衡器"), ("E / L", "均衡器 / 播放列表"), ("⇧⌘M", "迷你窗"), ("⌘Y", "观赏封面（双击专辑卡；观赏里单击即退）"), ("⌥⌘T", "窗口置顶"), ("回车 / 单击", "翻转中心卡片（右下角铅笔编辑 ID3）"), (", .", "轮播左右翻"), ("Esc", "逐层返回")]),
    ]
    var body: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { player.toggleShortcutsHelp() }
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("键盘快捷键").font(.system(size: 20, weight: .bold))
                    Spacer()
                    Button { player.toggleShortcutsHelp() } label: { Image(systemName: "xmark") }.buttonStyle(GlassIconButtonStyle(size: 28))
                }
                HStack(alignment: .top, spacing: 26) {
                    ForEach(Array(groups.enumerated()), id: \.offset) { _, g in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(g.0).font(.system(size: 12, weight: .bold)).opacity(0.6)
                            ForEach(Array(g.1.enumerated()), id: \.offset) { _, k in
                                HStack(spacing: 8) {
                                    Text(k.0).font(.system(size: 11.5, weight: .semibold, design: .rounded)).padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Capsule().fill(Color.inkFill.opacity(0.12)))
                                    Text(k.1).font(.system(size: 12)).opacity(0.85)
                                }
                            }
                        }
                    }
                }
            }
            .foregroundStyle(Color.ink)
            .padding(24)
            .glass(RoundedRectangle(cornerRadius: 26, style: .continuous), tint: Color(player.palette.glassTint), amount: 0.08, variant: .floating)
            .padding(30)
        }
    }
}
