// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

/// 底部玻璃胶囊播放条（参考图 01/02）：
/// 左：上一首 / 播放暂停 / 下一首；中：小封面 + 曲名歌手 + 进度；右：循环、随机、字幕音轨（视频）、均衡器、音量、列表。
struct PlayBar: View {
    @Environment(PlayerController.self) private var player
    var compact: Bool
    /// 卡片第一次出现：从下方轻轻浮起、淡入；之后卡片之间切换只做淡入淡出（见 CardStack）
    static let cardTransition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 10)),
        removal: .opacity.combined(with: .offset(y: 8)))
    static let panelTransition = AnyTransition.asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .bottom)),
        removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottom)))

    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            HStack(spacing: 2) {
                RepeatModeButton()
                Button { player.scanButtonTapped(-1) } label: { Image(systemName: "backward.fill") }
                    .buttonStyle(ScanButtonStyle(direction: -1, size: 36))
                    .help("轻点：上一首（⌘←）；长按：快退，按得越久越快，松手恢复播放")
                Button { player.togglePlay() } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer))
                        .offset(x: player.isPlaying ? 0 : 1.5)
                }
                .buttonStyle(GlassIconButtonStyle(size: 44, prominent: true))
                .help("播放 / 暂停（空格）")
                Button { player.scanButtonTapped(1) } label: { Image(systemName: "forward.fill") }
                    .buttonStyle(ScanButtonStyle(direction: 1, size: 36))
                    .help("轻点：下一首（⌘→）；长按：快进，按得越久越快，松手恢复播放")
            }

            NowPill(compact: compact)

            // 右侧只留常用的：视频的字幕音轨菜单、音量、视频全屏。
            // 循环/随机、变速变调、均衡器、输出设备、歌词都收进了菜单、右键菜单或点一下展开的入口（见 docs/第三轮-界面收纳清单.md）
            HStack(spacing: 2) {
                if player.isVideo {
                    TrackMenu().transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                VolumeControl()
                if player.isVideo {
                    Button { player.toggleFullScreen() } label: {
                        Image(systemName: player.windowFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                        .buttonStyle(GlassIconButtonStyle(size: 32))
                        .help(player.windowFullScreen ? "退出全屏（F）" : "全屏（F）")
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 64)
        .glass(Capsule(), tint: Color(player.palette.glassTint), amount: 0.06, interactive: true, variant: .clear)
        .contextMenu { MenuContent(nodes: MenuCatalog.playBar(player)) }
        .animation(Motion.toggle, value: player.isVideo)
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if player.asrProgress != nil {
                    ASRProgressCapsule().fixedSize().transition(Self.panelTransition)
                }
                // 参数卡片：同一时间只有一张；切换时旧的收起、新的从同一位置浮出（交叉过渡，不叠两张）
                // 打开过的卡片留在界面里（隐藏时透明、不接收点击），再次切换只做透明度 / 缩放过渡，不用重新创建控件——切换更顺
                CardStack()
                if player.showsLyricsStrip && player.tab == .nowPlaying && !player.cardOpen, let l = player.lyrics {
                    LyricsStrip(lyrics: l, width: compact ? 360 : 440).transition(Self.panelTransition)
                }
            }
            .alignmentGuide(.top) { d in d[.bottom] + 8 }
        }
        .animation(Motion.panel, value: player.cardOpen)
        .animation(Motion.panel, value: player.asrProgress == nil)
        .animation(Motion.panel, value: player.showsLyricsStrip)
    }
}

/// 参数卡片堆：同一时间只有一张；只有这一小块读 visibleCard，卡片之间切换时只重算这里
struct CardStack: View {
    @Environment(PlayerController.self) private var player
    /// 打开过的卡片留在界面里（隐藏时透明、不接收点击），再次切换只做透明度过渡，不用重新创建控件
    @State private var mountedCards: Set<ParamCard> = []
    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(ParamCard.allCases.filter { mountedCards.contains($0) || player.visibleCard == $0 }, id: \.self) { c in
                let on = player.visibleCard == c
                ParamCardView(card: c)
                    .fixedSize()
                    // 先把这张卡（含 ultraThinMaterial 玻璃）合成到一层，再只改整层透明度。
                    // 半透明直接打在 Material 上时，系统会每帧按当前 alpha 重采样背后的磨砂页，切卡交叉淡入会把主线程占满。
                    // 合成后再淡，外观在静止态与原先一致，弹簧仍走 Motion.panel，布局与交互不变。
                    .compositingGroup()
                    .opacity(on ? 1 : 0)
                    .allowsHitTesting(on)
                    .accessibilityHidden(!on)
                    .zIndex(on ? 1 : 0)
                    .transition(PlayBar.cardTransition)
            }
        }
        .onChange(of: player.visibleCard) { _, c in if let c { mountedCards.insert(c) } }
        .animation(Motion.panel, value: player.activeCard)
    }
}

/// 一张参数卡片
struct ParamCardView: View {
    @Environment(PlayerController.self) private var player
    let card: ParamCard
    var body: some View {
        Group {
            switch card {
            case .loop: LoopEditor()
            case .speedPitch: SpeedPitchPanel()
            case .subtitle: SubtitleSearchPanel()
            case .autoEq: AutoEqPanel()
            }
        }
        // t180u：参数卡不再挂云纹，以免与卡片页左上原四重复。
        .contextMenu { MenuContent(nodes: MenuCatalog.paramCard(player, card)) }
    }
}

/// 卡片打开时：卡片后面的界面轻度高斯模糊（RootView 上的 .blur，视频画面由 VideoSurfaceView 自己的图层滤镜模糊），
/// 这里再盖一层很淡的压暗（白主题提亮）；点一下收起卡片。模糊半径小，背景仍能看出是什么。
struct CardScrim: View {
    @Environment(PlayerController.self) private var player
    static let blurRadius: CGFloat = 5
    var body: some View {
        let on = player.cardOpen
        let light = player.look.isLight
        Color(light ? .white : .black).opacity(on ? (light ? 0.18 : 0.16) : 0)
            .animation(.easeInOut(duration: 0.28), value: on)
            .overlay { ScrimClickCatcher(enabled: on) { player.closeCard() } }
            .allowsHitTesting(on)
            .ignoresSafeArea()
            .onChange(of: player.isVideo) { _, v in player.videoSurface.setBlur(on && v ? 6 : 0) }
    }
}

/// 磨砂层上的点击：用 AppKit 视图直接接 mouseDown（比手势识别更确定，真实点击和自测合成点击都一样）
struct ScrimClickCatcher: NSViewRepresentable {
    var enabled: Bool
    var action: () -> Void
    final class V: NSView {
        var enabled = false
        var action: () -> Void = {}
        override func hitTest(_ p: NSPoint) -> NSView? { enabled ? super.hitTest(p) : nil }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { if enabled { action() } }
    }
    func makeNSView(context: Context) -> V { let v = V(); v.enabled = enabled; v.action = action; return v }
    func updateNSView(_ v: V, context: Context) { v.enabled = enabled; v.action = action }
}

/// 播放条上方的歌词条：三行左右，当前行放大高亮，跟着播放弹簧滚动
struct LyricsStrip: View {
    @Environment(PlayerController.self) private var player
    let lyrics: Lyrics
    var width: CGFloat = 440
    var body: some View {
        LyricsView(lyrics: lyrics, fontSize: 13, centered: true)
            .frame(width: width, height: 58)
            .padding(.horizontal, 16)
            .foregroundStyle(Color.ink)
            .glass(RoundedRectangle(cornerRadius: 20, style: .continuous), tint: Color(player.palette.glassTint), amount: 0.05, interactive: true, variant: .clear)
            .contextMenu { MenuContent(nodes: MenuCatalog.lyricsArea(player)) }
            .help("歌词来自 LRCLIB；点一行跳到那里")
    }
}

/// 中间的“正在播放”胶囊：小封面、曲名、歌手、进度。悬停时进度条加粗并显示时间，可拖动定位。
struct NowPill: View {
    @Environment(PlayerController.self) private var player
    var compact: Bool
    @State private var hover = false
    @State private var thumbHover = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if let cur = player.current, let art = player.art(for: cur) {
                    Image(decorative: art.thumbnail, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                        .id(cur.id + art.fadeID).transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else {
                    LinearGradient(colors: [Color(player.palette.tertiary), Color(player.palette.primary)], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(thumbHover ? 1.07 : 1)
            .animation(Motion.hover, value: thumbHover)
            .animation(Motion.toggle, value: player.current?.id)
            .background(ViewerRectProbe(key: "playbar", radius: 8))
            .modifier(ViewerHide(key: "playbar"))
            .contentShape(Rectangle())
            .onHover { thumbHover = $0 }
            // 一键极简往返：全屏 / 视频 / 列表 / 均衡器 / 记录里点一下回卡片模式；卡片模式里点一下进全屏模式
            .onTapGesture { player.toggleCardOrFullscreen() }
            .help(player.inCardMode ? "进入全屏模式" : "回到卡片模式")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(player.inCardMode ? "进入全屏模式" : "回到卡片模式")

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        if let title = player.current?.title, !title.isEmpty {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                .contentTransition(.opacity)
                        }
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.system(size: 11)).opacity(0.62).lineLimit(1)
                                .contentTransition(.opacity)
                        }
                    }
                    Spacer(minLength: 8)
                    if player.speed != 1 || player.pitchSemitones != 0 || player.pitchCents != 0 {
                        HStack(spacing: 1) {
                            SpeedPitchChip()
                            // 一键恢复 100% 速度和原调
                            Button { player.resetSpeedPitch() } label: {
                                Image(systemName: "arrow.counterclockwise").font(.system(size: 9, weight: .bold)).frame(width: 16, height: 16).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(Color(player.palette.accent).opacity(0.85))
                            .help("恢复 100% 速度、原调（⌥\\ 或 Esc）")
                            .accessibilityLabel("恢复正常速度和原调")
                        }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                    PlayModeStatus()
                    TimeLabel(hover: hover)
                }
                ProgressScrubber(hover: hover)
            }
            .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 16)
        // 21:9 宽幅控制条同步拉长：NowPill 与内部播放进度条自适应撑满控制条中段（不再锁死 520pt）
        .frame(minWidth: compact ? 220 : 360, maxWidth: .infinity)
        .frame(height: 50)
        .background {
            // 扁平的内嵌区：比玻璃暗一档（11-23 无边框规范）
            let r = RoundedRectangle(cornerRadius: 14, style: .continuous)
            r.fill(Color.black.opacity(hover ? 0.20 : 0.13))
        }
        .onHover { h in withAnimation(Motion.hover) { hover = h } }
        .animation(Motion.symbol, value: player.current?.id)
        .animation(Motion.toggle, value: player.abA != nil)
    }

    private var subtitle: String {
        guard let c = player.current else { return "" }
        return [c.knownArtist, c.album].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " — ")
    }
}

/// 随机播放的状态：只在开着时出现一个很小的图标，点一下关闭
/// 播放栏最左边的循环播放按钮：比旁边的按钮更显眼一点，三种状态一眼能分清——
/// 不循环：灰色描线图标；列表循环：强调色图标 + 强调色底；单曲循环：强调色「1」图标 + 更实的强调色底 + 外圈。切换有过渡动画。
private struct RepeatModeButton: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        let accent = Color(player.palette.accent)
        let mode = player.queue.repeatMode
        Button { player.cycleRepeat() } label: {
            Image(systemName: mode == .one ? "repeat.1" : "repeat")
                .font(.system(size: 15, weight: .bold))
                .contentTransition(.symbolEffect(.replace.downUp))
                .foregroundStyle(mode == .off ? AnyShapeStyle(Color.ink.opacity(0.42)) : AnyShapeStyle(accent))
                .frame(width: 38, height: 38)
                .background {
                    ZStack {
                        Circle().fill(accent.opacity(mode == .off ? 0 : (mode == .one ? 0.34 : 0.20)))
                        Circle().strokeBorder(accent.opacity(mode == .one ? 0.75 : 0), lineWidth: 1.5)
                    }
                    .scaleEffect(mode == .off ? 0.6 : 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle())
        .help("\(mode.label)（点一下切换：不循环 → 列表循环 → 单曲循环；⌘R）")
        .animation(Motion.toggle, value: mode)
    }
}

/// 只有按下缩放的按钮样式
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1).animation(Motion.press, value: configuration.isPressed)
    }
}

/// 上一首 / 下一首按钮：外观同其他玻璃图标按钮；按住超过 0.35 秒开始快退 / 快进，上方出现低调的倍速提示，松手恢复播放
struct ScanButtonStyle: ButtonStyle {
    var direction: Int
    var size: CGFloat
    func makeBody(configuration: Configuration) -> some View { ScanButtonBody(configuration: configuration, direction: direction, size: size) }
}

private struct ScanButtonBody: View {
    @Environment(PlayerController.self) private var player
    let configuration: ButtonStyleConfiguration
    let direction: Int
    let size: CGFloat
    @State private var holdTask: Task<Void, Never>?
    var body: some View {
        let scanning = player.scanDirection == direction
        GlassIconButton(configuration: configuration, size: size, prominent: false, active: scanning, accent: Color(player.palette.accent))
            .scaleEffect(scanning ? 0.94 : 1)
            .overlay(alignment: .top) {
                if scanning {
                    Text("\(direction > 0 ? "快进" : "快退") ×\(Int(player.scanRate))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.ink.opacity(0.85))
                        .padding(.horizontal, 7).frame(height: 18)
                        .background(Capsule().fill(.ultraThinMaterial).opacity(0.9))
                        .fixedSize()
                        .offset(y: -24)
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .bottom)))
                        .allowsHitTesting(false)
                }
            }
            .animation(Motion.toggle, value: scanning)
            .animation(Motion.toggle, value: player.scanRate)
            .onChange(of: configuration.isPressed) { _, pressed in
                holdTask?.cancel()
                if pressed {
                    holdTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(ScanMath.holdThreshold * 1e9))
                        if !Task.isCancelled { player.beginScan(direction) }
                    }
                } else if player.scanDirection == direction {
                    player.endScan()
                }
            }
    }
}

private struct PlayModeStatus: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        let accent = Color(player.palette.accent)
        HStack(spacing: 2) {
            // 区间循环开着时：播放栏里一直有个看得见的标签，点 × 取消，恢复正常播放
            if player.abA != nil {
                Button { player.clearABLoop() } label: {
                    HStack(spacing: 2) {
                        Text(player.abB == nil ? "A-" : "A-B").font(.system(size: 9.5, weight: .bold, design: .rounded))
                        Image(systemName: "xmark").font(.system(size: 7.5, weight: .heavy))
                    }
                    .padding(.horizontal, 5).frame(height: 16)
                    .background(Capsule().fill(accent.opacity(0.16)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(accent)
                .help("区间循环：开（点一下取消，⌥⌘B 或 Esc 也行）")
                .accessibilityLabel("取消区间循环")
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
            if player.queue.shuffle {
                Button { player.toggleShuffle() } label: {
                    Image(systemName: "shuffle").font(.system(size: 9.5, weight: .bold)).frame(width: 16, height: 16).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(accent.opacity(0.85))
                .help("随机播放：开（点一下关闭；⌥⌘S）")
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .animation(Motion.toggle, value: player.queue.shuffle)
        .animation(Motion.toggle, value: player.abA != nil)
    }
}

/// 播放画面里的小歌词开关（音频、正在播放页）：放在画面右下、离边缘留一段距离
struct LyricsToggle: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        let accent = Color(player.palette.accent)
        Button { player.toggleLyrics() } label: {
            Image(systemName: player.lyricsEnabled ? "quote.bubble.fill" : "quote.bubble").font(.system(size: 11, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(GlassIconButtonStyle(size: 26, active: player.lyricsEnabled, accent: accent))
        .help(player.lyricsEnabled ? "歌词：开（从 LRCLIB 自动找带时间轴的歌词，找不到就不显示）" : "歌词：关（点一下自动搜索歌词）")
        .contextMenu { MenuContent(nodes: MenuCatalog.lyricsArea(player)) }
    }
}

private struct TimeLabel: View {
    @Environment(PlayerController.self) private var player
    var hover: Bool
    var body: some View {
        Text(hover ? "\(TimeFormat.clock(player.position)) / \(TimeFormat.clock(player.duration))" : TimeFormat.remaining(player.position, player.duration))
            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
            .opacity(0.7)
            .contentTransition(.numericText())
            .animation(Motion.hover, value: hover)
    }
}

/// 进度条：120Hz 插值的位置；悬停变粗、出现游标；拖动实时预览，松手才 seek。
/// 区间循环：循环区展开后在原曲进度条上拖选一段（指针切换，松手即在原时间轴上循环）；已有区间时两端手柄可直接拖动微调。
struct ProgressScrubber: View {
    @Environment(PlayerController.self) private var player
    var hover: Bool
    @State private var hoverX: CGFloat?
    private enum Mode { case seek, select(Double), handleA, handleB }
    @State private var mode: Mode?
    /// 拖选/拖手柄时的临时区间（松手才写给 mpv）
    @State private var temp: (Double, Double)?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let frac = progressFraction
            let range = shownRange
            let active = hover || player.isScrubbing || (drawing && range != nil)
            let h: CGFloat = active ? 6 : 3
            ZStack(alignment: .leading) {
                Capsule().fill(Color.inkFill.opacity(0.16))
                Capsule()
                    .fill(LinearGradient(colors: [Color(player.palette.accent).opacity(0.85), Color.ink], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(h, w * frac))
                // 段落检测结果：副歌是强调色小段，其他重复段是淡色小段（在进度条下沿，悬停时更明显）
                if let d = player.duration, d > 0, !player.sections.isEmpty {
                    ForEach(Array(player.sections.enumerated()), id: \.offset) { _, sec in
                        let xa = w * CGFloat(sec.start / d), xb = w * CGFloat(sec.end / d)
                        Capsule()
                            .fill(sec.label.hasPrefix("副歌") ? Color(player.palette.accent).opacity(active ? 0.75 : 0.45) : Color.ink.opacity(active ? 0.28 : 0.14))
                            .frame(width: max(3, xb - xa - 2), height: 2)
                            .offset(x: xa + 1, y: h / 2 + 3)
                            .allowsHitTesting(false)
                    }
                    .transition(.opacity)
                }
                // 选中区间：扁平的半透明玻璃条 + 1px 亮边，两端是可拖的细手柄
                // 循环区收起时：区间只用一段很淡的强调色标在进度条上，不显示手柄、不能拖
                if !drawing, temp == nil, let rg = range, let d = player.duration, d > 0 {
                    let xa = w * CGFloat(rg.0 / d), xb = w * CGFloat(rg.1 / d)
                    Capsule().fill(loopRangeColor.opacity(0.55))
                        .frame(width: max(3, xb - xa), height: h)
                        .offset(x: xa)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if let rg = range, let d = player.duration, d > 0, drawing || temp != nil {
                    let xa = w * CGFloat(rg.0 / d), xb = w * CGFloat(rg.1 / d)
                    LoopRangeView(width: max(4, xb - xa), height: h + 8, accent: loopRangeColor,
                                  editing: temp != nil)
                        .offset(x: xa)
                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.6, anchor: .center)),
                                                removal: .opacity.combined(with: .scale(scale: 1.15, anchor: .center))))
                } else if drawing, let a = player.abA, player.abB == nil, let d = player.duration, d > 0 {
                    // 只设了起点：一根细竖线
                    Capsule().fill(Color(player.palette.accent)).frame(width: 2, height: h + 10)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 0.5))
                        .offset(x: w * CGFloat(a / d) - 1)
                        .transition(.opacity.combined(with: .scale(scale: 0.4)))
                }
                if let x = hoverX, hover {
                    Capsule().fill(Color.ink.opacity(0.55)).frame(width: 2, height: h + 6).offset(x: x - 1)
                        .transition(.opacity)
                }
                Circle().fill(.white).frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                    .offset(x: w * frac - 6)
                    .scaleEffect(hover || player.isScrubbing ? 1 : 0.01)
                    .opacity(hover || player.isScrubbing ? 1 : 0)
            }
            .frame(height: h)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let p) = phase {
                    hoverX = p.x
                    if LoopScrub.cursorIndicatesSelect(player.loopEditorOpen) { NSCursor.crosshair.set() }
                } else {
                    hoverX = nil
                    NSCursor.arrow.set()
                }
            }
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in changed(v, w) }
                .onEnded { v in ended(v, w) })
            .help(drawing ? "循环区已展开：拖动框选区间，指针会换成十字；拖两端可微调。循环仍在原曲时间轴上播放" : "拖动跳转")
            .animation(Motion.hover, value: hover)
            .animation(Motion.hover, value: player.isScrubbing)
            .animation(Motion.toggle, value: player.abA)
            .animation(Motion.toggle, value: player.abB)
            .animation(Motion.panel, value: drawing)
        }
        .frame(height: 14)
        .contentShape(Rectangle())
        .contextMenu { MenuContent(nodes: MenuCatalog.progressBar(player)) }
    }

    /// 只有循环区展开时，进度条上才显示区间、能直接拖选和拖手柄；收起时进度条只管跳转
    private var drawing: Bool { player.loopEditorOpen }

    private var loopRangeColor: Color {
        let a = player.palette.accent
        let c = LoopScrub.rangeRGB(accentR: a.r, accentG: a.g, accentB: a.b)
        return Color(red: c.0, green: c.1, blue: c.2)
    }

    private var shownRange: (Double, Double)? {
        if let t = temp { return (min(t.0, t.1), max(t.0, t.1)) }
        if let a = player.abA, let b = player.abB { return (a, b) }
        return nil
    }

    private func time(_ x: CGFloat, _ w: CGFloat) -> Double? {
        guard let d = player.duration, d > 0, w > 0 else { return nil }
        return Double(min(max(0, x / w), 1)) * d
    }

    private func changed(_ v: DragGesture.Value, _ w: CGFloat) {
        guard let d = player.duration, d > 0, let t = time(v.location.x, w) else { return }
        if mode == nil {
            let t0 = time(v.startLocation.x, w) ?? t
            let grab = Double(10 / max(w, 1)) * d          // 手柄抓取范围：±10pt
            switch LoopScrub.hit(editorOpen: drawing, optionHeld: NSEvent.modifierFlags.contains(.option), t0: t0, a: player.abA, b: player.abB, duration: d, grab: grab) {
            case .handleA:
                if let a = player.abA, let b = player.abB { mode = .handleA; temp = (a, b) }
            case .handleB:
                if let a = player.abA, let b = player.abB { mode = .handleB; temp = (a, b) }
            case .select(let origin):
                mode = .select(origin); temp = (origin, origin)
            case .seek:
                mode = .seek; player.beginScrub()
            }
        }
        switch mode {
        case .seek?: player.scrub(to: t)
        case .select(let t0)?: temp = (t0, t)
        case .handleA?: if let tp = temp { temp = (min(t, tp.1 - PlayerController.minLoop), tp.1) }
        case .handleB?: if let tp = temp { temp = (tp.0, max(t, tp.0 + PlayerController.minLoop)) }
        case nil: break
        }
        if let r = shownRange, r.1 >= r.0 { player.loopPreview = r.0...r.1 }
    }

    private func ended(_ v: DragGesture.Value, _ w: CGFloat) {
        defer { mode = nil }
        switch mode {
        case .seek?: if let t = time(v.location.x, w) { player.endScrub(at: t) }
        case .select?, .handleA?, .handleB?:
            if let tp = temp, abs(tp.1 - tp.0) >= PlayerController.minLoop {
                player.setLoopRange(tp.0, tp.1)
            } else if case .select? = mode, let t = time(v.location.x, w) {
                // 单击（没拖出区间）：就当普通跳转
                player.seek(to: t)
            }
            withAnimation(Motion.toggle) { temp = nil }
            player.loopPreview = nil
        case nil: break
        }
    }

    private var progressFraction: CGFloat {
        guard let d = player.duration, d > 0 else { return 0 }
        var t = player.position
        // 区间循环刚跳回时，播放内核报告的位置会因输出缓冲短暂略早于起点：显示上夹在区间内，游标不会“抖出”区间
        if let a = player.abA, player.abB != nil, t > a - 0.8, t < a { t = a }
        else if let b = player.abB, player.abA != nil, t > b { t = b }
        return CGFloat(min(max(t / d, 0), 1))
    }
}

/// 区间条：半透明强调色 + 背景模糊透出 + 1px 亮边；两端是白色细手柄（带 1px 边），编辑时手柄稍微放大
struct LoopRangeView: View {
    var width: CGFloat
    var height: CGFloat
    var accent: Color
    var editing: Bool
    @State private var appear = false
    var body: some View {
        let r = Capsule()
        ZStack {
            r.fill(.ultraThinMaterial).opacity(0.6)
            r.fill(accent.opacity(0.32))
            r.strokeBorder(Color.white.opacity(0.75), lineWidth: 1)
            HStack(spacing: 0) {
                handle
                Spacer(minLength: 0)
                handle
            }
            .padding(.horizontal, 1)
        }
        .frame(width: width, height: height)
        .animation(Motion.press, value: editing)
    }
    private var handle: some View {
        Capsule().fill(Color.white)
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
            .frame(width: editing ? 4 : 3, height: height + (editing ? 6 : 2))
    }
}

/// 音量：图标随音量分级；悬停时向左展开一条玻璃滑杆（宽度弹簧展开）
struct VolumeControl: View {
    @Environment(PlayerController.self) private var player
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 4) {
            // 均衡器一键直达按钮（点一下打开，再点回卡片模式，不再隐藏在悬停里）
            Button {
                player.selectTab(player.tab == .equalizer ? .nowPlaying : .equalizer)
            } label: { Image(systemName: "slider.vertical.3") }
            .buttonStyle(GlassIconButtonStyle(size: 30, active: player.tab == .equalizer, accent: Color(player.palette.accent)))
            .help(player.tab == .equalizer ? "回到卡片模式（E）" : "均衡器（E）")
            if expanded {
                GlassLinearSlider(value: player.muted ? 0 : player.volume / 100, accent: Color(player.palette.accent)) { v in
                    player.setVolume(v * 100)
                }
                .frame(width: 96, height: 20)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            Button { player.setMuted(!player.muted) } label: {
                Image(systemName: player.muted || player.volume == 0 ? "speaker.slash.fill" : "speaker.wave.3.fill",
                      variableValue: player.muted ? 0 : player.volume / 100)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(GlassIconButtonStyle(size: 32))
            .help("音量（↑↓），点击静音（M）；右键选输出设备")
            .contextMenu { MenuContent(nodes: MenuCatalog.volumeArea(player)) }
        }
        .onHover { h in withAnimation(Motion.panel) { expanded = h } }
        .animation(Motion.toggle, value: player.tab == .equalizer)
    }
}

struct GlassLinearSlider: View {
    var value: Double
    var accent: Color
    /// 轨道上的淡刻度（0…1 位置）。自绘，不用系统 NSSlider 的刻度——那个在动画布局时每帧重建上百个刻度，会卡
    var ticks: [Double] = []
    var onChange: (Double) -> Void
    @State private var dragging = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.inkFill.opacity(0.16)).frame(height: dragging ? 6 : 4)
                if !ticks.isEmpty {
                    Canvas { ctx, size in
                        for t in ticks {
                            let x = min(max(1, size.width * t), size.width - 1)
                            ctx.fill(Path(CGRect(x: x - 0.5, y: size.height / 2 - 5, width: 1, height: 10)), with: .color(Color.ink.opacity(0.28)))
                        }
                    }
                    .allowsHitTesting(false)
                }
                Capsule().fill(LinearGradient(colors: [accent.opacity(0.8), Color.ink], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(4, w * value), height: dragging ? 6 : 4)
                Circle().fill(.white).frame(width: dragging ? 14 : 11, height: dragging ? 14 : 11)
                    .shadow(color: .black.opacity(0.15), radius: 1.5, y: 0.5)
                    .offset(x: w * value - (dragging ? 7 : 5.5))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in dragging = true; onChange(Double(min(max(0, v.location.x / w), 1))) }
                .onEnded { _ in dragging = false })
            .animation(Motion.press, value: dragging)
        }
    }
}

/// 视频：音轨 / 字幕 / 倍速 / 小窗
struct TrackMenu: View {
    @Environment(PlayerController.self) private var player
    var body: some View {
        Menu {
            Section("字幕") {
                Button { player.selectSubtitle(nil) } label: { check(player.subtitleTracks.allSatisfy { !$0.isSelected }, "关闭字幕") }
                ForEach(player.subtitleTracks) { t in
                    Button { player.selectSubtitle(t.id) } label: { check(t.isSelected, t.displayName) }
                }
                Button("加载字幕文件…") { player.presentSubtitlePanel() }
            }
            Section("音轨") {
                ForEach(player.audioTracks) { t in
                    Button { player.selectAudioTrack(t.id) } label: { check(t.isSelected, t.displayName) }
                }
            }
            Section("播放速度") {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { s in
                    Button { player.setSpeed(s) } label: { check(abs(player.speed - s) < 0.005, s == 1 ? "正常" : String(format: "%g×", s)) }
                }
                Button("变速变调面板…") { player.toggleSpeedPitchPanel() }
            }
            Button(player.isPinnedMini ? "退出迷你窗" : "迷你窗") { player.togglePinnedMini() }
        } label: {
            Image(systemName: "captions.bubble").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.ink.opacity(0.86))
                .frame(width: 32, height: 32).contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("字幕、音轨与倍速")
        .contextMenu { MenuContent(nodes: MenuCatalog.subtitleArea(player) + [.divider, MenuCatalog.speedMenu(player), .item("迷你窗", "pip", checked: player.isPinnedMini) { player.togglePinnedMini() }]) }
    }

    @ViewBuilder private func check(_ on: Bool, _ title: String) -> some View {
        if on { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
}
