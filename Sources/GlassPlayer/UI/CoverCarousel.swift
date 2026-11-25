// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

/// 玻璃 3D 封面轮播。位置由 PlayerController.carousel（120Hz 弹簧物理）驱动，
/// 每张卡的倾斜、缩放、景深、变暗、模糊都是“相对居中距离”的连续函数，所以拖动和动画中永远平滑同步。
struct CoverCarousel: View {
    @Environment(PlayerController.self) private var player
    @State private var drag = DragTracker()
    @State private var scroll = ScrollCatcher()
    @State private var dbl = CardDoubleClickCatcher()

    /// 旋转方向：两侧卡外沿向后退、卡面朝向中心（与参考图 01 一致；2026-11-18 真机截图核对后定为 -1）。
    static let rotationSign: Double = -1
    /// 3D 倾斜深度（TANCO 2026-11-18：卡片保留，但更扁平一点 → 侧卡转角打 7 折，透视减弱）
    static let depth: Double = 0.7

    var body: some View {
        GeometryReader { geo in
            // 整数点对齐，保证 4K / Retina 屏上专辑图与卡片背面文字像素级锐利不发虚
            let side = floor(min(geo.size.height * 0.62, geo.size.width * 0.32, 460))
            let slot = side * 0.62          // 手指移动一个卡位 = 翻一张（与 CardPose 的首段间距一致 → 1:1 跟手）
            let pos = player.carousel.position
            let lo = max(0, Int(floor(pos)) - 4)
            let hi = min(player.queue.items.count - 1, Int(ceil(pos)) + 4)
            ZStack {
                if hi >= lo {
                    ForEach(lo...hi, id: \.self) { i in
                        // 清空/删除时 SwiftUI 动画里还会再算一次旧下标：越界就不画（2026-11-18 自测发现的崩溃）
                        if i < player.queue.items.count {
                        let item = player.queue.items[i]
                        let d = Double(i) - pos
                        let pose = CardPose.pose(relative: d)
                        let isCenter = i == player.carousel.centeredIndex && abs(d) < 0.5
                        let rotY = pose.rotationY * Self.rotationSign * Self.depth
                        CoverCard(item: item, art: player.art(for: item), side: side, pose: pose,
                                  isCenter: isCenter, isCurrent: i == player.queue.currentIndex,
                                  lifted: isCenter && player.isLifted,
                                  onTap: { player.cardClicked(i) })
                            .scaleEffect(abs(pose.scale - 1) > 0.001 ? pose.scale : 1)
                            .rotation3DEffect(.degrees(rotY), axis: (x: 0, y: 1, z: 0),
                                              anchor: .center, anchorZ: 0, perspective: abs(rotY) > 0.01 ? 0.30 : 0)
                            .offset(x: pose.x * side * 1.0)
                            .opacity(pose.opacity)
                            .zIndex(pose.zIndex)
                            .contextMenu { MenuContent(nodes: MenuCatalog.card(player, index: i)) }
                            .accessibilityLabel(item.knownArtist.map { "\(item.title)，\($0)" } ?? item.title)
                            .accessibilityAddTraits(isCenter ? [.isButton, .isSelected] : .isButton)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture { player.exitLift() }          // 卡片翻着时，点空白处翻回
            .contextMenu { MenuContent(nodes: MenuCatalog.blank(player)) }
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { v in
                        if !drag.active { drag.active = true; drag.last = 0; player.carouselBeginDrag() }
                        let dx = v.translation.width - drag.last
                        drag.last = v.translation.width
                        player.carouselDrag(deltaCards: -Double(dx / slot))
                    }
                    .onEnded { _ in drag.active = false; player.carouselEndDrag() }
            )
            .background {
                GeometryReader { g in
                    Color.clear
                        .onAppear { scroll.frame = g.frame(in: .global); scroll.install(player: player, slot: slot); player.viewer.carouselFrame = g.frame(in: .global); dbl.install(player) }
                        .onChange(of: g.frame(in: .global)) { _, f in scroll.frame = f; scroll.slot = slot; player.viewer.carouselFrame = f }
                }
            }
            .onDisappear { scroll.uninstall(); dbl.uninstall() }
            .onChange(of: player.carousel.centeredIndex) { _, i in player.prefetchAround(i) }
        }
    }
}

/// 专辑卡双击：系统判定为双击的第二下「按下」时就接手（不等抬起），取消还没执行的单击翻面，直接进观赏。
/// 第一下的单击由 SwiftUI 点按交给 cardClicked 记下（哪张卡、什么时候），这里只认紧跟着的第二下。
@MainActor
final class CardDoubleClickCatcher {
    private var monitor: Any?
    func install(_ player: PlayerController) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak player] e in
            guard let player, e.clickCount == 2, e.window === player.mainWindow, player.tab == .nowPlaying,
                  !player.viewer.isOpen, !player.isPinnedMini, !player.tagEditorOpen else { return e }
            return player.cardDoubleClicked() ? nil : e
        }
    }
    func uninstall() { if let m = monitor { NSEvent.removeMonitor(m) }; monitor = nil }
}

/// 拖拽状态（引用类型，避免每次拖动都触发额外的视图刷新）
final class DragTracker { var active = false; var last: CGFloat = 0 }

/// 触控板双指横扫 / 鼠标滚轮 → 轮播。
/// 用本地事件监听（而不是给 SwiftUI 叠 NSView），保证鼠标在卡片上方也能收到滚动事件。
@MainActor
final class ScrollCatcher {
    var frame: CGRect = .zero
    var slot: CGFloat = 300
    private var monitor: Any?
    private var active = false
    private var wheelLock: CFTimeInterval = 0
    private weak var player: PlayerController?

    func install(player: PlayerController, slot: CGFloat) {
        self.player = player
        self.slot = slot
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, let player = self.player, player.tab == .nowPlaying, !player.videoStageOpen,
                  let win = e.window, let content = win.contentView else { return e }
            // NSEvent 坐标原点在左下，SwiftUI global 原点在左上
            let p = CGPoint(x: e.locationInWindow.x, y: content.bounds.height - e.locationInWindow.y)
            guard self.frame.contains(p) || self.active else { return e }

            if e.hasPreciseScrollingDeltas {
                // 触控板：自己做惯性和磁吸，忽略系统惯性事件
                if !e.momentumPhase.isEmpty { return nil }
                let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
                if e.phase.contains(.began) || (!self.active && e.phase.contains(.changed)) {
                    guard abs(dx) >= abs(dy) * 0.8 || self.active else { return e }
                    self.active = true
                    player.carouselBeginDrag()
                }
                if self.active && (e.phase.contains(.changed) || e.phase.contains(.began)) {
                    player.carouselDrag(deltaCards: -Double(dx / self.slot))
                }
                if self.active && (e.phase.contains(.ended) || e.phase.contains(.cancelled)) {
                    self.active = false
                    player.carouselEndDrag()
                }
                return self.active ? nil : e
            } else {
                // 普通鼠标滚轮：一格一张
                let now = CACurrentMediaTime()
                let d = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? -e.scrollingDeltaX : -e.scrollingDeltaY
                guard abs(d) > 0.1, now - self.wheelLock > 0.09 else { return nil }
                self.wheelLock = now
                player.carouselStep(d > 0 ? 1 : -1)
                return nil
            }
        }
    }

    func uninstall() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

// MARK: - 单张卡
struct CoverCard: View {
    let item: MediaItem
    let art: CoverArt?
    let side: CGFloat
    let pose: CardPose
    let isCenter: Bool
    let isCurrent: Bool
    let lifted: Bool
    let onTap: () -> Void

    @State private var hoverPoint: CGPoint? = nil
    @Environment(\.glassLiuli) private var liuli
    @Environment(PlayerController.self) private var player

    private var pad: CGFloat { floor(side * 0.045) }
    private var radius: CGFloat { floor(side * 0.085) }
    private var coverSide: CGFloat { side - pad * 2 }
    private var cardHeight: CGFloat { floor(side + side * 0.17) }

    var body: some View {
        let tilt = tiltAngles
        ZStack {
            face(front: true)
                .modifier(FlipFace(angle: lifted ? 180 : 0, isBack: false))
            face(front: false)
                .modifier(FlipFace(angle: lifted ? 180 : 0, isBack: true))
        }
        .frame(width: side, height: cardHeight)
        .background { if isCenter && lifted { ViewerRectProbe(key: "lifted:" + item.id, radius: radius) } }
        .modifier(ViewerHide(key: "lifted:" + item.id))
        // 景深：两侧卡变暗、远处卡轻微失焦（居中卡保持 0 模糊，确保 4K 锐利度）
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black.opacity(pose.dim)).allowsHitTesting(false))
        .blur(radius: pose.blur > 0.01 ? pose.blur : 0)
        // 倒影
        .background(alignment: .top) { reflection.offset(y: cardHeight + 8) }
        // 中心卡：悬停跟手微倾（静止时透视归 0，不触发离屏 3D 重采样，杜绝发糊）；翻面时保持原生 1.0x 清晰度，仅柔和上浮
        .rotation3DEffect(.degrees(tilt.x), axis: (x: 1, y: 0, z: 0), perspective: abs(tilt.x) > 0.01 ? 0.5 : 0)
        .rotation3DEffect(.degrees(tilt.y), axis: (x: 0, y: 1, z: 0), perspective: abs(tilt.y) > 0.01 ? 0.5 : 0)
        .offset(y: lifted ? -floor(side * 0.035) : 0)
        .overlay {
            PlayingBreathRing(
                cornerRadius: radius,
                rgb: PlayingBreathGlow.rgb(artPalette: art?.palette, appPalette: player.palette, followCover: player.theme.followsCover),
                active: isCurrent && player.isPlaying && !lifted,
                intensity: 0.75 + 0.25 * pose.lift
            )
        }
        .shadow(color: .black.opacity(0.06 + 0.12 * pose.lift + (lifted ? 0.10 : 0)), radius: 14 + 14 * pose.lift + (lifted ? 14 : 0), x: 0, y: 8 + 8 * pose.lift + (lifted ? 10 : 0))
        .animation(Motion.lift, value: lifted)
        .animation(Motion.hover, value: hoverPoint)
        .onContinuousHover { phase in
            guard isCenter else { if hoverPoint != nil { hoverPoint = nil }; return }
            switch phase {
            case .active(let p): hoverPoint = CGPoint(x: p.x / side, y: p.y / cardHeight)
            case .ended: hoverPoint = nil
            }
        }
    }

    private var tiltAngles: (x: Double, y: Double) {
        guard isCenter, let p = hoverPoint, !lifted else { return (0, 0) }
        return (x: Double(p.y - 0.5) * -4, y: Double(p.x - 0.5) * 5)
    }

    // 卡片玻璃框：封面的磨砂版 + 色调 + 反光 + 细边高光
    private var glassFrame: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return ZStack {
            if let f = art?.frosted {
                Image(decorative: f, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .frame(width: side, height: cardHeight).clipped()
                    .opacity(0.88)
                    .overlay(Color.white.opacity(0.10))
                    .id(art?.fadeID ?? "")
                    .transition(.opacity)
            } else {
                LinearGradient(colors: [Color(player.palette.secondary), Color(player.palette.primary)], startPoint: .top, endPoint: .bottom)
            }
            Color(art?.palette.glassTint ?? player.palette.glassTint, opacity: 0.12)
            LinearGradient(stops: [.init(color: .white.opacity(0.12), location: 0), .init(color: .white.opacity(0.03), location: 0.35), .init(color: .clear, location: 0.6)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.plusLighter)
            // 随卡片位置轻轻滑动的一道淡反光（保留玻璃感，强度比之前低）
            let shift = CGFloat(max(-0.6, min(0.6, -pose.x * 0.32)))
            LinearGradient(stops: [
                .init(color: .clear, location: max(0, 0.18 + shift)),
                .init(color: .white.opacity(0.08), location: max(0, min(1, 0.28 + shift))),
                .init(color: .clear, location: max(0, min(1, 0.38 + shift))),
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .blendMode(.plusLighter)
            if let p = hoverPoint, isCenter {
                RadialGradient(colors: [.white.opacity(0.14), .clear], center: UnitPoint(x: p.x, y: p.y), startRadius: 0, endRadius: side * 0.6)
                    .blendMode(.plusLighter)
            }
            GrainOverlay(opacity: 0.05)
        }
        .clipShape(shape)
    }

    @ViewBuilder private func face(front: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack(alignment: .top) {
            glassFrame
            if front {
                VStack(spacing: 0) {
                    coverImage
                        .frame(width: coverSide, height: coverSide)
                        .clipShape(RoundedRectangle(cornerRadius: radius * 0.62, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                        // 封面观赏：记下中间这张封面的位置（飞出 / 飞回的起止点），观赏时把它藏起来
                        .background { if isCenter { ViewerRectProbe(key: "card:" + item.id, radius: radius * 0.62) } }
                        .modifier(ViewerHide(key: "card:" + item.id))
                        .padding(.top, pad)
                    // 歌名与歌手在底部磨砂玻璃留白区垂直居中，不紧贴专辑封面下沿
                    VStack(spacing: 3) {
                        Text(item.title).font(.system(size: max(12.5, side * 0.042), weight: .semibold)).lineLimit(1)
                        if let a = item.knownArtist { Text(a).font(.system(size: max(10.5, side * 0.030), weight: .regular)).opacity(0.72).lineLimit(1) }
                    }
                    .foregroundStyle(.white)   // 卡片底部是封面色的磨砂，白字在任何主题下都最清楚
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .padding(.horizontal, pad * 1.2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .opacity(0.35 + 0.65 * pose.lift)
                }
                .frame(width: side, height: cardHeight)
                if isCurrent && player.isPlaying && isCenter {
                    PlayingBars(color: .white).frame(width: 16, height: 12)
                        .padding(8).background(Capsule().fill(.black.opacity(0.28)))
                        .padding(pad + 8)
                        .frame(maxWidth: .infinity, alignment: .topTrailing)
                        .transition(.scale.combined(with: .opacity))
                }
            } else {
                CardBack(item: item, side: side, pad: pad, onBackgroundTap: onTap)
                    .frame(width: side, height: cardHeight)
                    .clipShape(shape)
            }
        }
        .frame(width: side, height: cardHeight)
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { if front { onTap() } }
        .onChange(of: lifted) { _, on in if on { player.loadProperties(item.id) } }
        .animation(Motion.toggle, value: player.isPlaying)
    }

    @ViewBuilder private var coverImage: some View {
        if let img = art?.image {
            // 换来源（默认 → 联网查到的官方封面）时 id 变化 → 新旧两张交叉淡入
            ZStack {
                Image(decorative: img, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                    .id(art?.fadeID ?? "")
                    .transition(.opacity)
            }
        } else {
            // 封面还在后台生成：先显示柔和的占位渐变（不是灰色图标），生成好后淡入
            LinearGradient(colors: [Color(player.palette.tertiary), Color(player.palette.primary)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(GrainOverlay(opacity: 0.08))
        }
    }

    @ViewBuilder private var reflection: some View {
        if let img = art?.image, pose.opacity > 0.05 {
            Image(decorative: img, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                .id(art?.fadeID ?? "")
                .transition(.opacity)
                .frame(width: coverSide, height: coverSide * 0.42, alignment: .bottom)
                .clipped()
                .scaleEffect(x: 1, y: -1)
                .clipShape(RoundedRectangle(cornerRadius: radius * 0.62, style: .continuous))
                .mask(LinearGradient(colors: [.white.opacity(0.32), .clear], startPoint: .top, endPoint: .bottom))
                .opacity((0.35 + 0.65 * pose.lift) * (lifted ? 0 : 1))
                .blur(radius: 1.2)
                .allowsHitTesting(false)
        }
    }
}

/// 翻面：角度连续插值，过 90° 时切换正反面（Animatable，保证每一帧都正确）。
struct FlipFace: ViewModifier, Animatable {
    var angle: Double
    let isBack: Bool
    var animatableData: Double { get { angle } set { angle = newValue } }
    func body(content: Content) -> some View {
        let a = isBack ? angle - 180 : angle
        let visible = isBack ? angle >= 90 : angle < 90
        content
            // 翻面静止归位（a == 0）时透视归 0，恢复 2D 原生 4K/Retina 像素直出，杜绝文字与封面发糊
            .rotation3DEffect(.degrees(a), axis: (x: 0, y: 1, z: 0), perspective: abs(a) > 0.01 ? 0.45 : 0)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
    }
}

/// 卡片背面：原版通透磨砂玻璃 + 整齐两列 ID3 与技术属性 + 歌词切换 + 右下角玻璃铅笔按钮
struct CardBack: View {
    @Environment(PlayerController.self) private var player
    let item: MediaItem
    let side: CGFloat
    let pad: CGFloat
    var onBackgroundTap: () -> Void = {}
    @State private var showLyricsPane = false

    /// 顶部主标题区已显示歌名/歌手/专辑，明细区只列补充 ID3 字段与文件技术参数，杜绝重复与拥挤
    private static let extraTagKeys: [(String, String)] = [
        ("专辑艺人", "album_artist"), ("音轨", "track"), ("年份", "date"), ("流派", "genre"),
    ]

    var body: some View {
        let props = player.fileProperties[item.id]
        let hasLyrics = (player.lyrics != nil && item.id == player.current?.id && !(player.lyrics?.lines.isEmpty ?? true))
        let accent = Color(player.palette.accent)
        let tags = props?.tags ?? [:]
        let extraTags: [(String, String)] = Self.extraTagKeys.compactMap { label, key in
            let v = tags[key]
                ?? (key == "album_artist" ? tags["albumartist"] : nil)
                ?? (key == "date" ? tags["year"] : nil)
            guard let v, !v.isEmpty else { return nil }
            return (label, v)
        }
        let techRows = props?.rows ?? []
        let detailRows = extraTags + techRows
        let subLine = [item.knownArtist, item.album].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")

        ZStack(alignment: .bottomTrailing) {
            // 深色柔光衬底（11-23 无边框黑曜石风格），确保任何明暗专辑封面上白字与 ID3 信息都清晰
            Color.black.opacity(0.32)
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Button { player.exitLift() } label: {
                        Label("返回", systemImage: "chevron.backward").font(.system(size: max(11, side * 0.031), weight: .semibold))
                    }
                    .buttonStyle(GlassChipStyle(selected: false, accent: accent, fontSize: max(11, side * 0.031)))
                    .help("翻回封面（Esc）")
                    .accessibilityLabel("返回封面")
                    Spacer(minLength: 4)
                    if hasLyrics {
                        HStack(spacing: 4) {
                            Button("属性") { withAnimation(Motion.toggle) { showLyricsPane = false } }
                                .buttonStyle(GlassChipStyle(selected: !showLyricsPane, accent: accent, fontSize: 11))
                            Button("歌词") { withAnimation(Motion.toggle) { showLyricsPane = true } }
                                .buttonStyle(GlassChipStyle(selected: showLyricsPane, accent: accent, fontSize: 11))
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: max(15, side * 0.054), weight: .bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if !subLine.isEmpty {
                        Text(subLine)
                            .font(.system(size: max(11.5, side * 0.033), weight: .medium))
                            .opacity(0.78)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onBackgroundTap)

                if item.formatLine != nil || item.duration != nil {
                    HStack(spacing: 6) {
                        if let f = item.formatLine { Tag(text: f) }
                        if let d = item.duration { Tag(text: TimeFormat.clock(d)) }
                    }
                }

                Divider().overlay(Color.white.opacity(0.22))

                if hasLyrics && showLyricsPane, let l = player.lyrics {
                    LyricsView(lyrics: l, fontSize: side * 0.038)
                        .padding(.bottom, 30)
                } else if !detailRows.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(detailRows.enumerated()), id: \.offset) { _, r in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(r.0)
                                        .font(.system(size: 11, weight: .medium))
                                        .opacity(0.62)
                                        .lineLimit(1)
                                        .frame(width: 54, alignment: .leading)
                                    Text(r.1)
                                        .font(.system(size: 11.5, weight: .medium))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        .padding(.bottom, 44)
                    }
                } else {
                    Spacer()
                    Text("点击右下角铅笔可编辑 ID3 信息与封面")
                        .font(.system(size: 11.5)).opacity(0.62)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Spacer()
                }
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .padding(pad * 1.9)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            // 右下角玻璃铅笔按钮（顶层独立交互，绝不被卡片单击吞掉）
            if player.canEditTags(item) {
                Button { player.openTagEditor(item.id) } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(GlassIconButtonStyle(size: 34, prominent: true, active: true, accent: accent))
                .foregroundStyle(.white)
                .help("编辑 ID3 信息与专辑封面")
                .accessibilityLabel("编辑标签与封面")
                .padding(pad * 1.4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { player.loadProperties(item.id) }
        .onChange(of: item.id) { _, id in player.loadProperties(id) }
    }

    struct Tag: View {
        let text: String
        var body: some View {
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded)).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.16)))
        }
    }
}

/// 歌词：当前句放大高亮，其余渐隐；自动滚动带弹簧
struct LyricsView: View {
    @Environment(PlayerController.self) private var player
    let lyrics: Lyrics
    let fontSize: CGFloat
    var centered = false

    var body: some View {
        // 播放位置每帧都在变：这里只算当前是第几行，下面的歌词列表只在行号变化时才重新生成
        LyricsLines(lyrics: lyrics, fontSize: fontSize, centered: centered, idx: lyrics.index(at: player.position + 0.15),
                    seek: { [weak player] t in player?.seek(to: t) })
            .equatable()
    }
}

private struct LyricsLines: View, Equatable {
    let lyrics: Lyrics
    let fontSize: CGFloat
    let centered: Bool
    let idx: Int?
    let seek: @MainActor (Double) -> Void
    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.idx == b.idx && a.fontSize == b.fontSize && a.centered == b.centered && a.lyrics == b.lyrics
    }
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: centered ? .center : .leading, spacing: fontSize * 0.7) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { i, line in
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: fontSize * (i == idx ? 1.12 : 1), weight: i == idx ? .bold : .medium))
                            .opacity(idx == nil ? 0.8 : (i == idx ? 1 : 0.38))
                            .blur(radius: idx == nil || i == idx ? 0 : min(1.2, Double(abs(i - (idx ?? i))) * 0.25))
                            .multilineTextAlignment(centered ? .center : .leading)
                            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                            .id(i)
                            .onTapGesture { if lyrics.isSynced { seek(line.time) } }
                    }
                }
                .padding(.vertical, fontSize * 3)
                .animation(Motion.symbol, value: idx)
            }
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .white, location: 0.15), .init(color: .white, location: 0.85), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
            .onAppear { if let i = idx { proxy.scrollTo(i, anchor: .center) } }
            .onChange(of: idx) { _, i in
                guard let i else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { proxy.scrollTo(i, anchor: .center) }
            }
        }
    }
}

/// 正在播放的小跳动条
struct PlayingBars: View {
    var color: Color
    var body: some View { CABars(color: NSColor(color)).allowsHitTesting(false) }
}

/// 三根跳动条：高度 = 0.35 + 0.65·|sin(t·(3.1 + 1.3i) + 1.7i)|，
/// 预先按 120 帧/秒采样成 24 秒的关键帧循环，锁定 120Hz 交给 Core Animation 播放，主线程每帧零开销。
private struct CABars: NSViewRepresentable {
    var color: NSColor
    final class V: NSView {
        var bars: [CALayer] = []
        var color: NSColor = .white { didSet { for b in bars { b.backgroundColor = color.cgColor } } }
        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            for _ in 0..<3 { let b = CALayer(); b.anchorPoint = CGPoint(x: 0.5, y: 0); layer?.addSublayer(b); bars.append(b) }
        }
        required init?(coder: NSCoder) { fatalError() }
        override func layout() {
            super.layout()
            let scale = window?.backingScaleFactor ?? 2
            CATransaction.begin(); CATransaction.setDisableActions(true)
            let w: CGFloat = 3, gap: CGFloat = 2, total = w * 3 + gap * 2
            let x0 = (bounds.width - total) / 2
            for (i, b) in bars.enumerated() {
                b.contentsScale = scale
                b.bounds = CGRect(x: 0, y: 0, width: w, height: bounds.height)
                b.position = CGPoint(x: x0 + CGFloat(i) * (w + gap) + w / 2, y: 0)
                b.cornerRadius = w / 2
                b.backgroundColor = color.cgColor
                if b.animation(forKey: "h") == nil { b.add(Self.anim(i), forKey: "h") }
            }
            CATransaction.commit()
        }
        static func anim(_ i: Int) -> CAAnimation {
            let fps = 120.0, period = 24.0, n = Int(period * fps)
            let t0 = Date().timeIntervalSinceReferenceDate
            let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
            a.values = (0...n).map { k in
                let t = t0 + Double(k) / fps
                return 0.35 + 0.65 * abs(sin(t * (3.1 + Double(i) * 1.3) + Double(i) * 1.7))
            }
            a.calculationMode = .linear
            a.duration = period
            a.repeatCount = .infinity
            a.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
            a.isRemovedOnCompletion = false
            return a
        }
    }
    func makeNSView(context: Context) -> V { let v = V(frame: .zero); v.color = color; return v }
    func updateNSView(_ v: V, context: Context) { v.color = color }
}

// MARK: - 正在播放的同步呼吸柔光（卡片轮播 & 鉴赏模式共用同一相位、颜色与观感）

enum PlayingBreathGlow {
    /// 呼吸周期（秒）：缓慢舒缓的呼吸灯节奏，卡片与鉴赏共用同一时钟相位
    static let period: CFTimeInterval = 3.8

    static func breath(at time: CFTimeInterval = CACurrentMediaTime()) -> Double {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return 0.5 }
        return 0.5 - 0.5 * cos(time * (2.0 * .pi / period))
    }

    private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        let r = a.r + (b.r - a.r) * t
        let g = a.g + (b.g - a.g) * t
        let bl = a.b + (b.b - a.b) * t
        return RGB(r, g, bl)
    }

    /// 贴合专辑主色与整体配色：保证深色/浅色专辑边缘都能透出温润而克制的琉璃微光
    static func rgb(artPalette: AmbientPalette?, appPalette: AmbientPalette, followCover: Bool) -> RGB {
        let base: RGB
        if let ap = artPalette {
            let artTone = mix(ap.accent, ap.tertiary, 0.35)
            base = followCover ? artTone : mix(artTone, appPalette.accent, 0.48)
        } else {
            base = mix(appPalette.accent, appPalette.tertiary, 0.30)
        }
        return mix(base, RGB(1, 1, 1), 0.24)
    }

    static func rimAlpha(breath b: Double) -> Double { 0.32 + 0.44 * b }
    static func haloOpacity(breath b: Double) -> Double { 0.26 + 0.38 * b }
    static func haloRadius(breath b: Double, scale: CGFloat = 1) -> CGFloat { (14 + 14 * CGFloat(b)) * scale }
}

/// 卡片轮播里「正在播放」专辑卡的同步呼吸光圈（样式、配色、呼吸节拍与鉴赏模式右下专辑图完全同步）
struct PlayingBreathRing: View {
    let cornerRadius: CGFloat
    let rgb: RGB
    let active: Bool
    var intensity: Double = 1.0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !active)) { _ in
            let b = active ? PlayingBreathGlow.breath() : 0
            let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            let glow = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
            let rimAlpha = PlayingBreathGlow.rimAlpha(breath: b) * intensity
            let haloAlpha = PlayingBreathGlow.haloOpacity(breath: b) * intensity
            let haloRad = PlayingBreathGlow.haloRadius(breath: b)
            ZStack {
                // 外层呼吸柔光晕：柔和托出正在播放的那张卡片
                shape
                    .stroke(glow.opacity(haloAlpha), lineWidth: 3.5)
                    .blur(radius: haloRad * 0.55)
                    .shadow(color: glow.opacity(haloAlpha * 0.85), radius: haloRad * 0.85, x: 0, y: 0)
                // 内层纤细琉璃光边：与鉴赏模式封面边缘光圈完全一致
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(rimAlpha * 0.85),
                                glow.opacity(rimAlpha),
                                glow.opacity(rimAlpha * 0.65),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.4
                    )
            }
            .opacity(active ? 1 : 0)
            .animation(.easeInOut(duration: 0.45), value: active)
        }
        .allowsHitTesting(false)
    }
}
