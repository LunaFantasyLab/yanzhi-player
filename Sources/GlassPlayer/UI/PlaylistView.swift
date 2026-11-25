// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import UniformTypeIdentifiers
import PlayerCore

/// 播放列表：一块大玻璃面板，当前曲目行有呼吸光；行出现时依次弹入；支持拖动排序、右键菜单。
/// 2026-11-23：标题下一排「当前列表 / 自己的歌单」，旁边不起眼的「+」「−」；点文件名或封面翻到属性，属性背面右下角铅笔改标签。
struct PlaylistView: View {
    @Environment(PlayerController.self) private var player
    @State private var appeared = false
    @State private var hovered: String?
    @State private var panelTargeted = false

    var body: some View {
        let accent = Color(player.palette.accent)
        let dropping = (panelTargeted || player.dropInsertIndex != nil) && !player.playlistBrowseOpen
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.inkFill.opacity(0.10))
            if let pl = player.viewingPlaylist {
                userList(pl)
            } else if player.queue.items.isEmpty {
                EmptyLibraryView(compact: true).frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(Array(player.queue.items.enumerated()), id: \.element.id) { i, item in
                            row(item, isCurrent: i == player.queue.currentIndex, viewerKey: "row:" + item.id, play: { player.play(index: i) },
                                menu: { MenuCatalog.playlistRow(player, index: i) })
                                .overlay(alignment: .top) { InsertLine(accent: accent).offset(y: -4).opacity(player.dropInsertIndex == i ? 1 : 0) }
                                .onDrop(of: [.fileURL], delegate: RowDrop(index: i, tail: false, player: player))
                                .id(item.id)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 14)
                                .animation(Motion.stagger(min(i, 14)), value: appeared)
                        }
                        .onMove { from, to in withAnimation(Motion.panel) { player.move(from: from, to: to) } }
                        // 列表末尾的空白：拖到这里 = 加到最后
                        Color.clear.frame(height: 40)
                            .listRowBackground(Color.clear).listRowSeparator(.hidden)
                            .overlay(alignment: .top) { InsertLine(accent: accent).opacity(player.dropInsertIndex == player.queue.items.count ? 1 : 0) }
                            .onDrop(of: [.fileURL], delegate: RowDrop(index: player.queue.items.count, tail: true, player: player))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .onChange(of: player.locateToken) { _, _ in
                        if let id = player.current?.id { withAnimation(Motion.panel) { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
                .transition(.opacity)
            }
        }
        .glass(shape, tint: Color(player.palette.glassTint), amount: 0.07)
        // 拖入时：玻璃边缘被点亮（强调色光晕 + 亮边），提示这里可以放下
        .overlay {
            ZStack {
                shape.fill(accent.opacity(0.08))
                shape.strokeBorder(Color.edge.opacity(0.85), lineWidth: 1.5)
            }
            .opacity(dropping ? 1 : 0)
            .scaleEffect(dropping ? 1 : 1.015)
            .allowsHitTesting(false)
        }
        .scaleEffect(dropping ? 1.006 : 1)
        .animation(Motion.panel, value: dropping)
        .animation(Motion.panel, value: player.viewingPlaylistID)
        .onDrop(of: [.fileURL], isTargeted: $panelTargeted) { providers in
            if let id = player.viewingPlaylistID {
                PlayerController.loadFileURLs(providers) { urls in
                    let items = PlayerController.expand(urls).map { MediaItem(url: $0) }
                    if !items.isEmpty { player.addToPlaylist(items, id) }
                }
                return true
            }
            let at = player.dropInsertIndex ?? player.queue.items.count
            PlayerController.loadFileURLs(providers) { urls in player.insert(urls: urls, at: at); player.setDropInsert(nil) }
            return true
        }
        .contextMenu { MenuContent(nodes: MenuCatalog.playlistBlank(player)) }
        .alert("删除这个歌单？", isPresented: Binding(get: { player.asksDeletePlaylist != nil }, set: { if !$0 { player.asksDeletePlaylist = nil } })) {
            Button("取消", role: .cancel) { player.asksDeletePlaylist = nil }
            Button("删除", role: .destructive) { if let id = player.asksDeletePlaylist { player.deletePlaylist(id) } }
        } message: {
            Text("只删歌单「\(player.asksDeletePlaylist.flatMap { player.library.list($0)?.name } ?? "")」，不删音乐文件。")
        }
        .onAppear { appeared = true }
        .onDisappear { appeared = false; player.closeProperties() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("播放列表").font(.system(size: 20, weight: .bold))
                    if !summary.isEmpty {
                        Text(summary).font(.system(size: 12)).opacity(0.6).contentTransition(.numericText())
                    }
                }
                PlaylistChips()
            }
            Spacer()
            Button { player.openPlayHistory() } label: {
                Label("播放记录", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(GlassChipStyle())
            .fixedSize()
            .help("查看播放过的音乐")
            .accessibilityLabel("播放记录")
            // 只留一个「添加」和一个「更多」：定位、排序、清空、保存/载入都在「更多」和右键菜单里
            Menu {
                Button { player.viewingPlaylistID == nil ? player.presentAddPanel(folders: false) : player.addSongsToViewedPlaylist(folders: false) } label: { Label("添加歌曲…", systemImage: "plus") }
                Button { player.viewingPlaylistID == nil ? player.presentAddPanel(folders: true) : player.addSongsToViewedPlaylist(folders: true) } label: { Label("添加文件夹…", systemImage: "folder.badge.plus") }
            } label: { Label("添加", systemImage: "plus") }
                .menuStyle(.button).buttonStyle(GlassChipStyle()).fixedSize()
            Menu { MenuContent(nodes: player.viewingPlaylistID.map { Array(MenuCatalog.userPlaylistBlank(player, $0).dropFirst(3)) } ?? Array(MenuCatalog.playlist(player).dropFirst(3))) } label: {
                Image(systemName: "ellipsis").frame(height: 14)
            }
            .menuStyle(.button).menuIndicator(.hidden).buttonStyle(GlassChipStyle()).fixedSize()
            .help("定位当前曲目、排序、移除、清空、保存 / 载入播放列表")
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    private var summary: String {
        let items = player.viewingPlaylist?.items ?? player.queue.items
        let n = items.count
        let total = items.compactMap { player.details[$0.id]?.item.duration ?? $0.duration }.reduce(0, +)
        return n == 0 ? "" : "\(n) 项 · \(TimeFormat.clock(total))"
    }

    /// 自己的歌单：双击一首 = 换成这个歌单从这首播；可拖动排序
    @ViewBuilder private func userList(_ pl: UserPlaylist) -> some View {
        if pl.items.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "music.note.list").font(.system(size: 30, weight: .light)).opacity(0.35)
                HStack(spacing: 8) {
                    Button { player.addSongsToViewedPlaylist(folders: false) } label: { Label("添加歌曲", systemImage: "plus") }
                        .buttonStyle(GlassChipStyle(fontSize: 12))
                    Button { player.addSongsToViewedPlaylist(folders: true) } label: { Label("添加文件夹", systemImage: "folder.badge.plus") }
                        .buttonStyle(GlassChipStyle(fontSize: 12))
                }
            }
            .foregroundStyle(Color.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        } else {
            List {
                ForEach(Array(pl.items.enumerated()), id: \.element.id) { r, item0 in
                    let item = player.details[item0.id]?.item ?? item0
                    row(item, isCurrent: player.queue.current?.id == item.id, viewerKey: "pl:" + item.id, play: { player.playUserPlaylist(pl.id, from: r) },
                        menu: { MenuCatalog.userPlaylistRow(player, pl.id, row: r) })
                        .onAppear { player.ensureDetails(item0) }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                }
                .onMove { from, to in player.movePlaylistRows(from: from, to: to, pl.id) }
                Color.clear.frame(height: 30).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .transition(.opacity)
        }
    }

    private func row(_ item: MediaItem, isCurrent: Bool, viewerKey: String, play: @escaping () -> Void, menu: @escaping () -> [MenuNode]) -> some View {
        let isHover = hovered == item.id
        let flipped = player.flippedRowID == item.id
        let accent = Color(player.palette.accent)
        // 点文件名或封面 = 翻面看属性；双击 = 播放
        let flip = TapGesture(count: 2).onEnded { play() }.exclusively(before: TapGesture().onEnded { player.toggleProperties(item.id) })
        return ZStack {
            HStack(spacing: 12) {
                ZStack {
                    if let art = player.art(for: item) {
                        Image(decorative: art.thumbnail, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill).transition(.opacity)
                    } else {
                        Color.white.opacity(0.08)
                    }
                    if isCurrent {
                        Color.black.opacity(0.35)
                        if player.isPlaying { PlayingBars(color: .white).frame(width: 14, height: 12).transition(.scale.combined(with: .opacity)) }
                        else { Image(systemName: "pause.fill").font(.system(size: 11, weight: .bold)).transition(.scale.combined(with: .opacity)) }
                    }
                }
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(Motion.toggle, value: player.isPlaying)
                // 右键「观赏封面」时从这里飞出、飞回
                .background(ViewerRectProbe(key: viewerKey, radius: 8))
                .modifier(ViewerHide(key: viewerKey))
                .contentShape(Rectangle())
                .gesture(flip)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        if item.kind == .video { Image(systemName: "film").font(.system(size: 10, weight: .semibold)).opacity(0.6) }
                        if !item.url.isFileURL { Image(systemName: "globe").font(.system(size: 10, weight: .semibold)).opacity(0.6) }
                        Text(item.title).font(.system(size: 13, weight: isCurrent ? .bold : .medium)).lineLimit(1)
                            .contentShape(Rectangle())
                            .gesture(flip)
                    }
                    let sub = [item.knownArtist, item.album].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " — ")
                    if !sub.isEmpty { Text(sub).font(.system(size: 11)).opacity(0.58).lineLimit(1) }
                }
                Spacer()
                if let f = item.formatLine, isHover || isCurrent {
                    Text(f).font(.system(size: 10, weight: .semibold, design: .rounded)).opacity(0.55)
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                Text(TimeFormat.clock(item.duration)).font(.system(size: 12, design: .rounded).monospacedDigit()).opacity(0.6)
            }
            .opacity(flipped ? 0 : 1)
            .rotation3DEffect(.degrees(flipped ? -180 : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .allowsHitTesting(!flipped)

            if flipped {
                PropertiesBack(item: item)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)), removal: .opacity))
            }
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background {
            // 当前行：一块扁平的强调色玻璃；悬停行：淡白；翻面：深一点的底（11-23 无边框规范）
            let r = RoundedRectangle(cornerRadius: 12, style: .continuous)
            r.fill(flipped ? Color.black.opacity(0.22) : (isCurrent ? accent.opacity(0.24) : Color.inkFill.opacity(isHover ? 0.07 : 0)))
        }
        .scaleEffect(isHover && !flipped ? 1.006 : 1)
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Motion.hover) { hovered = h ? item.id : (hovered == item.id ? nil : hovered) } }
        .onTapGesture(count: 2) { if !flipped { play() } }
        .animation(Motion.panel, value: isCurrent)
        .animation(Motion.lift, value: flipped)
        .contextMenu { MenuContent(nodes: menu()) }
    }
}

/// 标题下那一排：当前列表 + 自己的歌单 + 不起眼的「+」「−」
struct PlaylistChips: View {
    @Environment(PlayerController.self) private var player
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        let accent = Color(player.palette.accent)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button("当前列表") { player.viewPlaylist(nil) }
                    .buttonStyle(GlassChipStyle(selected: player.viewingPlaylistID == nil, accent: accent, fontSize: 11.5))
                ForEach(player.library.lists) { l in
                    if player.renamingPlaylistID == l.id {
                        TextField("歌单名", text: $draft)
                            .textFieldStyle(.plain).font(.system(size: 11.5, weight: .semibold))
                            .focused($editing)
                            .frame(width: max(64, CGFloat(draft.count) * 12 + 16))
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(Capsule().fill(accent.opacity(0.34)))
                            .onAppear { draft = l.name; after(0.05) { editing = true } }
                            .onSubmit { player.commitRenamePlaylist(l.id, draft) }
                            .onChange(of: editing) { _, f in if !f, player.renamingPlaylistID == l.id { player.commitRenamePlaylist(l.id, draft) } }
                    } else {
                        Button(l.name) { player.viewPlaylist(l.id) }
                            .buttonStyle(GlassChipStyle(selected: player.viewingPlaylistID == l.id, accent: accent, fontSize: 11.5))
                            .simultaneousGesture(TapGesture(count: 2).onEnded { player.beginRenamePlaylist(l.id) })
                            .contextMenu {
                                MenuContent(nodes: [
                                    .item("重命名", "pencil") { player.beginRenamePlaylist(l.id) },
                                    .item("删除歌单…", "minus.circle", destructive: true) { player.requestDeletePlaylist(l.id) },
                                ])
                            }
                    }
                }
                Button { player.createPlaylist() } label: { Image(systemName: "plus").font(.system(size: 10.5, weight: .bold)) }
                    .buttonStyle(GlassIconButtonStyle(size: 22)).opacity(0.7)
                    .help("用当前列表新建歌单")
                if player.viewingPlaylistID != nil {
                    Button { player.requestDeletePlaylist() } label: { Image(systemName: "minus").font(.system(size: 10.5, weight: .bold)) }
                        .buttonStyle(GlassIconButtonStyle(size: 22)).opacity(0.7)
                        .help("删除这个歌单（不删文件）")
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .padding(.vertical, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.panel, value: player.library.lists.map(\.id))
        .animation(Motion.toggle, value: player.renamingPlaylistID)
    }
}

/// 属性（行的背面）：格式、时长、大小、位置和标签；右下角铅笔 = 编辑标签
struct PropertiesBack: View {
    @Environment(PlayerController.self) private var player
    let item: MediaItem
    var body: some View {
        let props = player.fileProperties[item.id]
        let tags = props?.tags ?? [:]
        let tagRows: [(String, String)] = [("标题", "title"), ("歌手", "artist"), ("专辑", "album"), ("专辑艺术家", "album_artist"), ("音轨", "track"), ("年份", "date"), ("流派", "genre")]
            .compactMap { k, key in tags[key].flatMap { $0.isEmpty ? nil : (k, $0) } }
        ZStack(alignment: .bottomTrailing) {
            HStack(alignment: .top, spacing: 18) {
                grid(tagRows.isEmpty ? [("标签", "没有")] : tagRows)
                grid(props?.rows ?? [("", "正在读取…")])
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 34)
            if player.canEditTags(item) {
                Button { player.openTagEditor(item.id) } label: { Image(systemName: "pencil").font(.system(size: 12, weight: .semibold)) }
                    .buttonStyle(GlassIconButtonStyle(size: 26, prominent: true))
                    .help("编辑标签")
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { player.closeProperties() }
    }
    private func grid(_ rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(r.0).font(.system(size: 11)).opacity(0.55).lineLimit(1).frame(width: 56, alignment: .leading)
                    Text(r.1).font(.system(size: 11.5, weight: .medium)).lineLimit(1).truncationMode(.middle).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 编辑 ID3 信息与 4K 专辑封面（100% 不透明黑曜石实底：左 168pt 封面区 + 右 340pt 规范表单，打字时零透底重叠、绝不折行/挤压）
struct TagEditorSheet: View {
    @Environment(PlayerController.self) private var player
    let item: MediaItem
    @State private var fields: [String: String] = [:]
    @State private var original: [String: String] = [:]
    @State private var dirty: Set<String> = []
    @State private var cover: TagEdit.CoverChange = .keep
    @State private var coverPreview: NSImage?
    @State private var generatingCover = false
    @State private var loaded = false
    @State private var lastGeneratedStyle: DefaultCoverStyle?
    static let keys: [(String, String)] = [("标题", "title"), ("歌手", "artist"), ("专辑", "album"), ("专辑艺术家", "album_artist"), ("音轨", "track"), ("年份", "date"), ("流派", "genre")]

    var body: some View {
        let accent = Color(player.palette.accent)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("编辑 ID3 信息与封面").font(.system(size: 16, weight: .bold))
                Spacer(minLength: 8)
                Text(item.url.lastPathComponent)
                    .font(.system(size: 11, design: .monospaced))
                    .opacity(0.55)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            HStack(alignment: .top, spacing: 24) {
                // 左侧封面区：严格 168pt 宽，按钮分两排整齐对齐，绝不撑破或挤压右侧表单
                VStack(spacing: 10) {
                    ZStack {
                        if let img = coverPreview { Image(nsImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fill) }
                        else if case .remove = cover { Color.inkFill.opacity(0.08) }
                        else if let art = player.art(for: item) { Image(decorative: art.image, scale: 1).resizable().interpolation(.high).aspectRatio(contentMode: .fill) }
                        else { Color.inkFill.opacity(0.08) }
                        if generatingCover {
                            Color.black.opacity(0.35)
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    .frame(width: 168, height: 168)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 10, y: 4)

                    HStack(spacing: 8) {
                        Button("换图…") { pickCover() }
                            .buttonStyle(GlassChipStyle(fontSize: 11.5))
                        Button { generateRandomCover() } label: {
                            Label("随机", systemImage: "dice")
                        }
                        .buttonStyle(GlassChipStyle(fontSize: 11.5))
                        .disabled(generatingCover)
                        .help("本地随机生成一张 4K 高清封面")
                    }
                    Button("移除封面") { cover = .remove; coverPreview = nil }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .opacity(0.6)
                }
                .frame(width: 168)

                // 右侧表单区：固定标签列宽 68pt 单行右对齐 + 全宽通透输入框，音轨/年份同行对齐，排版清爽对称
                VStack(alignment: .leading, spacing: 10) {
                    fieldRow("标题", key: "title", placeholder: "歌曲标题")
                    fieldRow("歌手", key: "artist", placeholder: "演唱者 / 艺术家")
                    fieldRow("专辑", key: "album", placeholder: "所属专辑")
                    fieldRow("专辑艺人", key: "album_artist", placeholder: "专辑艺术家（可选）")
                    fieldRow("流派", key: "genre", placeholder: "风格流派（如 古典 / 流行）")
                    HStack(spacing: 12) {
                        Text("音轨")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.72)
                            .lineLimit(1)
                            .frame(width: 68, alignment: .trailing)
                        inputField(key: "track", placeholder: "1/12")
                            .frame(maxWidth: .infinity)
                        Text("年份")
                            .font(.system(size: 12, weight: .medium))
                            .opacity(0.72)
                            .lineLimit(1)
                            .fixedSize()
                        inputField(key: "date", placeholder: "2026")
                            .frame(width: 84)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            Divider().overlay(Color.inkFill.opacity(0.12))

            HStack {
                Text(player.tagSaving ? "正在保存…" : (player.writesEmbeddedTags(item) ? "保存前会自动备份原文件" : "该格式无损保存在本地标签库，不改动原音频文件"))
                    .font(.system(size: 11.5)).opacity(0.58)
                Spacer()
                Button("取消") { player.closeTagEditor() }.buttonStyle(GlassChipStyle()).disabled(player.tagSaving)
                Button("保存") { player.saveTags(item.id, edit()) }
                    .buttonStyle(GlassChipStyle(selected: true, accent: accent))
                    .keyboardShortcut(.defaultAction)
                    .disabled(player.tagSaving || generatingCover || !loaded)
            }
        }
        .foregroundStyle(Color(ObsidianChrome.text))
        .padding(24)
        .frame(width: 580)
        // ID3 修改页面专属 100% 不透明实底（alpha = 1.0，不叠加半透材质），严格裁切为连续圆角，打字时零透底重叠
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(ObsidianChrome.fill))
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.55), radius: 36, x: 0, y: 18)
        .onAppear(perform: load)
        .onChange(of: player.fileProperties[item.id]) { _, _ in mergeProbed() }
    }

    private func fieldRow(_ label: String, key: String, placeholder: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .opacity(0.72)
                .lineLimit(1)
                .frame(width: 68, alignment: .trailing)
            inputField(key: key, placeholder: placeholder)
                .frame(maxWidth: .infinity)
        }
    }

    private func inputField(key: String, placeholder: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        return TextField(placeholder, text: Binding(
            get: { fields[key] ?? "" },
            set: { fields[key] = $0; dirty.insert(key) }
        ))
        .textFieldStyle(.plain)
        .font(.system(size: 12.5))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(shape.fill(Color.white.opacity(0.09)))
    }

    private func load() {
        guard !loaded else { return }
        let p = player.fileProperties[item.id]
        var f: [String: String] = [:]
        for (_, k) in Self.keys {
            let probed = p?.tags[k] ?? (k == "album_artist" ? p?.tags["albumartist"] : nil) ?? (k == "date" ? p?.tags["year"] : nil)
            let fallback: String? = switch k {
            case "title": item.title
            case "artist": item.knownArtist
            case "album": item.album
            case "track": item.trackNumber.map(String.init)
            default: nil
            }
            f[k] = probed ?? fallback ?? ""
        }
        fields = f; original = f; loaded = true
    }

    private func mergeProbed() {
        guard let p = player.fileProperties[item.id] else { return }
        for (_, k) in Self.keys where !dirty.contains(k) {
            if let probed = p.tags[k] ?? (k == "album_artist" ? p.tags["albumartist"] : nil) ?? (k == "date" ? p.tags["year"] : nil), !probed.isEmpty {
                fields[k] = probed
                original[k] = probed
            }
        }
    }

    private func edit() -> TagEdit {
        func v(_ k: String) -> String? { (fields[k] ?? "") == (original[k] ?? "") ? nil : (fields[k] ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
        var e = TagEdit()
        e.title = v("title"); e.artist = v("artist"); e.album = v("album"); e.albumArtist = v("album_artist")
        e.track = v("track"); e.year = v("date"); e.genre = v("genre")
        e.cover = cover
        return e
    }

    private func pickCover() {
        let url: URL?
        if let t = TestHooks.openPanel(folders: false) { url = t.first } else {
            let p = NSOpenPanel()
            p.allowedContentTypes = [.jpeg, .png, .heic, .webP, .tiff]
            p.prompt = "用作封面"
            url = p.runModal() == .OK ? p.url : nil
        }
        guard let url, let raw = try? Data(contentsOf: url) else { return }
        let ext = url.pathExtension.lowercased()
        if ext == "jpg" || ext == "jpeg" || ext == "png" {
            guard let cg = MetadataReader.decodeImage(raw) else { return }
            cover = .set(raw, mime: ext == "png" ? "image/png" : "image/jpeg")
            coverPreview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } else if let cg = MetadataReader.decodeImage(raw) {
            // 按 4K 原生像素转换，绝不经由 72dpi tiffRepresentation 掉分辨率
            let rep = NSBitmapImageRep(cgImage: cg)
            guard let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.96]) else { return }
            cover = .set(jpg, mime: "image/jpeg")
            coverPreview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    private func generateRandomCover() {
        guard !generatingCover else { return }
        generatingCover = true
        let seed = item.baseCoverSeed + "|edit:\(UInt64.random(in: 1...UInt64.max))"
        let title = (fields["album"]?.isEmpty == false ? fields["album"]! : (fields["title"]?.isEmpty == false ? fields["title"]! : item.title))
        let artist = fields["artist"]?.isEmpty == false ? fields["artist"]! : item.displayArtist
        // 每次点击必换全新风格（18 种艺术风格 × 32 套鲜活色盘，不与上一次重复）
        let pool = DefaultCoverStyle.allCases.filter { $0 != lastGeneratedStyle }
        let style = pool.randomElement() ?? .stainedGlass
        lastGeneratedStyle = style
        Task.detached(priority: .userInitiated) {
            let spec = DefaultCoverSpec.make(seed: seed)
            // 严格 4K UHD（3840×3840）本地生成高清封面
            let cg = CoverStore.defaultCover(spec: spec, style: style, title: title, artist: artist, size: CoverStore.maxSide)
            let rep = NSBitmapImageRep(cgImage: cg)
            let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.96])
            await MainActor.run {
                generatingCover = false
                guard let jpg else { return }
                cover = .set(jpg, mime: "image/jpeg")
                coverPreview = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }
        }
    }
}

/// 播放列表里的玻璃插入线：白芯 + 强调色光晕，出现/消失带弹簧
struct InsertLine: View {
    var accent: Color
    var body: some View {
        HStack(spacing: 0) {
            Circle().strokeBorder(Color.ink, lineWidth: 2).frame(width: 9, height: 9)
            Capsule().fill(Color.ink).frame(height: 2.5)
        }
        .shadow(color: accent.opacity(0.6), radius: 4)
        .padding(.horizontal, 4)
        .allowsHitTesting(false)
        .animation(Motion.hover, value: accent)
    }
}

/// 拖到某一行：上半行 = 插到它前面，下半行 = 插到它后面
struct RowDrop: DropDelegate {
    let index: Int
    let tail: Bool
    let player: PlayerController
    static let rowHeight: CGFloat = 52

    static func insertionIndex(row: Int, y: CGFloat, height: CGFloat = rowHeight) -> Int { y < height / 2 ? row : row + 1 }

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? { update(info); return DropProposal(operation: .copy) }
    func dropExited(info: DropInfo) { MainActor.assumeIsolated { player.setDropInsert(nil) } }
    func performDrop(info: DropInfo) -> Bool {
        let at = tail ? index : Self.insertionIndex(row: index, y: info.location.y)
        let providers = info.itemProviders(for: [.fileURL])
        MainActor.assumeIsolated {
            PlayerController.loadFileURLs(providers) { urls in player.insert(urls: urls, at: at); player.setDropInsert(nil) }
        }
        return true
    }
    private func update(_ info: DropInfo) {
        let at = tail ? index : Self.insertionIndex(row: index, y: info.location.y)
        MainActor.assumeIsolated { player.setDropInsert(at) }
    }
}

/// 空状态：一个慢慢旋转的玻璃光环 + 引导文字
struct EmptyLibraryView: View {
    @Environment(PlayerController.self) private var player
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 24 : 32) {
            EmptyMark(style: EmptyMarkStyle.preview, compact: compact)
            HStack(spacing: 8) {
                Button { player.presentAddPanel(folders: false) } label: {
                    Label("添加文件", systemImage: "plus")
                }
                .buttonStyle(GlassChipStyle(fontSize: compact ? 12 : 13))
                .accessibilityLabel("添加文件")
                Button { player.presentAddPanel(folders: true) } label: {
                    Label("添加文件夹", systemImage: "folder.badge.plus")
                }
                .buttonStyle(GlassChipStyle(fontSize: compact ? 12 : 13))
                .accessibilityLabel("添加文件夹")
            }
        }
        .foregroundStyle(Color.ink)
    }
}
