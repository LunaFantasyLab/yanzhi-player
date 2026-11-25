// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit
import PlayerCore

/// 封面观赏模式的进出逻辑（界面在 UI/CoverViewer.swift）。TANCO 2026-11-20 拍板：不要任何手势，鼠标 + 键盘就能完整使用。
/// 进入：双击专辑卡（中间、旁边、背面都行）；右键「观赏封面」；⌘Y；双击播放栏小封面；双击迷你窗封面（先回大窗口）；播放列表行右键。
/// 退出（Esc 一层层退）：观赏里进的全屏 → 先退全屏；放大了 → 先回到适应窗口；否则退出观赏。
/// 另外：右上角 ×、单击封面或空白（无论是否放大，立即飞回原入口，不等待双击）、右键「退出观赏」、再按 ⌘Y 都直接退出。
extension PlayerController {
    /// 观赏模式开着（check-exits 登记用的状态名）
    var coverViewerOpen: Bool { viewer.isOpen }

    /// 单击翻面要等多久才确认“不是双击”：最多 0.17 秒，响应极速跟手
    static var cardClickDelay: Double { min(NSEvent.doubleClickInterval, 0.17) }

    // MARK: 专辑卡的单击 / 双击

    /// 专辑卡被单击（SwiftUI 的点按回调）：视频卡立即进视频舞台；专辑卡先等一下，确认不是双击再翻面 / 换歌
    func cardClicked(_ i: Int) {
        guard queue.items.indices.contains(i) else { return }
        let now = CACurrentMediaTime()
        TestHooks.log(String(format: "  卡片单击 #%d（%@）%@", i, queue.items[i].kind == .video ? "视频" : "专辑", now < suppressCardTapUntil ? "：双击余波，忽略" : ""))
        if now < suppressCardTapUntil { return }                 // 双击的第二下、或刚进视频舞台的余波
        if queue.items[i].kind == .audio, now - cardDoubleDownAt < 0.3 {
            // 第一下的点按比第二下的按下来得晚（系统很忙时会这样）：同样按双击处理
            cardDoubleDownAt = 0
            doubleOpen(i); return
        }
        if queue.items[i].kind == .video {
            suppressCardTapUntil = now + NSEvent.doubleClickInterval
            withAnimation(Motion.lift) { carouselTap(i) }
            return
        }
        pendingCardWork?.cancel()
        pendingCardClick = (i, now)
        pendingCardWork = after(Self.cardClickDelay) { [weak self] in
            guard let self, let pc = self.pendingCardClick, pc.index == i else { return }
            self.pendingCardClick = nil
            self.lastCardClickDelay = CACurrentMediaTime() - pc.time
            withAnimation(Motion.lift) { self.carouselTap(i) }
        }
    }

    /// 系统认定的双击（第二下按下时）：取消还没执行的单击，直接观赏，中间不会先翻一下
    /// 返回 true 表示处理了（这一下按下不再往下传）
    func cardDoubleClicked() -> Bool {
        guard let pc = pendingCardClick, CACurrentMediaTime() - pc.time < NSEvent.doubleClickInterval + 0.1,
              queue.items.indices.contains(pc.index), queue.items[pc.index].kind == .audio else {
            cardDoubleDownAt = CACurrentMediaTime()
            return false
        }
        doubleOpen(pc.index)
        return true
    }

    private func doubleOpen(_ i: Int) {
        pendingCardWork?.cancel(); pendingCardWork = nil
        pendingCardClick = nil
        suppressCardTapUntil = CACurrentMediaTime() + 0.35
        if i == carousel.centeredIndex {
            openCoverViewer(from: isLifted ? .lifted : .carousel, index: i)
        } else {
            // 旁边的卡：先记下它现在的位置（从这里飞出），再切过来播放（轮播在观赏背后转过去）
            let from = carouselCoverRect(index: i)
            openCoverViewer(from: .carousel, index: i, fromRect: from)
            isLifted = false
            carousel.jump(to: i); runCarousel()
            play(index: i)
        }
    }

    /// 轮播里第 i 张卡封面在窗口里的位置：中间那张用实测位置，旁边的按轮播的摆放公式算
    func carouselCoverRect(index i: Int) -> (rect: CGRect, radius: CGFloat)? {
        guard queue.items.indices.contains(i) else { return nil }
        let id = queue.items[i].id
        if i == carousel.centeredIndex, let r = viewer.rects["card:" + id] { return r }
        let f = viewer.carouselFrame
        guard f.width > 10 else { return nil }
        let side = min(f.height * 0.60, f.width * 0.30, 440)
        let pose = CardPose.pose(relative: Double(i) - carousel.position)
        let s = CGFloat(pose.scale)
        let pad = side * 0.045, cardH = side * 1.17, cover = side - pad * 2
        let cx = f.midX + CGFloat(pose.x) * side
        let top = f.midY - cardH * s / 2 + pad * s
        return (CGRect(x: cx - cover * s / 2, y: top, width: cover * s, height: cover * s), side * 0.085 * 0.62 * s)
    }

    // MARK: 打开 / 关闭

    func toggleCoverViewer() {
        if viewer.isOpen { closeCoverViewer(); return }
        let src: ViewerSource = isPinnedMini ? .mini : (tab == .nowPlaying && !videoStageOpen ? (isLifted ? .lifted : .carousel) : .playbar)
        openCoverViewer(from: src)
    }

    /// 打开观赏。index 为空时：轮播入口看中间那张，其余看当前曲目
    func openCoverViewer(from src: ViewerSource, index: Int? = nil, fromRect: (rect: CGRect, radius: CGFloat)? = nil, enterFullScreen: Bool = false) {
        // opening 卡住（打开飞行中途被关掉之类）超过 1.5 秒就不再算数，免得以后再也打不开
        if viewer.opening, CACurrentMediaTime() - viewer.openingSince > 1.5 { viewer.opening = false }
        guard !viewer.isOpen, !viewer.opening, let v = viewer.view else {
            TestHooks.log("  观赏封面：没打开（已开着=\(viewer.isOpen) 正在打开=\(viewer.opening)）"); return
        }
        let idx = index ?? ((src == .carousel || src == .lifted) ? carousel.centeredIndex : queue.currentIndex)
        guard let idx, queue.items.indices.contains(idx) else { return }
        let item = queue.items[idx]
        guard item.kind == .audio else { showHUD("film", "视频没有专辑封面"); return }
        guard let art = art(for: item) else { showHUD("photo", "封面还在加载，稍等一下"); return }
        pendingCardWork?.cancel(); pendingCardClick = nil
        if src == .mini {
            // 迷你窗太小，看不了大图：先回到大窗口，退出观赏后再回到迷你窗
            viewer.restoreMini = true
            viewer.opening = true
            if isPinnedMini { togglePinnedMini() }
            after(0.5) { [weak self] in
                guard let self else { return }
                self.viewer.opening = false
                self.beginViewer(item: item, art: art, src: .mini, from: nil, hideKey: nil, view: v, enterFullScreen: enterFullScreen)
            }
            return
        }
        var from = fromRect
        var key: String?
        switch src {
        case .carousel:
            key = "card:" + item.id
            if from == nil { from = carouselCoverRect(index: idx) }
        case .lifted:
            key = "lifted:" + item.id
            from = viewer.rects[key!]
        case .playbar: key = "playbar"; from = viewer.rects["playbar"]
        case .playlist: key = "row:" + item.id; from = viewer.rects[key!]
        case .mini: break
        }
        beginViewer(item: item, art: art, src: src, from: from, hideKey: from == nil ? nil : key, view: v, enterFullScreen: enterFullScreen)
    }

    private func beginViewer(item: MediaItem, art: CoverArt, src: ViewerSource, from: (rect: CGRect, radius: CGFloat)?, hideKey: String?, view v: CoverViewerView, enterFullScreen: Bool = false) {
        if activeCard != nil { closeCard() }
        if showShortcuts { toggleShortcutsHelp() }
        viewer.source = src
        viewer.itemID = item.id
        viewer.closing = false
        viewer.opening = true
        viewer.openingSince = CACurrentMediaTime()
        viewer.fullscreenByViewer = enterFullScreen || (mainWindow?.styleMask.contains(.fullScreen) ?? false)
        viewer.setOpen(true)
        v.open(image: art.image, backdrop: art.backdrop, fromGlobal: from?.rect, radius: from?.radius ?? 16, isDefaultCover: art.style != nil)
        viewer.hide(hideKey)
        loadFullCover(item: item, art: art)
        TestHooks.log("  观赏封面：打开（入口 \(src.rawValue)，「\(item.title)」\(art.image.width)×\(art.image.height)）")
    }

    /// 后台读原图（文件自带 → 原始字节；联网 → 缓存里的原图；默认封面 → 按大尺寸重画），读好后无缝换上
    func loadFullCover(item: MediaItem, art: CoverArt) {
        let id = item.id
        let it = details[id]?.item ?? item
        let origin = art.origin
        let style = art.style
        let q = coverQuery(it)
        Task { [weak self] in
            var data: Data?
            var img: CGImage?
            switch origin {
            case "online":
                if case .found(let d, _, _) = await CoverService.lookupShared(q) { data = d }
            case "generated":
                img = await Task.detached(priority: .userInitiated) {
                    CoverStore.defaultCover(spec: DefaultCoverSpec.make(seed: it.coverSeed), style: style ?? .softGlass,
                                            title: it.album?.isEmpty == false ? it.album! : it.title, artist: it.displayArtist, size: CoverStore.maxSide)
                }.value
            default:
                data = await Task.detached(priority: .userInitiated) { await FullCover.fileCoverData(it.url) }.value
            }
            if img == nil, let data { img = await Task.detached(priority: .userInitiated) { FullCover.decodeFull(data) }.value }
            guard let self, let img, self.viewer.isOpen, !self.viewer.closing, self.viewer.itemID == id else { return }
            guard img.width >= art.image.width else { return }
            self.viewer.view?.upgrade(to: img)
            TestHooks.log("  观赏封面：换上原图 \(img.width)×\(img.height)（卡片用的是 \(art.image.width)×\(art.image.height)）")
        }
    }

    func closeCoverViewer() {
        guard viewer.isOpen, !viewer.closing, let v = viewer.view else { return }
        if viewer.fullscreenByViewer, let w = mainWindow, w.styleMask.contains(.fullScreen) {
            // 观赏里进的全屏：先退全屏，窗口落定后再飞回
            viewer.fullscreenByViewer = false
            viewer.closing = true
            w.toggleFullScreen(nil)
            after(0.9) { [weak self] in self?.viewer.closing = false; self?.closeCoverViewer() }
            return
        }
        viewer.fullscreenByViewer = false
        viewer.closing = true
        viewer.opening = false             // 打开飞行中途就关：不能让“正在打开”一直挂着
        viewer.stopChromeTimer()
        withAnimation(.easeInOut(duration: 0.2)) { viewer.chromeVisible = false }
        let src = viewer.source
        let shownID = viewer.itemID ?? ""
        var target: (rect: CGRect, radius: CGFloat)?
        var key: String?
        switch src {
        case .carousel, .lifted:
            // 飞回轮播里正在看的那张（期间切了歌，轮播已经转到新歌，就飞回新歌那张）
            if tab == .nowPlaying && !videoStageOpen, let i = queue.items.firstIndex(where: { $0.id == shownID }) {
                if isLifted && i == carousel.centeredIndex, let r = viewer.rects["lifted:" + shownID] { target = r; key = "lifted:" + shownID }
                else { target = carouselCoverRect(index: i); key = "card:" + shownID }
            }
        case .playbar: if queue.current?.id == shownID { target = viewer.rects["playbar"]; key = "playbar" }
        case .playlist: target = viewer.rects["row:" + shownID]; key = "row:" + shownID
        case .mini: target = nil
        }
        viewer.hide(target == nil ? nil : key)
        v.close(toGlobal: target?.rect, radius: target?.radius ?? 16) { [weak self] in
            guard let self else { return }
            self.viewer.setOpen(false)
            self.viewer.hide(nil)
            self.viewer.closing = false
            self.viewer.chromeVisible = true
            self.mainWindow?.makeFirstResponder(nil)
            TestHooks.log("  观赏封面：已退出（回到 \(src.rawValue)）")
            if self.viewer.restoreMini { self.viewer.restoreMini = false; if !self.isPinnedMini { self.togglePinnedMini() } }
        }
    }

    /// Esc：缩放先归位；全屏鉴赏一键同步退出全屏并回到窗口卡片模式
    func viewerEscape() {
        guard let v = viewer.view else { return }
        TestHooks.log("  观赏 Esc：closing=\(viewer.closing) opening=\(viewer.opening) 观赏全屏=\(viewer.fullscreenByViewer) 全屏=\(mainWindow?.styleMask.contains(.fullScreen) ?? false) 放大=\(v.isZoomed)")
        if viewer.closing || viewer.opening { return }
        if v.isZoomed { v.zoomToFit(); return }
        if let w = mainWindow, w.styleMask.contains(.fullScreen) {
            viewer.fullscreenByViewer = true
        }
        closeCoverViewer()
    }

    /// 观赏里按 F / 右键：全屏与鉴赏统一（退出全屏时同步回到窗口卡片模式）
    func viewerToggleFullScreen() {
        guard viewer.isOpen, !viewer.closing, let w = mainWindow else { return }
        let full = w.styleMask.contains(.fullScreen)
        if full {
            viewer.fullscreenByViewer = true
            closeCoverViewer()
        } else {
            viewer.fullscreenByViewer = true
            w.toggleFullScreen(nil)
        }
    }

    /// 观赏中切歌：封面跟着换（交叉淡入）；切到视频就退出观赏（视频没有专辑封面）
    func viewerTrackChanged() {
        guard viewer.isOpen, !viewer.closing, let cur = queue.current else { return }
        guard cur.kind == .audio else { closeCoverViewer(); return }
        guard cur.id != viewer.itemID else { return }
        viewer.itemID = cur.id
        ensureDetails(cur)
        func swap(_ art: CoverArt) {
            viewer.view?.crossfade(to: art.image, backdrop: art.backdrop, isDefaultCover: art.style != nil)
            loadFullCover(item: cur, art: art)
            TestHooks.log("  观赏封面：切歌 → 「\(cur.title)」，封面交叉淡入")
        }
        if let art = art(for: cur) { swap(art); return }
        Task { [weak self] in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, self.viewer.isOpen, self.viewer.itemID == cur.id else { return }
                if let art = self.art(for: cur) { swap(art); return }
            }
        }
    }

    /// 观赏模式里的按键。返回 true 表示已处理（不再往下传）
    func viewerHandleKey(_ e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection([.command, .option, .control, .shift])
        let ch = e.charactersIgnoringModifiers?.lowercased() ?? ""
        if e.keyCode != 53 { TestHooks.log("  观赏按键 code=\(e.keyCode) 「\(ch)」mods=\(mods.rawValue)") }
        if e.keyCode == 53 { viewerEscape(); return true }                   // Esc
        if mods == [.option] {                                              // ⌥ + 方向键：放大后平移（方向键本身仍是快进快退、音量）
            switch e.keyCode {
            case 123: viewer.view?.panByKey(dx: -1, dy: 0); return true
            case 124: viewer.view?.panByKey(dx: 1, dy: 0); return true
            case 126: viewer.view?.panByKey(dx: 0, dy: -1); return true
            case 125: viewer.view?.panByKey(dx: 0, dy: 1); return true
            default: break
            }
        }
        if [49, 123, 124, 125, 126].contains(e.keyCode) { return false }     // 空格、方向键：照常
        if mods == [.command] {
            switch ch {
            case "=", "+": viewer.view?.zoomStep(1); return true
            case "-": viewer.view?.zoomStep(-1); return true
            case "0": viewer.view?.zoomToFit(); return true
            case "y": closeCoverViewer(); return true
            default: return false                                               // 其他 ⌘ 快捷键（上一首 / 下一首…）照常
            }
        }
        if mods == [.command, .shift], ch == "=" || ch == "+" { viewer.view?.zoomStep(1); return true }
        if mods.isEmpty {
            switch ch {
            case "f": viewerToggleFullScreen(); return true
            case "m": return false
            default: return true                                                // 其他单键在观赏里不起作用，免得在看不见的地方改了状态
            }
        }
        return false
    }
}
