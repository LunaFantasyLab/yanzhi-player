// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PlayerCore

/// 主界面骨架：环境色背景 → 顶部分段（正在播放 / 播放列表 / 均衡器）→ 内容 → 底部玻璃播放条 → HUD / 拖放蒙层。
struct RootView: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 860
            let videoChromeHidden = player.videoStageOpen && player.tab == .nowPlaying && !player.chromeVisible
            let immersive = VideoLayout.isImmersiveVideo(fullscreen: player.windowFullScreen, videoStageOpen: player.videoStageOpen, mini: player.isPinnedMini, nowPlaying: player.tab == .nowPlaying)
            let showAppHeader = EmptyProjectLayout.showsApplicationHeader(queueIsEmpty: player.queue.items.isEmpty, videoStageOpen: player.videoStageOpen, mini: player.isPinnedMini, nowPlaying: player.tab == .nowPlaying)
            let showPlayChrome = EmptyProjectLayout.showsPlayChrome(queueIsEmpty: player.queue.items.isEmpty, videoStageOpen: player.videoStageOpen, mini: player.isPinnedMini, nowPlaying: player.tab == .nowPlaying)
            let hideOuterBG = immersive || (player.isPinnedMini && !player.isVideo)
            ZStack {
                AmbientBackground()
                    .opacity(hideOuterBG ? 0 : 1)
                if immersive { Color.black.ignoresSafeArea() }
                FrameClockAnchor().frame(width: 1, height: 1).allowsHitTesting(false)
                // 空白处右键
                Color.clear.contentShape(Rectangle())
                    // 视频舞台上点画面外的空白处：回到封面轮播
                    .onTapGesture { if player.videoStageOpen && player.tab == .nowPlaying { player.exitVideoStage() } }
                    .contextMenu { MenuContent(nodes: MenuCatalog.blank(player)) }

                ZStack {
                    if player.isPinnedMini {
                        MiniPlayerView()
                            .ignoresSafeArea()
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.94)), removal: .opacity))
                    } else if immersive {
                        // 视频全屏：画面按比例铺满窗口，控件叠在上面不占布局；留下的空边只来自片源比例，底为黑。
                        content(compact: compact)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .ignoresSafeArea()
                            .blur(radius: player.cardOpen ? CardScrim.blurRadius : 0)
                            .animation(.easeInOut(duration: 0.28), value: player.cardOpen)
                            .overlay { CardScrim() }
                            .overlay(alignment: .top) {
                                if showAppHeader {
                                    topBar(compact: compact)
                                        .obsidianChrome()
                                        .padding(.top, 14)
                                        .opacity(videoChromeHidden ? 0 : 1)
                                        .offset(y: videoChromeHidden ? -20 : 0)
                                        .allowsHitTesting(!videoChromeHidden)
                                }
                            }
                            .overlay(alignment: .bottom) {
                                if showPlayChrome {
                                    PlayBar(compact: compact)
                                        .obsidianChrome()
                                        .padding(.horizontal, compact ? 12 : 32)
                                        .frame(maxWidth: 1400)
                                        .padding(.bottom, 18)
                                        .opacity(videoChromeHidden ? 0 : 1)
                                        .offset(y: videoChromeHidden ? 40 : 0)
                                        .scaleEffect(videoChromeHidden ? 0.96 : 1)
                                        .allowsHitTesting(!videoChromeHidden)
                                }
                            }
                            .animation(Motion.panel, value: videoChromeHidden)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.03)), removal: .opacity))
                    } else {
                        VStack(spacing: 0) {
                            VStack(spacing: 0) {
                                if showAppHeader {
                                    topBar(compact: compact)
                                        .obsidianChrome()
                                        .padding(.top, 14)
                                        .opacity(videoChromeHidden ? 0 : 1)
                                        .offset(y: videoChromeHidden ? -20 : 0)
                                }
                                content(compact: compact)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.horizontal, player.tab == .nowPlaying ? 0 : 28)
                                    .padding(.vertical, 12)
                            }
                            // 参数卡片打开时：卡片后面的界面淡淡磨砂、稍微压暗，点一下收起
                            // 模糊滤镜一直挂着（关着时半径 0.01，肉眼无差别），开关卡片时只改半径，不用临时插入 / 拆掉滤镜层（那一下会卡一帧）
                            .blur(radius: player.cardOpen ? CardScrim.blurRadius : 0)
                            .animation(.easeInOut(duration: 0.28), value: player.cardOpen)
                            .overlay { CardScrim() }
                            if showPlayChrome {
                                PlayBar(compact: compact)
                                    .obsidianChrome()
                                    .padding(.horizontal, compact ? 12 : 32)
                                    .frame(maxWidth: 1400)
                                    .padding(.bottom, 18)
                                    .opacity(videoChromeHidden ? 0 : 1)
                                    .offset(y: videoChromeHidden ? 40 : 0)
                                    .scaleEffect(videoChromeHidden ? 0.96 : 1)
                            }
                        }
                        .animation(Motion.panel, value: videoChromeHidden)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.03)), removal: .opacity))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .backgroundPreferenceValue(VideoSlotKey.self) { slots in VideoHost(slots: slots) }

                if let hud = player.hud {
                    HUDView(message: hud)
                        .id(hud.id)
                        .transition(.scale(scale: 0.82).combined(with: .opacity))
                }

                if player.isDropTargeted || player.videoDropTargeted {
                    DropOverlay(mini: player.isPinnedMini).transition(.opacity.combined(with: .scale(scale: 1.03)))
                }

                if player.showShortcuts {
                    ShortcutsOverlay().transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                // 全局 ID3 标签与专辑封面编辑弹层（编辑卡片本身 100% 不透明，彻底避免打字时与底层内容视觉重叠）
                if let id = player.tagEditorItemID, let item = player.item(withID: id) {
                    ZStack {
                        Color.black.opacity(0.42).ignoresSafeArea().onTapGesture { player.closeTagEditor() }
                        TagEditorSheet(item: item).id(id)
                    }
                    .obsidianChrome()
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                    .zIndex(50)
                }

                // 右上角配色调色盘按钮：保留 11-23 黑曜石外观，并突破顶部安全区向左上微移，贴合窗口右上角形成柔和切入角关系
                if !player.isPinnedMini && showAppHeader && !videoChromeHidden {
                    HStack(spacing: 8) {
                        ThemeButton()
                    }
                    .obsidianChrome()
                    .padding(.top, 6)
                    .padding(.trailing, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .ignoresSafeArea(.container, edges: .top)
                    .transition(.opacity)
                }

                // 封面观赏模式：常驻最上层、平时隐藏（打开时不新建视图，避免第一帧卡顿）
                CoverViewerLayer()
            }
            .animation(Motion.toggle, value: player.hud?.id)
            .animation(Motion.panel, value: player.isDropTargeted)
            .animation(Motion.panel, value: player.videoDropTargeted)
            .animation(Motion.panel, value: player.isPinnedMini)
            .animation(Motion.panel, value: player.showShortcuts)
            .animation(Motion.panel, value: player.tagEditorItemID)
        }
        .frame(minWidth: player.isPinnedMini ? 340 : 760, minHeight: player.isPinnedMini ? 152 : 520)
        .environment(\.glassMidnight, player.look.isPureBlack)
        .environment(\.glassLight, player.look.isLight)
        .environment(\.glassLiuli, player.look.isLiuli)
        .animation(Motion.themeChange, value: player.look)
        // 白主题用浅色外观（系统材质、右键菜单、对话框一起变浅），其余主题保持深色
        .preferredColorScheme(player.look.isLight ? .light : .dark)
        // 拖到窗口任何地方（含迷你窗）：按顺序加入并立即播放第一个；拖到播放列表上由列表自己处理“插入”
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { player.isDropTargeted }, set: { v in withAnimation(Motion.panel) { player.isDropTargeted = v } })) { providers in
            PlayerController.loadFileURLs(providers) { urls in player.open(urls, playNow: true) }
            return true
        }
        .onAppear {
            if let i = player.queue.currentIndex { player.prefetchAround(i) }
            player.syncWindowFullScreen()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in player.syncWindowFullScreen() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in player.syncWindowFullScreen() }
        .alert("清空播放记录？", isPresented: Bindable(player).asksClearPlayHistory) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) { player.clearPlayHistory() }
        } message: {
            Text("只会清除这里的记录，不会删除磁盘上的文件，也不会改动当前播放列表、收藏或其它偏好。")
        }
    }

    // 顶部：仿 visionOS 的分段玻璃胶囊（参考图 02）
    private func topBar(compact: Bool) -> some View {
        HStack {
            Spacer()
            // 均衡器不再放在这一栏（入口在音量旁边，悬停时出现；菜单、右键、⌘3 照旧）
            GlassSegmented(options: [MainTab.nowPlaying, .playlist].map { GlassSegmented<MainTab>.Option(id: $0, title: $0.title, symbol: nil) },
                           selection: player.tab, compact: compact) { t in
                player.selectTab(t)
                if t == .nowPlaying && player.videoStageOpen { player.exitVideoStage() }
            }
            .fixedSize()
            Spacer()
        }
        .overlay(alignment: .leading) {
            // 视频舞台：左上角看得见的出口（Esc、点空白处、双指横扫、右键也行）
            if player.videoStageOpen && player.tab == .nowPlaying && !player.isPinnedMini {
                Button { player.exitVideoStage() } label: {
                    Label("返回", systemImage: "chevron.backward").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(GlassChipStyle(selected: false, accent: Color(player.palette.accent)))
                .help("回到封面轮播（Esc）")
                .accessibilityLabel("返回封面轮播")
                .padding(.leading, 84)      // 让开左上角的红绿灯
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .overlay(alignment: .trailing) {
            if player.isPinnedMini {
                Label("置顶中", systemImage: "pin.fill").font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10).frame(height: 24)
                    .glass(Capsule(), amount: 0.05, elevated: false)
                    .transition(.scale.combined(with: .opacity))
                    .padding(.trailing, 10)
            }
        }
        .animation(Motion.toggle, value: player.isPinnedMini)
        .animation(Motion.toggle, value: player.videoStageOpen)
    }

    @ViewBuilder private func content(compact: Bool) -> some View {
        ZStack {
            if player.showPlayHistory {
                PlayHistoryView()
                    .frame(maxWidth: 1240)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.97))))
            } else {
            switch player.tab {
            case .nowPlaying:
                Group {
                    if player.queue.items.isEmpty {
                        EmptyLibraryView()
                    } else if player.videoStageOpen {
                        let immersive = VideoLayout.isImmersiveVideo(fullscreen: player.windowFullScreen, videoStageOpen: true, mini: player.isPinnedMini, nowPlaying: player.tab == .nowPlaying)
                        let pad = VideoLayout.stagePadding(fullscreen: immersive, compact: compact)
                        VideoStage().padding(.horizontal, pad.horizontal)
                    } else {
                        CoverCarousel()
                            .overlay(alignment: .bottomTrailing) {
                                LyricsToggle()
                                    .padding(.trailing, compact ? 44 : 96)
                                    .padding(.bottom, 4)
                            }
                    }
                }
                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                        removal: .opacity.combined(with: .scale(scale: 1.02))))
            case .playlist:
                PlaylistView()
                    .frame(maxWidth: 1240)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.97))))
            case .equalizer:
                // 2026-11-24：21:9 全幅对齐底部控制条（1400pt），16 段与 32 段均舒展铺开、绝不拥挤
                EqualizerView()
                    .frame(maxWidth: 1400, maxHeight: 540)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity),
                                            removal: .opacity.combined(with: .scale(scale: 0.97))))
            }
            } // showPlayHistory
        }
        .animation(Motion.tab, value: player.tab)
        .animation(Motion.tab, value: player.showPlayHistory)
        .animation(Motion.panel, value: player.videoStageOpen)
        .animation(Motion.panel, value: player.queue.items.isEmpty)
    }

}

/// 线程安全的小容器（拖放回调在后台线程）
final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _urls: [URL] = []
    func append(_ u: URL) { lock.lock(); _urls.append(u); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return _urls }
}

/// 音量、倍速、循环等快捷键反馈：居中的玻璃小方块，弹入后自动消失
struct HUDView: View {
    let message: HUDMessage
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: message.symbol).font(.system(size: 30, weight: .medium))
                .symbolEffect(.bounce, value: message.id)
            Text(message.text).font(.system(size: 13, weight: .semibold)).multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 18)
        .frame(minWidth: 150, maxWidth: 300, minHeight: 130)
        .fixedSize(horizontal: false, vertical: true)
        .glass(RoundedRectangle(cornerRadius: 26, style: .continuous), amount: 0.05, variant: .floating, tracksPointer: false)
        .allowsHitTesting(false)
    }
}

/// 拖入文件时的蒙层：整窗变成一块“被点亮的玻璃”——边缘亮起强调色、中央一块玻璃提示牌轻轻呼吸
struct DropOverlay: View {
    @Environment(PlayerController.self) private var player
    var mini = false
    @State private var pulse = false
    var body: some View {
        let accent = Color(player.palette.accent)
        let r = RoundedRectangle(cornerRadius: mini ? 16 : 30, style: .continuous)
        ZStack {
            Color.black.opacity(0.22)
            // 扁平的“被点亮的玻璃框”：淡强调色铺底 + 1.5px 亮边，亮度轻轻呼吸
            r.fill(accent.opacity(pulse ? 0.14 : 0.08))
                .overlay(r.strokeBorder(Color.edge.opacity(pulse ? 0.9 : 0.6), lineWidth: 1.5))
                .padding(mini ? 8 : 22)
            VStack(spacing: mini ? 6 : 12) {
                Image(systemName: "square.and.arrow.down.on.square").font(.system(size: mini ? 24 : 40, weight: .light))
                    .symbolEffect(.bounce, options: .repeating, value: pulse)
                Text("松手立即播放").font(.system(size: mini ? 13 : 17, weight: .semibold))
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, mini ? 18 : 34).padding(.vertical, mini ? 12 : 26)
            .glass(RoundedRectangle(cornerRadius: mini ? 16 : 26, style: .continuous), tint: accent, amount: 0.10, variant: .floating, tracksPointer: false)
            .scaleEffect(pulse ? 1.015 : 1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
        .onAppear { pulse = true }
    }
}
