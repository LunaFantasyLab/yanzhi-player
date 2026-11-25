// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import PlayerCore

/// 全部菜单的内容（2026-11-24 极简精炼版）：
/// 去掉多余、重复、低频或系统不支持的项（如「画中画」「关于画中画」「声道」「音视频延迟」「缩放微调」「套娃更多」），
/// 只保留日常听歌观影真正需要的功能，菜单栏与各处右键保持简洁一致。
@MainActor
enum MenuCatalog {
    typealias N = MenuNode
    private static let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private static func speedTitle(_ s: Double) -> String { s == 1 ? "正常（1×）" : String(format: "%g×", s) }

    // MARK: 菜单栏
    static func file(_ p: PlayerController) -> [N] {
        [
            .item("打开文件…", "doc", key: "o", panel: true) { p.presentOpenPanel(folders: false) },
            .item("打开文件夹…", "folder", key: "o", mods: [.command, .shift], panel: true) { p.presentOpenPanel(folders: true) },
            .item("打开网址…", "globe", key: "u", panel: true) { p.openURLPrompt() },
            recentMenu(p),
            .divider,
            .item("添加歌曲…", "plus", key: "o", mods: [.command, .option], panel: true) { p.addSongs(folders: false) },
            .item("添加文件夹…", "folder.badge.plus", key: "o", mods: [.command, .option, .shift], panel: true) { p.addSongs(folders: true) },
            .divider,
            .item("保存播放列表…", "square.and.arrow.down", key: "s", enabled: !p.queue.items.isEmpty, panel: true) { p.savePlaylistPanel() },
            .item("载入播放列表…", "music.note.list", key: "l", mods: [.command, .shift], panel: true) { p.loadPlaylistPanel() },
        ]
    }

    static func recentMenu(_ p: PlayerController) -> N {
        var c: [N] = p.recent.map { u in
            .item(u.isFileURL ? u.lastPathComponent : (u.host ?? "") + u.path, u.isFileURL ? (MediaFormats.kind(forExtension: u.pathExtension) == .video ? "film" : (u.hasDirectoryPath || u.pathExtension.isEmpty ? "folder" : "music.note")) : "globe") { p.openRecent(u) }
        }
        if c.isEmpty { c = [.header("暂无记录")] }
        c += [.divider, .item("清除最近打开", "clock.arrow.circlepath", enabled: !p.recent.isEmpty) { p.clearRecent() }]
        return MenuNode(title: "最近打开", symbol: "clock", kind: .submenu(c))
    }

    static func edit(_ p: PlayerController) -> [N] {
        [
            .item("编辑标签与封面…", "pencil", enabled: p.current.map { p.canEditTags($0) } ?? false) { if let id = p.current?.id { p.openTagEditor(id) } },
            .item("拷贝曲目信息", "doc.on.doc", key: "c", mods: [.command, .shift], enabled: p.current != nil) { p.copyInfo(nil) },
            .item("在访达中显示", "folder", key: "r", mods: [.command, .shift], enabled: p.current?.url.isFileURL == true) { p.revealCurrent() },
        ]
    }

    static func playback(_ p: PlayerController) -> [N] {
        let has = p.hasMedia
        return [
            .item(p.isPlaying ? "暂停" : "播放", p.isPlaying ? "pause.fill" : "play.fill", key: .space, mods: [], enabled: !p.queue.items.isEmpty) { p.togglePlay() },
            .item("上一首", "backward.fill", key: .leftArrow, enabled: !p.queue.items.isEmpty) { p.previous() },
            .item("下一首", "forward.fill", key: .rightArrow, enabled: !p.queue.items.isEmpty) { p.next() },
            .divider,
            .item("快退 15 秒", "gobackward.15", key: .leftArrow, mods: [], enabled: has) { p.seek(by: -PlayerController.seekStep) },
            .item("快进 15 秒", "goforward.15", key: .rightArrow, mods: [], enabled: has) { p.seek(by: PlayerController.seekStep) },
            .divider,
            speedMenu(p),
            repeatMenu(p),
            loopMenu(p, shortcuts: true),
        ]
    }

    /// 区间循环（A-B）：精简直给，微调直接在循环卡片拖动
    static func loopMenu(_ p: PlayerController, shortcuts: Bool = false) -> N {
        let has = p.hasMedia && p.duration != nil
        let k = shortcuts
        let head: [N] = [
            .item("把当前位置设为起点", "a.circle", key: k ? "[" : nil, mods: [.command, .option], enabled: has) { p.setLoopStart() },
            .item("把当前位置设为终点并开始循环", "b.circle", key: k ? "]" : nil, mods: [.command, .option], enabled: has) { p.setLoopEnd() },
            .item("取消区间循环", "xmark.circle", enabled: p.abA != nil) { p.clearABLoop() },
        ]
        var body: [N] = [
            .divider,
            .item(p.analyzingSections ? "正在找副歌…" : "找副歌并循环", "music.note.list", key: k ? "g" : nil, mods: [.command, .option], enabled: has && !p.analyzingSections && p.current?.url.isFileURL == true) { p.findChorusAndLoop() },
        ]
        if !p.sections.isEmpty {
            body.append(.menu("循环某一段", "rectangle.split.3x1", enabled: has,
                              p.sections.enumerated().map { (i, s) -> N in
                                  .item("\(s.label)　\(TimeFormat.clock(s.start))–\(TimeFormat.clock(s.end))",
                                        checked: p.abA.map { abs($0 - s.start) < 0.05 } ?? false) { p.loopSection(i) }
                              }))
        }
        body += [
            .divider,
            .item(p.menuCard == .loop ? "收起循环区" : "展开循环区…", "character.cursor.ibeam", key: k ? "l" : nil, mods: [.command, .option], enabled: has) { p.toggleLoopEditor() },
            .item("无缝接缝", "waveform.path", checked: p.loopSeamAlign) { p.toggleLoopSeamAlign() },
        ]
        return .menu("区间循环（A-B）", "repeat.circle", head + body)
    }

    static func onlineCoverItem(_ p: PlayerController) -> N {
        .item("自动补封面（联网查官方封面）", "photo.on.rectangle", checked: p.onlineCoversEnabled) { p.toggleOnlineCovers() }
    }

    static func lyricsItem(_ p: PlayerController) -> N {
        .item("自动搜索歌词（LRCLIB）", "quote.bubble", checked: p.lyricsEnabled) { p.toggleLyrics() }
    }

    static func speedMenu(_ p: PlayerController) -> N {
        .menu("变速与变调", "speedometer", [
            .header("速度 \(SpeedPitch.speedText(p.speed)) · 音调 \(SpeedPitch.pitchText(semitones: p.pitchSemitones, cents: p.pitchCents))"),
            .menu("常用速度", "list.bullet", speeds.map { s -> N in .item(speedTitle(s), key: s == 1 ? "\\" : nil, mods: [], checked: abs(p.speed - s) < 0.005) { p.setSpeed(s) } }),
            .item("升高 1 半音", "arrow.up", key: "=", mods: [.option]) { p.pitchStep(semitones: 1) },
            .item("降低 1 半音", "arrow.down", key: "-", mods: [.option]) { p.pitchStep(semitones: -1) },
            .divider,
            .item("恢复正常速度与原调", "arrow.counterclockwise", key: "\\", mods: [.option], enabled: p.speed != 1 || p.pitchSemitones != 0 || p.pitchCents != 0) { p.resetSpeedPitch() },
            .item(p.menuCard == .speedPitch ? "收起变速变调面板" : "打开变速变调面板…", "slider.horizontal.3", key: "k", mods: [.option, .command]) { p.toggleSpeedPitchPanel() },
        ])
    }

    static func repeatMenu(_ p: PlayerController) -> N {
        .menu("循环与随机", "repeat", [
            .item("不循环", checked: p.queue.repeatMode == .off) { p.setRepeat(.off) },
            .item("列表循环", checked: p.queue.repeatMode == .all) { p.setRepeat(.all) },
            .item("单曲循环", checked: p.queue.repeatMode == .one) { p.setRepeat(.one) },
            .divider,
            .item("随机播放", "shuffle", key: "s", mods: [.command, .option], checked: p.queue.shuffle) { p.toggleShuffle() },
        ])
    }

    static func audio(_ p: PlayerController) -> [N] {
        [
            .item("静音", "speaker.slash", key: "m", mods: [], checked: p.muted) { p.toggleMute() },
            outputMenu(p),
            audioTrackMenu(p),
            .divider,
            .item("均衡器", "slider.vertical.3", key: "e", mods: [.command, .option], checked: p.eq.enabled) { p.toggleEQ() },
            presetMenu(p),
            .menu("均衡器段数", "slider.horizontal.3", EQBandCount.allCases.map { c in .item("\(c.rawValue) 段", checked: p.eq.bandCount == c) { p.setBandCountFromMenu(c) } }),
            autoEqMenu(p),
        ]
    }

    static func presetMenu(_ p: PlayerController) -> N {
        .menu("均衡器预设", "dial.medium", p.allPresets.map { pr in .item(pr.name, checked: p.eq.presetID == pr.id) { p.applyPresetFromMenu(pr) } })
    }

    static func audioTrackMenu(_ p: PlayerController) -> N {
        let t = p.audioTracks
        return .menu("音轨", "waveform", enabled: !t.isEmpty, t.map { tr in .item(tr.displayName, checked: tr.isSelected) { p.selectAudioTrackFromMenu(tr) } })
    }

    static func outputMenu(_ p: PlayerController) -> N {
        let cur = p.currentAudioDevice
        return .menu("输出设备", "hifispeaker", p.audioDevices().map { d in .item(d.name, checked: d.id == cur) { p.selectAudioDevice(d) } })
    }

    static func isFullScreen(_ p: PlayerController) -> Bool {
        p.mainWindow?.styleMask.contains(.fullScreen) ?? p.windowFullScreen
    }

    static func video(_ p: PlayerController) -> [N] {
        let v = p.isVideo && p.hasMedia
        let full = isFullScreen(p)
        return [
            .item(full ? "退出全屏" : "全屏", full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", key: "f", mods: []) { p.toggleFullScreen() },
            .item("迷你窗", "pip", key: "m", mods: [.command, .shift], checked: p.isPinnedMini) { p.togglePinnedMini() },
            .divider,
            .menu("画面比例", "aspectratio", enabled: v, PlayerController.aspectChoices.map { a in .item(a.1, checked: p.aspectOverride == a.0) { p.setAspect(a.0) } }),
            .menu("旋转", "rotate.right", enabled: v, [
                .item("顺时针旋转 90°", "rotate.right", key: "r", mods: [.command, .option]) { p.setRotation(p.videoRotate + 90) },
                .item("逆时针旋转 90°", "rotate.left") { p.setRotation(p.videoRotate - 90) },
                .divider,
                .item("不旋转", checked: p.videoRotate == 0) { p.setRotation(0) },
            ]),
            .item("截图", "camera", key: "c", mods: [.command, .option], enabled: v) { p.screenshot() },
            .divider,
            subtitleMenu(p),
            .item("加载外挂字幕…", "doc.badge.plus", key: "u", mods: [.command, .shift], enabled: v, panel: true) { p.presentSubtitlePanel() },
            subtitleToolsMenu(p),
        ]
    }

    /// 本地语音识别 + 在线字幕
    static func subtitleToolsMenu(_ p: PlayerController) -> N {
        let has = p.hasMedia && p.current?.url.isFileURL == true
        let what = p.isVideo ? "字幕" : "歌词"
        return .menu("自动\(what)与在线字幕", "captions.bubble.fill", enabled: p.hasMedia, [
            .item(p.asrProgress == nil ? "本地识别生成\(what)" : "正在识别… \(Int((p.asrProgress ?? 0) * 100))%", "waveform.badge.mic",
                  enabled: has && p.asrAvailable && p.asrProgress == nil) { p.generateSubtitles(language: .auto) },
            .item("取消识别", "xmark.circle", enabled: p.asrProgress != nil) { p.cancelASR() },
            .divider,
            .item(p.menuCard == .subtitle ? "收起在线字幕" : "在线搜索字幕…", "magnifyingglass", enabled: p.hasMedia) { p.toggleSubtitlePanel() },
        ])
    }

    /// AutoEq 耳机校正
    static func autoEqMenu(_ p: PlayerController) -> N {
        .menu("耳机校正（AutoEq）", "headphones", [
            .item(p.menuCard == .autoEq ? "收起耳机校正" : "选择耳机…", "magnifyingglass") { p.toggleAutoEqPanel() },
            .item(p.autoEqEntry.map { "校正：\($0.name)" } ?? "校正（未选耳机）", "headphones", checked: p.autoEqEnabled, enabled: p.autoEqCurve != nil) { p.setAutoEqEnabled(!p.autoEqEnabled) },
            .menu("强度", "dial.low", enabled: p.autoEqCurve != nil, [0.25, 0.5, 0.75, 1.0].map { v -> N in .item("\(Int(v * 100))%", checked: abs(p.autoEqStrength - v) < 0.01) { p.setAutoEqStrength(v) } }),
            .menu("最近用过", "clock", enabled: !p.autoEqRecent.isEmpty, p.autoEqRecent.map { e -> N in .item("\(e.name)（\(e.displaySource)）", checked: p.autoEqEntry == e) { p.selectAutoEq(e) } }),
        ])
    }

    static func subtitleMenu(_ p: PlayerController) -> N {
        let subs = p.subtitleTracks
        return .menu("字幕", "captions.bubble", enabled: p.isVideo,
                     [.item("关闭字幕", checked: !subs.contains(where: \.isSelected)) { p.selectSubtitleFromMenu(nil) }] +
                     subs.map { t in .item(t.displayName, checked: t.isSelected) { p.selectSubtitleFromMenu(t) } })
    }

    static func playlist(_ p: PlayerController) -> [N] {
        let empty = p.queue.items.isEmpty
        return [
            .item("播放记录", "clock.arrow.circlepath", checked: p.showPlayHistory) { p.togglePlayHistory() },
            .item("清空播放记录…", "trash", enabled: !p.playHistory.items.isEmpty, destructive: true) { p.promptClearPlayHistory() },
            .divider,
            .item("定位当前曲目", "scope", key: "l", enabled: p.current != nil) { p.locateCurrent() },
            sortMenu(p),
            .divider,
            .item("移除当前曲目", "minus.circle", key: .delete, enabled: p.current != nil) { p.removeCurrent() },
            .item("清空播放列表", "trash", key: .delete, mods: [.command, .shift], enabled: !empty, destructive: true) { p.clearQueueFromMenu() },
        ]
    }

    static func sortMenu(_ p: PlayerController) -> N {
        .menu("排序", "arrow.up.arrow.down", enabled: p.queue.items.count > 1,
              PlayerController.SortKey.allCases.map { k in .item(k.title) { p.sortQueue(k) } })
    }

    static func view(_ p: PlayerController) -> [N] {
        [
            .item("正在播放", "play.circle", key: "1", checked: p.tab == .nowPlaying) { p.selectTab(.nowPlaying) },
            .item("播放列表", "list.bullet", key: "2", checked: p.tab == .playlist) { p.selectTab(.playlist) },
            .item("均衡器", "slider.vertical.3", key: "3", checked: p.tab == .equalizer) { p.selectTab(.equalizer) },
            .divider,
            .item("观赏封面", "photo.artframe", key: "y", enabled: p.current?.kind == .audio) { p.toggleCoverViewer() },
            lyricsItem(p),
            onlineCoverItem(p),
            themeMenu(p),
        ]
    }

    static func themeMenu(_ p: PlayerController) -> N {
        .menu("配色主题", "paintpalette", p.themeOrder.map { t in .item(t.name, checked: p.theme == t) { p.setTheme(t); p.showHUD("paintpalette", t.name) } })
    }

    static func window(_ p: PlayerController) -> [N] {
        [
            .item("迷你窗（置顶小窗）", "pip", key: "m", mods: [.command, .shift], checked: p.isPinnedMini) { p.togglePinnedMini() },
            .item("窗口置顶", "pin", key: "t", mods: [.command, .option], checked: p.isFloating) { p.toggleFloating() },
        ]
    }

    static func help(_ p: PlayerController) -> [N] {
        [
            .item("键盘快捷键", "keyboard", key: "/") { p.toggleShortcutsHelp() },
            .item("支持的格式", "doc.text.magnifyingglass") { p.showHUD("music.note", "FLAC · ALAC · APE · DSD · WAV · MP3 · AAC · OPUS\nMKV · MP4 · MOV · WEBM · AVI · TS") },
        ]
    }

    // MARK: 右键菜单（极简高效）

    static func addItems(_ p: PlayerController) -> [N] {
        [.item("添加歌曲…", "plus", panel: true) { p.addSongs(folders: false) },
         .item("添加文件夹…", "folder.badge.plus", panel: true) { p.addSongs(folders: true) },
         .divider]
    }

    static func coverItems(_ p: PlayerController, index i: Int) -> [N] {
        guard p.queue.items.indices.contains(i) else { return [] }
        let id = p.queue.items[i].id
        let audio = p.queue.items[i].kind == .audio
        let file = p.hasFileCover(id)
        let online = p.coverInfo[id] != nil
        return [
            .header("专辑封面 · " + p.coverSourceText(id).replacingOccurrences(of: "当前：", with: "")),
            .item(online ? "重新查找封面" : "联网查找封面", online ? "arrow.clockwise" : "magnifyingglass", enabled: audio && !file) { p.refetchCover(index: i) },
            .item("改用默认封面", "square.dashed", enabled: audio && !file && online) { p.useDefaultCover(index: i) },
            .item("换一张生成封面", "dice", enabled: p.isGeneratedCover(index: i)) { p.rerollCover(index: i) },
            onlineCoverItem(p),
        ]
    }
    static func coverMenu(_ p: PlayerController, index i: Int) -> N { .menu("封面", "photo", coverItems(p, index: i)) }

    /// 专辑卡片右键：直给常用，不塞冗余套娃菜单
    static func card(_ p: PlayerController, index i: Int) -> [N] {
        guard p.queue.items.indices.contains(i) else { return [] }
        let item = p.queue.items[i]
        let isCur = i == p.queue.currentIndex
        return addItems(p) + [
            .item(isCur && p.isPlaying ? "暂停" : "播放", isCur && p.isPlaying ? "pause.fill" : "play.fill") { if isCur { p.togglePlay() } else { p.play(index: i) } },
            .item("下一首播放", "text.line.first.and.arrowtriangle.forward", enabled: !isCur && p.queue.currentIndex != nil) { p.playNext(index: i) },
            .item(isCur && p.isLifted ? "翻回封面" : "显示属性与歌词", isCur && p.isLifted ? "chevron.backward" : "info.circle") {
                if isCur && p.isLifted { p.exitLift() } else { p.showInfo(index: i) }
            },
        ] + (item.kind == .audio ? [.item("观赏封面", "photo.artframe") { p.openCoverViewer(from: p.isLifted && i == p.carousel.centeredIndex ? .lifted : .carousel, index: i) }] : [])
          + (p.isGeneratedCover(index: i) ? [.item("随机重新生成封面", "dice") { p.rerollCover(index: i) }] : []) + [
            .item("编辑标签与封面…", "pencil", enabled: p.canEditTags(item)) { p.openTagEditor(item.id) },
            .divider,
            addToPlaylistMenu(p, [item]),
            coverMenu(p, index: i),
            .item("在访达中显示", "folder", enabled: item.url.isFileURL) { p.revealInFinder(item) },
            .divider,
            .item("从播放列表移除", "minus.circle", destructive: true) { withAnimation(Motion.panel) { p.remove(at: i) }; p.showHUD("minus.circle", "已移除") },
        ]
    }

    static func playlistRow(_ p: PlayerController, index i: Int) -> [N] {
        guard p.queue.items.indices.contains(i) else { return [] }
        let item = p.queue.items[i]
        let n = p.queue.items.count
        return addItems(p) + [
            .item("播放", "play.fill") { p.play(index: i) },
            .item("下一首播放", "text.line.first.and.arrowtriangle.forward", enabled: i != p.queue.currentIndex && p.queue.currentIndex != nil) { p.playNext(index: i) },
            .item("属性", "info.square") { p.toggleProperties(item.id) },
            .item("编辑标签与封面…", "pencil", enabled: p.canEditTags(item)) { p.openTagEditor(item.id) },
        ] + (item.kind == .audio ? [.item("观赏封面", "photo.artframe") { p.openCoverViewer(from: .playlist, index: i) }] : []) + [
            .divider,
            addToPlaylistMenu(p, [item]),
            .menu("移动", "arrow.up.arrow.down", [
                .item("上移", "arrow.up", enabled: i > 0) { p.moveItem(i, to: i - 1) },
                .item("下移", "arrow.down", enabled: i < n - 1) { p.moveItem(i, to: i + 2) },
                .item("移到最前", "arrow.up.to.line", enabled: i > 0) { p.moveItem(i, to: 0) },
                .item("移到最后", "arrow.down.to.line", enabled: i < n - 1) { p.moveItem(i, to: n) },
            ]),
            .item("在访达中显示", "folder", enabled: item.url.isFileURL) { p.revealInFinder(item) },
            .divider,
            .item("从列表移除", "minus.circle", destructive: true) { withAnimation(Motion.panel) { p.remove(at: i) }; p.showHUD("minus.circle", "已移除") },
        ]
    }

    static func playlistBlank(_ p: PlayerController) -> [N] {
        if let id = p.viewingPlaylistID { return userPlaylistBlank(p, id) }
        return addItems(p) + playlist(p) + [.divider, .item("用当前列表新建歌单", "plus.rectangle.on.rectangle") { p.createPlaylist() }]
    }

    static func addToPlaylistMenu(_ p: PlayerController, _ items: [MediaItem]) -> N {
        .menu("加入歌单", "text.badge.plus", p.library.lists.map { l in
            .item(l.name, "music.note.list") { p.addToPlaylist(items, l.id) }
        } + (p.library.lists.isEmpty ? [] : [.divider]) + [
            .item("新建歌单", "plus") { p.createPlaylist(items: items) },
        ])
    }

    static func userPlaylistRow(_ p: PlayerController, _ id: UUID, row r: Int) -> [N] {
        guard let l = p.library.list(id), l.items.indices.contains(r) else { return [] }
        let item = l.items[r], n = l.items.count
        return [
            .item("添加歌曲…", "plus", panel: true) { p.addSongsToViewedPlaylist(folders: false) },
            .item("添加文件夹…", "folder.badge.plus", panel: true) { p.addSongsToViewedPlaylist(folders: true) },
            .divider,
            .item("从这首开始播放歌单", "play.fill") { p.playUserPlaylist(id, from: r) },
            .item("属性", "info.square") { p.toggleProperties(item.id) },
            .item("编辑标签与封面…", "pencil", enabled: p.canEditTags(item)) { p.openTagEditor(item.id) },
            .menu("移动", "arrow.up.arrow.down", [
                .item("上移", "arrow.up", enabled: r > 0) { p.movePlaylistRows(from: [r], to: r - 1, id) },
                .item("下移", "arrow.down", enabled: r < n - 1) { p.movePlaylistRows(from: [r], to: r + 2, id) },
            ]),
            .item("在访达中显示", "folder", enabled: item.url.isFileURL) { p.revealInFinder(item) },
            .divider,
            .item("从歌单移除", "minus.circle", destructive: true) { p.removeFromPlaylist(row: r, id) },
        ]
    }

    static func userPlaylistBlank(_ p: PlayerController, _ id: UUID) -> [N] {
        [
            .item("添加歌曲…", "plus", panel: true) { p.addSongsToViewedPlaylist(folders: false) },
            .item("添加文件夹…", "folder.badge.plus", panel: true) { p.addSongsToViewedPlaylist(folders: true) },
            .divider,
            .item("播放这个歌单", "play.fill", enabled: !(p.library.list(id)?.items.isEmpty ?? true)) { p.playUserPlaylist(id, from: 0) },
            .item("重命名", "pencil") { p.beginRenamePlaylist(id) },
            .item("删除歌单…", "minus.circle", destructive: true) { p.requestDeletePlaylist(id) },
            .divider,
            .item("回到当前列表（Esc）", "chevron.backward") { p.closePlaylistBrowse() },
        ]
    }

    static func subtitleAllMenu(_ p: PlayerController) -> N {
        let v = p.isVideo && p.hasMedia
        guard case .submenu(let tracks) = subtitleMenu(p).kind else { return subtitleMenu(p) }
        return .menu("字幕", "captions.bubble", enabled: v, tracks + [
            .divider,
            .item("加载外挂字幕…", "doc.badge.plus", enabled: v, panel: true) { p.presentSubtitlePanel() },
        ])
    }

    /// 视频画面右键
    static func videoSurface(_ p: PlayerController) -> [N] {
        let full = isFullScreen(p)
        return (p.videoStageOpen ? [.item("返回卡片模式", "chevron.backward") { p.exitVideoStage() }, .divider] : []) + addItems(p) + [
            .item(p.isPlaying ? "暂停" : "播放", p.isPlaying ? "pause.fill" : "play.fill") { p.togglePlay() },
            .item(full ? "退出全屏" : "全屏", full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { p.toggleFullScreen() },
            .item("迷你窗", "pip", checked: p.isPinnedMini) { p.togglePinnedMini() },
            .divider,
            subtitleAllMenu(p),
            audioTrackMenu(p),
            .menu("画面比例", "aspectratio", enabled: p.isVideo && p.hasMedia, PlayerController.aspectChoices.map { a in .item(a.1, checked: p.aspectOverride == a.0) { p.setAspect(a.0) } }),
            .divider,
            speedMenu(p),
            loopMenu(p),
            .item("截图", "camera", enabled: p.isVideo && p.hasMedia) { p.screenshot() },
            .item("在访达中显示", "folder", enabled: p.current?.url.isFileURL == true) { p.revealCurrent() },
        ]
    }

    static func eqMenu(_ p: PlayerController) -> N {
        .menu("均衡器", "slider.vertical.3", [
            .item("开启均衡器", "slider.vertical.3", checked: p.eq.enabled) { p.toggleEQ() },
            presetMenu(p),
            autoEqMenu(p),
            .divider,
            .item(p.tab == .equalizer ? "回到卡片模式" : "打开均衡器页", "slider.horizontal.3") { p.selectTab(p.tab == .equalizer ? .nowPlaying : .equalizer) },
        ])
    }

    /// 播放控制条右键
    static func playBar(_ p: PlayerController) -> [N] {
        let any = !p.queue.items.isEmpty
        return addItems(p) + [
            .item(p.isPlaying ? "暂停" : "播放", p.isPlaying ? "pause.fill" : "play.fill", enabled: any) { p.togglePlay() },
            .item("上一首", "backward.fill", enabled: any) { p.previous() },
            .item("下一首", "forward.fill", enabled: any) { p.next() },
            .divider,
            repeatMenu(p),
            speedMenu(p),
            loopMenu(p),
            .divider,
            eqMenu(p),
            outputMenu(p),
            .item("迷你窗", "pip", checked: p.isPinnedMini) { p.togglePinnedMini() },
        ]
    }

    static func progressBar(_ p: PlayerController) -> [N] {
        let has = p.hasMedia
        var loop: [N] = []
        if case .submenu(let c) = loopMenu(p).kind { loop = c }
        return [
            .item("快退 15 秒", "gobackward.15", enabled: has) { p.seek(by: -PlayerController.seekStep) },
            .item("快进 15 秒", "goforward.15", enabled: has) { p.seek(by: PlayerController.seekStep) },
            .divider,
            .header("区间循环（A-B）"),
        ] + loop
    }

    static func lyricsArea(_ p: PlayerController) -> [N] {
        [
            .header(p.lyricsSource.map { "当前歌词来自 \($0)" } ?? (p.lyrics != nil ? "当前歌词来自本地文件" : "当前没有歌词")),
            lyricsItem(p),
            subtitleToolsMenu(p),
        ]
    }

    static func subtitleArea(_ p: PlayerController) -> [N] {
        [subtitleAllMenu(p), subtitleToolsMenu(p), .divider, audioTrackMenu(p)]
    }

    static func volumeArea(_ p: PlayerController) -> [N] {
        [
            .item("静音", "speaker.slash", checked: p.muted) { p.toggleMute() },
            .divider,
            outputMenu(p),
            eqMenu(p),
        ]
    }

    static func paramCard(_ p: PlayerController, _ c: ParamCard) -> [N] {
        var out: [N]
        switch c {
        case .loop: if case .submenu(let x) = loopMenu(p).kind { out = x } else { out = [] }
        case .speedPitch: if case .submenu(let x) = speedMenu(p).kind { out = x } else { out = [] }
            out = out.filter { !$0.title.hasPrefix("打开变速变调面板") && !$0.title.hasPrefix("收起变速变调面板") }
        case .subtitle: out = [subtitleAllMenu(p), subtitleToolsMenu(p)]
        case .autoEq: if case .submenu(let x) = autoEqMenu(p).kind { out = x } else { out = [] }
            out = out.filter { !$0.title.hasPrefix("收起耳机校正") && !$0.title.hasPrefix("选择耳机") }
            out += [.divider, .item("开启均衡器", "slider.vertical.3", checked: p.eq.enabled) { p.toggleEQ() }]
        }
        return out + [.divider, .item("收起这张卡片（Esc）", "chevron.down") { p.closeCard() }]
    }

    static func equalizer(_ p: PlayerController) -> [N] {
        [
            .item("开启均衡器", "slider.vertical.3", checked: p.eq.enabled) { p.toggleEQ() },
            presetMenu(p),
            .menu("段数", "slider.horizontal.3", EQBandCount.allCases.map { c in .item("\(c.rawValue) 段", checked: p.eq.bandCount == c) { p.setBandCountFromMenu(c) } }),
            .menu("前级", "dial.low", [
                .item("前级归零", "dial.low") { withAnimation(Motion.panel) { p.setPreamp(0) }; p.showHUD("dial.low", "前级 0 dB") },
                .item("自动前级（防削波）", "waveform.path.ecg") { withAnimation(Motion.panel) { p.setPreamp(p.eq.suggestedPreamp) }; p.showHUD("waveform.path.ecg", String(format: "前级 %.1f dB", p.eq.preamp)) },
            ]),
            .item("存为预设…", "square.and.arrow.down", panel: true) { p.savePresetPrompt() },
            .item("重置均衡器", "arrow.counterclockwise") { withAnimation(Motion.panel) { p.resetEQ() }; p.showHUD("arrow.counterclockwise", "均衡器已重置") },
            .divider,
            autoEqMenu(p),
            outputMenu(p),
            .divider,
            .item("回到卡片模式（Esc）", "chevron.down") { p.selectTab(.nowPlaying) },
        ]
    }

    /// 窗口空白处右键（已彻底去除配色主题，极简清爽）
    static func blank(_ p: PlayerController) -> [N] {
        var out: [N] = []
        if p.isLifted { out += [.item("翻回封面", "chevron.backward") { p.exitLift() }, .divider] }
        if p.videoStageOpen && p.tab == .nowPlaying { out += [.item("返回卡片模式", "chevron.backward") { p.exitVideoStage() }, .divider] }
        if p.isPinnedMini { out += [.item("退出迷你窗", "arrow.up.backward.and.arrow.down.forward") { p.togglePinnedMini() }, .divider] }
        let full = isFullScreen(p)
        out += addItems(p) + [
            .item("打开网址…", "globe", panel: true) { p.openURLPrompt() },
            recentMenu(p),
            .divider,
            .item("迷你窗", "pip", checked: p.isPinnedMini) { p.togglePinnedMini() },
            .item("窗口置顶", "pin", checked: p.isFloating) { p.toggleFloating() },
            .item(full ? "退出全屏" : "全屏", full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right") { p.toggleFullScreen() },
            .divider,
            .item("键盘快捷键", "keyboard") { p.toggleShortcutsHelp() },
        ]
        return out
    }

    static func mini(_ p: PlayerController) -> [N] {
        [
            .item(p.isPlaying ? "暂停" : "播放", p.isPlaying ? "pause.fill" : "play.fill") { p.togglePlay() },
            .item("上一首", "backward.fill") { p.previous() },
            .item("下一首", "forward.fill") { p.next() },
            .item("静音", "speaker.slash", checked: p.muted) { p.toggleMute() },
            .divider,
            .item("窗口置顶", "pin", checked: p.isFloating) { p.toggleFloating() },
            .item("退出迷你窗", "arrow.up.backward.and.arrow.down.forward") { p.togglePinnedMini() },
        ]
    }

    static func viewer(_ p: PlayerController) -> [N] {
        let v = p.viewer.view
        let zoomed = v?.isZoomed ?? false
        let full = isFullScreen(p)
        return [
            .item(zoomed ? "适应窗口" : "原图 100%", zoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass", key: zoomed ? KeyEquivalent("0") : nil) {
                if zoomed { v?.zoomToFit() } else { v?.zoomToActual() }
            },
            .item(full ? "退出全屏" : "全屏", full ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", key: "f", mods: []) { p.viewerToggleFullScreen() },
            .header(v?.pixelInfo ?? ""),
            .divider,
            .item("退出观赏", "xmark") { p.closeCoverViewer() },
        ]
    }

    static func allContexts(_ p: PlayerController) -> [(String, [N])] {
        let i = p.queue.currentIndex ?? 0
        return [("封面卡片", card(p, index: i)), ("播放列表条目", playlistRow(p, index: i)), ("播放列表空白处", playlistBlank(p)),
                ("视频画面", videoSurface(p)), ("播放控制条", playBar(p)), ("进度条", progressBar(p)), ("歌词条", lyricsArea(p)),
                ("字幕与音轨按钮", subtitleArea(p)), ("音量", volumeArea(p)), ("均衡器", equalizer(p)), ("空白处", blank(p)), ("迷你窗", mini(p)), ("封面观赏", viewer(p))]
            + ParamCard.allCases.map { ("参数卡片·\($0.title)", paramCard(p, $0)) }
    }

    static func menuBar(_ p: PlayerController) -> [(String, [N])] {
        [("文件", file(p)), ("编辑", edit(p)), ("播放", playback(p)), ("音频", audio(p)), ("视频", video(p)),
         ("播放列表", playlist(p)), ("显示", view(p)), ("窗口", window(p)), ("帮助", help(p))]
    }

    /// 精简对照清单（保持与当前极简菜单结构一致）
    static let simplifyMap: [(String, String, String, String)] = [
        ("窗口空白处", "配色主题 ▸", "配色主题", "右键里去掉，改用右上角调色板按钮；菜单栏「显示」仍保留"),
        ("封面卡片", "快退 / 快进", "快退 15 秒", "统一合并为 15 秒，在进度条右键、菜单栏「播放」与 ← → 键"),
        ("封面卡片", "联网查找封面 / 改用默认封面", "联网查找封面", "收进「封面」子菜单"),
        ("播放列表条目", "上移 / 下移 / 移到最前 / 移到最后", "上移", "收进「移动」子菜单"),
        ("视频画面", "画中画 / 关于画中画", "迷你窗", "系统不支持画中画，统一使用「迷你窗」"),
        ("播放控制条", "循环 ▸ / 随机播放", "随机播放", "合成「循环与随机」子菜单"),
        ("播放控制条", "均衡器全套入口", "均衡器预设", "收进「均衡器」子菜单，底部控制条亦有一键直达按钮"),
        ("菜单栏·文件", "添加歌曲… / 添加文件夹…", "添加歌曲…", "统一名称与右键一致"),
    ]
}
