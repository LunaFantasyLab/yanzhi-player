// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import SwiftUI
import AppKit
import AVFoundation
import UniformTypeIdentifiers
import PlayerCore

/// 文件属性（播放列表行翻到背面时显示）
struct FileProperties: Equatable {
    var rows: [(String, String)]
    var tags: [String: String]
    static func == (a: Self, b: Self) -> Bool { a.rows.map { $0.0 + $0.1 } == b.rows.map { $0.0 + $0.1 } && a.tags == b.tags }
}

/// 2026-11-23 七项改版里和「资料」有关的部分：歌单、主题排序、生成封面换一张、属性卡与改标签。
extension PlayerController {
    /// playlists.json / cover-rerolls.json 放哪：正常用 = ~/Library/Application Support/GlassPlayer/；
    /// 自测（-sessionPath）= 跟会话文件放一起；沙盒却没给路径 = 临时目录（绝不碰本人的资料）
    static func sidecarURL(sessionURL: URL, defaultDir: URL, name: String, explicit: Bool) -> URL {
        if explicit {
            let base = sessionURL.deletingPathExtension().lastPathComponent
            return sessionURL.deletingLastPathComponent().appendingPathComponent("\(base)-\(name).json")
        }
        if Prefs.sandbox {
            return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("liuli-sandbox-\(getpid())", isDirectory: true).appendingPathComponent("\(name).json")
        }
        return defaultDir.appendingPathComponent("\(name).json")
    }

    // MARK: - 歌单
    func scheduleLibrarySave() {
        librarySaveWork?.cancel()
        librarySaveWork = after(0.4) { [weak self] in self?.saveLibraryNow() }
    }
    func saveLibraryNow() {
        librarySaveWork?.cancel(); librarySaveWork = nil
        do { try PlaylistLibraryStore.save(library, to: libraryURL) } catch { TestHooks.log("✗ 歌单保存失败：\(error)") }
    }

    var viewingPlaylist: UserPlaylist? { viewingPlaylistID.flatMap { library.list($0) } }

    func viewPlaylist(_ id: UUID?) {
        guard viewingPlaylistID != id else { return }
        renamingPlaylistID = nil
        flippedRowID = nil
        withAnimation(Motion.panel) { viewingPlaylistID = id }
        if let p = viewingPlaylist { for it in p.items.prefix(30) { ensureDetails(it) } }
    }
    func closePlaylistBrowse() { viewPlaylist(nil) }

    /// 「+」：用当前播放列表里的歌新建一个歌单，马上可以起名
    @discardableResult
    func createPlaylist(items: [MediaItem]? = nil) -> UUID {
        let src = items ?? queue.items
        let id = withAnimation(Motion.panel) { library.create(items: src) }
        scheduleLibrarySave()
        viewPlaylist(id)
        withAnimation(Motion.toggle) { renamingPlaylistID = id }
        showHUD("music.note.list", src.isEmpty ? "新建了空歌单" : "新建歌单：\(src.count) 首")
        return id
    }
    func beginRenamePlaylist(_ id: UUID) { withAnimation(Motion.toggle) { renamingPlaylistID = id } }
    func commitRenamePlaylist(_ id: UUID, _ name: String) {
        if library.rename(id, to: name) { scheduleLibrarySave() }
        withAnimation(Motion.toggle) { renamingPlaylistID = nil }
    }
    func cancelRenamePlaylist() { withAnimation(Motion.toggle) { renamingPlaylistID = nil } }

    /// 「−」：删掉正在看的歌单（先问一句；只删歌单，不删文件）
    func requestDeletePlaylist(_ id: UUID? = nil) {
        guard let id = id ?? viewingPlaylistID, library.list(id) != nil else { return }
        asksDeletePlaylist = id
    }
    func deletePlaylist(_ id: UUID) {
        let name = library.list(id)?.name ?? ""
        if viewingPlaylistID == id { viewPlaylist(nil) }
        withAnimation(Motion.panel) { _ = library.delete(id) }
        asksDeletePlaylist = nil
        saveLibraryNow()
        showHUD("trash", "已删除歌单「\(name)」")
    }

    func addToPlaylist(_ items: [MediaItem], _ id: UUID) {
        let n = withAnimation(Motion.panel) { library.add(items, to: id) }
        scheduleLibrarySave()
        let name = library.list(id)?.name ?? ""
        showHUD("text.badge.plus", n == 0 ? "「\(name)」里已经有了" : "已加入「\(name)」\(n > 1 ? "：\(n) 首" : "")")
    }
    func removeFromPlaylist(row: Int, _ id: UUID) {
        withAnimation(Motion.panel) { library.remove(at: row, from: id) }
        scheduleLibrarySave()
    }
    func movePlaylistRows(from: IndexSet, to: Int, _ id: UUID) {
        guard let f = from.first else { return }
        withAnimation(Motion.panel) { library.move(from: f, to: to, in: id) }
        scheduleLibrarySave()
    }

    /// 在歌单里双击一首：把这个歌单换进播放列表，从这首开始播
    func playUserPlaylist(_ id: UUID, from row: Int) {
        guard let p = library.list(id), p.items.indices.contains(row) else { return }
        withAnimation(Motion.panel) {
            engine.stop()
            queue.replace(with: p.items, startAt: row)
            syncCarouselCount()
        }
        for it in p.items.prefix(24) { ensureDetails(it) }
        play(index: row, from: 0)
        showHUD("music.note.list", "播放歌单「\(p.name)」")
        scheduleSave()
    }

    /// 歌单添加歌曲（歌单页的「添加歌曲…」「添加文件夹…」）
    func addSongsToViewedPlaylist(folders: Bool) {
        guard let id = viewingPlaylistID else { addSongs(folders: folders); return }
        let urls: [URL]
        if let t = TestHooks.openPanel(folders: folders) { urls = t } else {
            let p = NSOpenPanel()
            p.canChooseFiles = !folders; p.canChooseDirectories = folders; p.allowsMultipleSelection = true
            p.prompt = "加入歌单"
            guard p.runModal() == .OK else { return }
            urls = p.urls
        }
        let items = Self.expand(urls).map { MediaItem(url: $0) }
        guard !items.isEmpty else { return }
        addToPlaylist(items, id)
        for it in items.prefix(24) { ensureDetails(it) }
    }

    // MARK: - 主题排序
    func moveTheme(_ t: AppTheme, onto target: AppTheme) {
        let o = ThemeOrder.move(themeOrder, t, onto: target)
        guard o != themeOrder else { return }
        withAnimation(Motion.panel) { themeOrder = o }
        Prefs.set(ThemeOrder.rawValues(o), "themeOrder")
    }
    func beginThemeReorder() { guard !isReorderingThemes else { return }; withAnimation(Motion.panel) { isReorderingThemes = true } }
    func endThemeReorder() { guard isReorderingThemes else { return }; withAnimation(Motion.panel) { isReorderingThemes = false } }

    // MARK: - 生成封面：换一张
    func isGeneratedCover(index i: Int) -> Bool {
        guard queue.items.indices.contains(i), queue.items[i].kind == .audio else { return false }
        let id = queue.items[i].id
        return !hasFileCover(id) && coverInfo[id] == nil && (covers.art(for: id)?.isGenerated ?? true)
    }
    /// 右键「换一张生成封面」：本地程序随机重画（同一张专辑一起换），记住结果
    func rerollCover(index i: Int) {
        guard isGeneratedCover(index: i) else { showHUD("photo", "这张用的是真实封面"); return }
        let it = details[queue.items[i].id]?.item ?? queue.items[i]
        let base = it.baseCoverSeed
        let book = CoverRerolls.shared.reroll(base)
        try? CoverRerollBook.save(book, to: rerollURL)
        let same = queue.items.map { details[$0.id]?.item ?? $0 }.filter { $0.baseCoverSeed == base && !hasFileCover($0.id) && coverInfo[$0.id] == nil }
        for m in same {
            let st = defaultStyle(for: m)
            Task { [weak self] in
                let art = await Task.detached(priority: .userInitiated) { await CoverStore.makeArtGated(cover: nil, item: m, style: st) }.value
                guard let self, !self.hasFileCover(m.id), self.coverInfo[m.id] == nil else { return }
                self.applyCover(art, for: m.id)
            }
        }
        showHUD("dice", "换了一张封面")
    }

    // MARK: - 属性卡（播放列表行翻面）
    func toggleProperties(_ id: String) {
        if flippedRowID == id { closeProperties(); return }
        withAnimation(Motion.lift) { flippedRowID = id }
        loadProperties(id)
    }
    func closeProperties() { guard flippedRowID != nil else { return }; withAnimation(Motion.lift) { flippedRowID = nil } }

    func loadProperties(_ id: String) {
        if fileProperties[id] != nil { return }
        if let cached = details[id]?.properties { fileProperties[id] = cached; return }
        guard let it = queue.items.first(where: { $0.id == id }) ?? viewingPlaylist?.items.first(where: { $0.id == id }) else { return }
        let item = details[id]?.item ?? it
        Task.detached(priority: .userInitiated) { [weak self] in
            let p = Self.readProperties(item)
            await MainActor.run { self?.fileProperties[id] = p }
        }
    }

    nonisolated static func readProperties(_ it: MediaItem) -> FileProperties {
        buildProperties(from: FFmpegProbe.probe(it.url), item: it)
    }

    nonisolated static func buildProperties(from p: FFmpegProbe.Result?, item it: MediaItem) -> FileProperties {
        var rows: [(String, String)] = []
        var tags: [String: String] = [:]
        if let p {
            tags = p.tags
            if let a = p.audio {
                var s = a.codec.uppercased()
                if a.sampleRate > 0 { s += " · \(String(format: "%g", Double(a.sampleRate) / 1000)) kHz" }
                if a.bitDepth > 0 { s += " · \(a.bitDepth) bit" }
                if a.channels > 0 { s += a.channels == 1 ? " · 单声道" : (a.channels == 2 ? " · 立体声" : " · \(a.channels) 声道") }
                rows.append(("音频", s))
                if a.bitRate > 0 { rows.append(("码率", "\(a.bitRate / 1000) kbps")) }
            }
            if let v = p.video { rows.append(("视频", "\(v.codec.uppercased()) · \(v.width)×\(v.height)")) }
            if let d = p.duration { rows.append(("时长", TimeFormat.clock(d))) }
        }
        if it.url.isFileURL, let a = try? FileManager.default.attributesOfItem(atPath: it.url.path) {
            if let n = (a[.size] as? NSNumber)?.int64Value { rows.append(("大小", ByteCountFormatter.string(fromByteCount: n, countStyle: .file))) }
            if let m = a[.modificationDate] as? Date {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm"
                rows.append(("修改", f.string(from: m)))
            }
            rows.append(("位置", (it.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath))
        }
        if let custom = CustomTags.shared.entry(for: it.url) {
            tags = custom.applying(to: tags)
        }
        return FileProperties(rows: rows, tags: tags)
    }

    // MARK: - 改标签（支持全部本地音频格式：MP3/FLAC/M4A 写回文件，其它格式安全存入本地标签库）
    static let embeddedTagExtensions: Set<String> = TagWriter.supportedExtensions.union(["m4a"])
    static let tagEditableExtensions: Set<String> = embeddedTagExtensions
    func writesEmbeddedTags(_ it: MediaItem) -> Bool { it.url.isFileURL && it.kind == .audio && Self.embeddedTagExtensions.contains(it.url.pathExtension.lowercased()) }
    func canEditTags(_ it: MediaItem) -> Bool { it.url.isFileURL && it.kind == .audio }

    func openTagEditor(_ id: String) {
        withAnimation(Motion.panel) { tagEditorItemID = id }
        if fileProperties[id] == nil { loadProperties(id) }
    }
    func closeTagEditor() { guard tagEditorItemID != nil, !tagSaving else { return }; withAnimation(Motion.panel) { tagEditorItemID = nil } }

    func item(withID id: String) -> MediaItem? {
        details[id]?.item ?? queue.items.first { $0.id == id } ?? library.lists.lazy.flatMap(\.items).first { $0.id == id }
    }

    /// 保存：MP3 / FLAC 按字节重写（M4A 无损封装），先备份并校验音频数据；
    /// 其它音频格式（WAV / AIFF / OGG / OPUS / APE / AAC / DSD 等）或只读文件无损记入本地标签与封面侧车库。
    func saveTags(_ id: String, _ edit: TagEdit) {
        guard let it = item(withID: id), canEditTags(it), !tagSaving else { return }
        guard !edit.isEmpty else { closeTagEditor(); return }
        tagSaving = true
        let url = it.url, backupDir = tagBackupDir!, tagsURL = customTagsURL!
        let embedded = writesEmbeddedTags(it)
        Task { [weak self] in
            enum SaveOutcome: Sendable { case embedded(URL), sidecar }
            let result: Result<SaveOutcome, Error> = await Task.detached(priority: .userInitiated) {
                do {
                    if embedded {
                        do {
                            let ext = url.pathExtension.lowercased()
                            let backup: URL
                            if ext == "m4a" {
                                backup = try await MP4TagWriter.write(url, edit: edit, backupDir: backupDir)
                            } else {
                                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                                let out = try TagWriter.rewrite(data, ext: ext, edit: edit)
                                backup = try TagWriter.safeReplace(url, with: out, backupDir: backupDir)
                            }
                            let book = CustomTags.shared.clear(for: url)
                            try? CustomTagBook.save(book, to: tagsURL)
                            return .success(.embedded(backup))
                        } catch TagWriteError.unsafeTag, TagWriteError.unsupported {
                            // 容器结构少见时自动降级到本地侧车标签库，绝不损坏原文件也绝不让编辑失效
                            let book = try CustomTags.shared.apply(edit, for: url)
                            try CustomTagBook.save(book, to: tagsURL)
                            return .success(.sidecar)
                        }
                    } else {
                        let book = try CustomTags.shared.apply(edit, for: url)
                        try CustomTagBook.save(book, to: tagsURL)
                        return .success(.sidecar)
                    }
                } catch { return .failure(error) }
            }.value
            guard let self else { return }
            self.tagSaving = false
            switch result {
            case .success(.embedded(let backup)):
                TestHooks.log("  标签已写入「\(url.lastPathComponent)」，原文件备份 \(backup.path)")
                self.reloadAfterTagEdit(id)
                withAnimation(Motion.panel) { self.tagEditorItemID = nil }
                self.showHUD("checkmark.circle", "已写入文件（原文件已备份）")
            case .success(.sidecar):
                TestHooks.log("  标签已记入本地标签库「\(url.lastPathComponent)」")
                self.reloadAfterTagEdit(id)
                withAnimation(Motion.panel) { self.tagEditorItemID = nil }
                self.showHUD("checkmark.circle", "已保存 ID3 与封面")
            case .failure(let e):
                TestHooks.log("✗ 标签没写：\(e)")
                self.showHUD("exclamationmark.triangle", (e as? TagWriteError)?.description ?? "没保存：\(e.localizedDescription)")
            }
        }
    }

    /// 改完标签：重读这首的信息和封面，队列 / 歌单里同一首一起更新
    func reloadAfterTagEdit(_ id: String) {
        guard let base = item(withID: id) else { return }
        details[id] = nil
        fileCoverIDs.remove(id)
        coverTried.remove(id)
        fileProperties[id] = nil
        forgetDisplayedCover(id)
        var fresh = base
        fresh.title = MediaItem.titleFromFilename(base.url); fresh.artist = nil; fresh.album = nil; fresh.trackNumber = nil
        ensureDetails(fresh)
        loadProperties(id)
        _ = after(1.2) { [weak self] in
            guard let self, let d = self.details[id] else { return }
            self.library.refresh(d.item)
            self.scheduleLibrarySave()
            self.loadProperties(id)
            self.scheduleSave()
        }
    }
}

/// M4A：用 AVFoundation 无损封装（passthrough，不重新编码），换掉标签和封面；其余元数据原样带过去。
enum MP4TagWriter {
    static func write(_ url: URL, edit: TagEdit, backupDir: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let old = (try? await asset.load(.metadata)) ?? []
        var edited: Set<AVMetadataIdentifier> = []
        var add: [AVMetadataItem] = []
        func text(_ id: AVMetadataIdentifier, _ v: String?) {
            guard let v else { return }
            edited.insert(id)
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return }
            let m = AVMutableMetadataItem(); m.identifier = id; m.value = t as NSString; m.extendedLanguageTag = "und"
            add.append(m)
        }
        text(.iTunesMetadataSongName, edit.title)
        text(.iTunesMetadataArtist, edit.artist)
        text(.iTunesMetadataAlbum, edit.album)
        text(.iTunesMetadataAlbumArtist, edit.albumArtist)
        text(.iTunesMetadataReleaseDate, edit.year)
        text(.iTunesMetadataUserGenre, edit.genre)
        if let tr = edit.track {
            edited.insert(.iTunesMetadataTrackNumber)
            if let n = Int(tr.split(separator: "/").first ?? "") {
                let total = Int(tr.split(separator: "/").dropFirst().first ?? "") ?? 0
                let m = AVMutableMetadataItem(); m.identifier = .iTunesMetadataTrackNumber
                m.value = Data([0, 0, UInt8(n >> 8), UInt8(n & 0xFF), UInt8(total >> 8), UInt8(total & 0xFF), 0, 0]) as NSData
                m.dataType = kCMMetadataBaseDataType_RawData as String
                add.append(m)
            }
        }
        switch edit.cover {
        case .keep: break
        case .remove: edited.insert(.iTunesMetadataCoverArt)
        case .set(let d, let mime):
            edited.insert(.iTunesMetadataCoverArt)
            let m = AVMutableMetadataItem(); m.identifier = .iTunesMetadataCoverArt; m.value = d as NSData
            m.dataType = (mime == "image/png" ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG) as String
            add.append(m)
        }
        let keep = old.filter { m in
            guard let id = m.identifier else { return true }
            if edited.contains(id) { return false }
            // 同一项的通用写法（common key）也一起换掉，免得新旧两份打架
            if edit.title != nil, m.commonKey == .commonKeyTitle { return false }
            if edit.artist != nil, m.commonKey == .commonKeyArtist { return false }
            if edit.album != nil, m.commonKey == .commonKeyAlbumName { return false }
            if edit.cover != .keep, m.commonKey == .commonKeyArtwork { return false }
            return true
        }
        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else { throw TagWriteError.unsupported("m4a") }
        ex.metadata = keep + add
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent).liuli-\(UUID().uuidString.prefix(8)).m4a")
        do { try await ex.export(to: tmp, as: .m4a) } catch { try? FileManager.default.removeItem(at: tmp); throw error }
        // 核对：时长一致、音轨数一致（passthrough 不重新编码）
        let a0 = try await asset.load(.duration).seconds, n0 = try await asset.loadTracks(withMediaType: .audio).count
        let out = AVURLAsset(url: tmp)
        let a1 = try await out.load(.duration).seconds, n1 = try await out.loadTracks(withMediaType: .audio).count
        guard abs(a0 - a1) < 0.05, n0 == n1 else { try? FileManager.default.removeItem(at: tmp); throw TagWriteError.verifyFailed }
        let data = try Data(contentsOf: tmp, options: .mappedIfSafe)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try TagWriter.safeReplace(url, with: data, backupDir: backupDir)
    }
}
