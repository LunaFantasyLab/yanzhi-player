// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import XCTest
@testable import PlayerCore

/// 2026-11-23 七项改版：持久化（歌单 / 队列恢复 / 封面重生成）、主题排序、标签写入、耳机品牌目录
final class SevenItemsTests: XCTestCase {
    private func tmp(_ name: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("liuli-7-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent(name)
    }
    private func item(_ n: String) -> MediaItem { MediaItem(url: URL(fileURLWithPath: "/tmp/liuli-7/\(n).mp3"), title: n) }

    // MARK: 主题排序
    func testThemeDefaultOrderPutsFollowCoverNextToSystemThenWhiteBlack() {
        let o = ThemeOrder.defaultOrder
        XCTAssertEqual(Array(o.prefix(4)), [.system, .followCover, .white, .black])
        XCTAssertEqual(Set(o), Set(AppTheme.allCases))
        XCTAssertEqual(o.count, AppTheme.allCases.count)
    }
    func testThemeReorderOnlyMovesNeverDeletes() {
        var o = ThemeOrder.defaultOrder
        o = ThemeOrder.move(o, .liuli, onto: .system)
        XCTAssertEqual(o.first, .liuli)
        XCTAssertEqual(o[1], .system)
        o = ThemeOrder.move(o, .system, onto: .smoke)
        XCTAssertEqual(Set(o), Set(AppTheme.allCases), "排序不能丢主题")
        XCTAssertEqual(o.count, AppTheme.allCases.count)
        XCTAssertEqual(ThemeOrder.move(o, .liuli, onto: .liuli), o)
    }
    func testThemeOrderPersistsAndHealsUnknownOrMissing() {
        var o = ThemeOrder.move(ThemeOrder.defaultOrder, .celadon, onto: .system)
        let saved = ThemeOrder.rawValues(o)
        XCTAssertEqual(ThemeOrder.resolve(saved: saved), o, "保存再读回顺序不变")
        // 存档里有不认识的、重复的、缺的
        let messy = ["celadon", "bogus", "celadon", "system"]
        o = ThemeOrder.resolve(saved: messy)
        // 存档里有的两个保持先后（青瓷在系统默认前面），缺的按默认邻居补回
        XCTAssertEqual(o.first, .celadon)
        XCTAssertLessThan(o.firstIndex(of: .celadon)!, o.firstIndex(of: .system)!)
        XCTAssertEqual(o[o.firstIndex(of: .system)! + 1], .followCover, "缺的「跟随封面」补在它默认的邻居「系统默认」后面")
        XCTAssertEqual(Set(o), Set(AppTheme.allCases))
        XCTAssertEqual(o.count, AppTheme.allCases.count)
        XCTAssertEqual(ThemeOrder.resolve(saved: nil), ThemeOrder.defaultOrder)
    }

    // MARK: 歌单
    func testPlaylistCreateRenameDeleteAndPersist() throws {
        var lib = PlaylistLibrary()
        let a = lib.create(items: [item("a"), item("b"), item("a")])
        XCTAssertEqual(lib.list(a)?.name, "歌单 1")
        XCTAssertEqual(lib.list(a)?.items.map(\.title), ["a", "b"], "同一首只放一次")
        let b = lib.create(name: "  书房  ")
        XCTAssertEqual(lib.list(b)?.name, "书房")
        XCTAssertEqual(lib.defaultName(), "歌单 2")
        XCTAssertFalse(lib.rename(a, to: "   "), "空名字不改")
        XCTAssertTrue(lib.rename(a, to: "夜跑"))
        XCTAssertEqual(lib.add([item("b"), item("c")], to: a), 1)
        lib.move(from: 2, to: 0, in: a)
        XCTAssertEqual(lib.list(a)?.items.map(\.title), ["c", "a", "b"])
        lib.remove(at: 1, from: a)
        XCTAssertEqual(lib.list(a)?.items.map(\.title), ["c", "b"])

        let url = tmp(PlaylistLibraryStore.fileName)
        try PlaylistLibraryStore.save(lib, to: url)
        let back = PlaylistLibraryStore.load(from: url)
        XCTAssertEqual(back, lib, "退出再打开，歌单原样还在")
        XCTAssertNotNil(lib.delete(b))
        XCTAssertEqual(lib.lists.map(\.name), ["夜跑"])
    }
    func testDamagedPlaylistFileIsKeptAsideNotOverwritten() throws {
        let url = tmp(PlaylistLibraryStore.fileName)
        try Data("{ 这不是 JSON".utf8).write(to: url)
        let lib = PlaylistLibraryStore.load(from: url)
        XCTAssertTrue(lib.lists.isEmpty)
        let siblings = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
        XCTAssertTrue(siblings.contains { $0.contains(".damaged-") }, "坏文件改名留着，不被下次保存覆盖")
    }
    func testLaunchRestoresQueueWithoutAutoplayPosition() {
        var saved = SessionState()
        saved.queue.replace(with: [item("x"), item("y")], startAt: 1)
        saved.queue.repeatMode = .one
        saved.lastPosition = 88
        saved.volume = 40
        let s = LaunchPolicy.preparedSession(from: saved)
        XCTAssertEqual(s.queue.items.map(\.title), ["x", "y"], "打开时恢复播放列表")
        XCTAssertEqual(s.queue.currentIndex, 1)
        XCTAssertEqual(s.queue.repeatMode, .one)
        XCTAssertEqual(s.lastPosition, 0, "不带上次进度、不自动播放")
        XCTAssertEqual(s.volume, 40)
    }

    // MARK: 生成封面换一张
    func testCoverRerollChangesSeedAndPersists() throws {
        var book = CoverRerollBook()
        let base = "album|海边|琉璃样曲"
        XCTAssertEqual(book.seed(for: base), base)
        let s1 = book.reroll(base)
        XCTAssertNotEqual(s1, base)
        let s2 = book.reroll(base)
        XCTAssertNotEqual(s1, s2, "每次都换成不一样的")
        XCTAssertNotEqual(DefaultCoverSpec.make(seed: base), DefaultCoverSpec.make(seed: s2))
        let url = tmp("cover-rerolls.json")
        try CoverRerollBook.save(book, to: url)
        XCTAssertEqual(CoverRerollBook.load(from: url).seed(for: base), s2, "重新打开还是这一张")
        let shared = CoverRerolls()
        shared.set(book)
        XCTAssertEqual(shared.seed(for: base), s2)
        XCTAssertEqual(shared.seed(for: "track|别的|歌"), "track|别的|歌")
    }

    // MARK: 标签写入
    private func fakeMP3(tag: Data? = nil) -> Data {
        var audio = Data()
        for i in 0..<4000 { audio.append(UInt8((i * 37 + 11) & 0xFF)) }
        audio.append(contentsOf: Array("TAG".utf8)); audio.append(Data(count: 125))      // 末尾 ID3v1 原样保留
        return (tag ?? Data()) + audio
    }
    private func v23Tag(_ frames: [Data]) -> Data {
        let body = frames.reduce(Data(), +) + Data(count: 16)
        return Data([0x49, 0x44, 0x33, 3, 0, 0]) + Data(ID3Writer.syncsafeBytes(body.count)) + body
    }
    func testID3RewriteKeepsAudioBytesAndUnknownFrames() throws {
        let priv = ID3Writer.header("PRIV", 5, major: 3) + Data([1, 2, 3, 4, 5])
        let oldTitle = ID3Writer.textFrame("TIT2", "旧名字", major: 3)
        let src = fakeMP3(tag: v23Tag([oldTitle, priv]))
        let jpg = Data([0xFF, 0xD8, 0xFF, 0xE0, 9, 9, 9, 0xFF, 0xD9])
        let out = try TagWriter.rewrite(src, ext: "mp3", edit: TagEdit(title: "新名字", artist: "琉璃样曲", year: "2026", cover: .set(jpg, mime: "image/jpeg")))
        XCTAssertEqual(try ID3Writer.payload(out), try ID3Writer.payload(src), "音频数据一个字节都不能变")
        let t = try ID3Writer.readText(out)
        XCTAssertEqual(t["TIT2"], "新名字")
        XCTAssertEqual(t["TPE1"], "琉璃样曲")
        XCTAssertEqual(t["TYER"], "2026")
        XCTAssertTrue(try ID3Writer.hasFrontCover(out))
        XCTAssertNotNil(out.range(of: Data(Array("PRIV".utf8)) + ID3Writer.be32Bytes(5).data), "不认识的帧原样保留")
        // 删掉封面、清空艺人
        let out2 = try TagWriter.rewrite(out, ext: "mp3", edit: TagEdit(artist: "", cover: .remove))
        XCTAssertFalse(try ID3Writer.hasFrontCover(out2))
        XCTAssertNil(try ID3Writer.readText(out2)["TPE1"])
        XCTAssertEqual(try ID3Writer.readText(out2)["TIT2"], "新名字")
        XCTAssertEqual(try ID3Writer.payload(out2), try ID3Writer.payload(src))
    }
    func testID3OnFileWithoutTagAndRefusesUnsafeTag() throws {
        let src = fakeMP3()
        let out = try TagWriter.rewrite(src, ext: "mp3", edit: TagEdit(title: "无标签的歌"))
        XCTAssertEqual(try ID3Writer.payload(out), src)
        XCTAssertEqual(try ID3Writer.readText(out)["TIT2"], "无标签的歌")
        var unsync = v23Tag([])
        unsync[5] = 0x80
        XCTAssertThrowsError(try TagWriter.rewrite(fakeMP3(tag: unsync), ext: "mp3", edit: TagEdit(title: "x"))) { e in
            XCTAssertEqual(e as? TagWriteError, .unsafeTag("整体反同步"))
        }
        XCTAssertThrowsError(try TagWriter.rewrite(src, ext: "ogg", edit: TagEdit(title: "x")))
    }
    private func fakeFLAC() -> Data {
        var d = Data([0x66, 0x4C, 0x61, 0x43])
        d.append(contentsOf: [0x00, 0, 0, 34]); d.append(Data((0..<34).map { UInt8($0) }))       // STREAMINFO
        let vc = FLACWriter.commentBlock(vendor: "reference libFLAC", ["TITLE=旧", "COMMENT=保留我"])
        d.append(contentsOf: [0x04, 0, UInt8(vc.count >> 8), UInt8(vc.count & 0xFF)]); d.append(vc)
        d.append(contentsOf: [0x02, 0, 0, 4]); d.append(Data([7, 7, 7, 7]))                         // APPLICATION
        d.append(contentsOf: [0x81, 0, 0, 8]); d.append(Data(count: 8))                             // PADDING（最后一块）
        for i in 0..<5000 { d.append(UInt8((i * 13) & 0xFF)) }
        return d
    }
    func testFLACRewriteKeepsAudioAndOtherBlocks() throws {
        let src = fakeFLAC()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let out = try TagWriter.rewrite(src, ext: "flac", edit: TagEdit(title: "潮汐", album: "样曲集", track: "2", cover: .set(png, mime: "image/png")))
        XCTAssertEqual(try FLACWriter.payload(out), try FLACWriter.payload(src))
        let c = try FLACWriter.readComments(out)
        XCTAssertEqual(c["TITLE"], "潮汐")
        XCTAssertEqual(c["ALBUM"], "样曲集")
        XCTAssertEqual(c["TRACKNUMBER"], "2")
        XCTAssertEqual(c["COMMENT"], "保留我", "没改的字段原样保留")
        XCTAssertTrue(try FLACWriter.hasFrontCover(out))
        XCTAssertNotNil(out.range(of: Data([0x02, 0, 0, 4, 7, 7, 7, 7])), "APPLICATION 块原样保留")
        let blocks = try FLACWriter.parse(out).blocks
        XCTAssertEqual(blocks.first?.type, 0)
        let out2 = try TagWriter.rewrite(out, ext: "flac", edit: TagEdit(cover: .remove))
        XCTAssertFalse(try FLACWriter.hasFrontCover(out2))
        XCTAssertEqual(try FLACWriter.payload(out2), try FLACWriter.payload(src))
    }
    func testSafeReplaceKeepsBackupOfOriginal() throws {
        let url = tmp("歌.mp3")
        let src = fakeMP3()
        try src.write(to: url)
        let out = try TagWriter.rewrite(src, ext: "mp3", edit: TagEdit(title: "备份测试"))
        let backupDir = url.deletingLastPathComponent().appendingPathComponent("tag-backups")
        let backup = try TagWriter.safeReplace(url, with: out, backupDir: backupDir)
        XCTAssertEqual(try Data(contentsOf: backup), src, "原文件整份备份")
        XCTAssertEqual(try Data(contentsOf: url), out)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty, "不留临时文件")
    }

    // MARK: 耳机品牌
    func testAutoEqBrandGrouping() {
        let names = ["Sennheiser HD 600", "Sennheiser HD 650", "64 Audio U12t", "Bang & Olufsen Beoplay H95", "Dan Clark Audio Stealth",
                     "Apple AirPods Pro", "Apple AirPods Max", "HiFiMAN Sundara", "HIFIMAN Arya", "HIFIMAN Edition XS", "Nothing ear (1)", "Tin HiFi T2"]
        let es = names.enumerated().map { AutoEq.Entry(name: $1, source: "crinacle", rig: nil, path: "crinacle/x/\($0)") }
        XCTAssertEqual(AutoEq.brand(of: "64 Audio U12t"), "64 Audio")
        XCTAssertEqual(AutoEq.brand(of: "Bang & Olufsen Beoplay H95"), "Bang & Olufsen")
        XCTAssertEqual(AutoEq.brand(of: "Dan Clark Audio Stealth"), "Dan Clark Audio")
        XCTAssertEqual(AutoEq.brand(of: "Nothing ear (1)"), "Nothing")
        let idx = AutoEq.brandIndex(es)
        XCTAssertEqual(idx.major.map(\.name).prefix(2), ["Apple", "Sennheiser"])
        XCTAssertEqual(idx.letters.last, "#", "数字开头的品牌归到 #，排最后")
        let h = idx.sections.first { $0.letter == "H" }?.brands
        XCTAssertEqual(h?.count, 1, "大小写不同的同一品牌合并")
        XCTAssertEqual(h?.first?.name, "HIFIMAN")
        XCTAssertEqual(h?.first?.count, 3)
        let apple = AutoEq.models(es, brand: "Apple")
        XCTAssertEqual(apple.map { AutoEq.modelName($0, brand: "Apple") }, ["AirPods Max", "AirPods Pro"])
    }

    // MARK: 均衡器 32 路实时频谱分析
    func testAudioSpectrumTracksLowAndHighFrequencies() {
        let sr = 22050
        let count = sr * 2
        // 前 1 秒 120 Hz 低频正弦，后 1 秒 4000 Hz 高频正弦
        var mono = [Float](repeating: 0, count: count)
        for i in 0..<count {
            let f: Float = i < sr ? 120 : 4000
            mono[i] = sin(2 * .pi * f * Float(i) / Float(sr)) * 0.8
        }
        let spec = AudioSpectrum.analyze(mono: mono, sampleRate: sr)
        XCTAssertEqual(AudioSpectrum.defaultFPS, 120.0, "频谱分析采样率必须不低于 120 fps")
        XCTAssertGreaterThan(spec.frameCount, 200)
        let low = spec.sample(at: 0.45)
        let high = spec.sample(at: 1.55)
        XCTAssertEqual(low.count, 32)
        XCTAssertEqual(high.count, 32)
        let lowPeakIdx = low.enumerated().max(by: { $0.element < $1.element })!.offset
        let highPeakIdx = high.enumerated().max(by: { $0.element < $1.element })!.offset
        XCTAssertLessThan(lowPeakIdx, 12, "120 Hz 能量应落在低频左侧彩条")
        XCTAssertGreaterThan(highPeakIdx, 20, "4000 Hz 能量应落在高频右侧彩条")
    }

    // MARK: 全格式侧车 ID3 与封面编辑（WAV / AIFF / APE / OGG 等）
    func testCustomTagBookPersistsMetadataAndCoverOverrides() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("liuli-customtag-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let wavURL = dir.appendingPathComponent("demo.wav")
        let coverDir = dir.appendingPathComponent("custom-covers", isDirectory: true)
        let jsonURL = dir.appendingPathComponent("custom-tags.json")

        var book = CustomTagBook()
        let fakeCover = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let edit = TagEdit(title: "月光奏鸣曲", artist: "贝多芬", album: "钢琴独奏", albumArtist: "古典大师",
                           track: "1/3", year: "2026", genre: "Classical", cover: .set(fakeCover, mime: "image/jpeg"))
        try book.apply(edit, for: wavURL, coverDir: coverDir)
        try CustomTagBook.save(book, to: jsonURL)

        let reloaded = CustomTagBook.load(from: jsonURL)
        let entry = reloaded.entries[CustomTagBook.key(for: wavURL)]
        XCTAssertEqual(entry?.title, "月光奏鸣曲")
        XCTAssertEqual(entry?.artist, "贝多芬")
        XCTAssertEqual(entry?.album, "钢琴独奏")
        XCTAssertEqual(entry?.year, "2026")
        XCTAssertFalse(entry?.coverRemoved ?? true)
        XCTAssertNotNil(entry?.coverFile)
        if let cf = entry?.coverFile {
            XCTAssertEqual(try Data(contentsOf: coverDir.appendingPathComponent(cf)), fakeCover)
        }
        let merged = entry!.applying(to: ["title": "old", "comment": "keep"])
        XCTAssertEqual(merged["title"], "月光奏鸣曲")
        XCTAssertEqual(merged["comment"], "keep")
        XCTAssertEqual(merged["date"], "2026")
    }

    // MARK: 并行多核默认封面渲染一致性与完整性（覆盖全部 18 种风格 × 32 套色盘）
    func testParallelDefaultCoverRendererProducesValidRGBA() {
        XCTAssertEqual(DefaultCoverStyle.allCases.count, 18)
        XCTAssertGreaterThanOrEqual(DefaultCoverSpec.richPalettes.count, 32)
        let spec = DefaultCoverSpec.make(seed: "liuli-4k-test")
        let a = DefaultCoverRenderer.render(spec, style: .softGlass, size: 512)
        let b = DefaultCoverRenderer.render(spec, style: .softGlass, size: 512)
        XCTAssertEqual(a.count, 512 * 512 * 4)
        XCTAssertEqual(a, b, "多核并行渲染必须确定性一致")
        for st in DefaultCoverStyle.allCases where st != .softGlass {
            let px = DefaultCoverRenderer.render(spec, style: st, size: 128)
            XCTAssertEqual(px.count, 128 * 128 * 4, "风格 \(st.name) 输出字节数不符")
        }
    }
}

private extension Array where Element == UInt8 { var data: Data { Data(self) } }
