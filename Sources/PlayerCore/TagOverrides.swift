// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 全格式本地标签与封面侧车记录（2026-11-24）：
/// MP3 / FLAC / M4A 优先安全写回音频文件本身；WAV / AIFF / APE / OGG / OPUS / AAC / DSD 等其它音频格式
/// 或只读文件，统一无损保存在侧车 `custom-tags.json` + `custom-covers/` 中，保证所有音频都能编辑 ID3 信息与专辑封面。
public struct CustomTagEntry: Codable, Equatable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var track: String?
    public var year: String?
    public var genre: String?
    /// 存放在 custom-covers/ 下的自定义封面文件名（非 nil 表示覆盖封面）
    public var coverFile: String?
    /// 显式移除了封面（即使原文件或同目录有封面也不显示，改用默认封面）
    public var coverRemoved: Bool

    public init(title: String? = nil, artist: String? = nil, album: String? = nil, albumArtist: String? = nil,
                track: String? = nil, year: String? = nil, genre: String? = nil, coverFile: String? = nil, coverRemoved: Bool = false) {
        self.title = title
        self.artist = artist
        self.album = album
        self.albumArtist = albumArtist
        self.track = track
        self.year = year
        self.genre = genre
        self.coverFile = coverFile
        self.coverRemoved = coverRemoved
    }

    public var isEmpty: Bool {
        title == nil && artist == nil && album == nil && albumArtist == nil && track == nil && year == nil && genre == nil
            && coverFile == nil && !coverRemoved
    }

    /// 合并到已读取的标签字典（键名与 FFmpegProbe 一致：title/artist/album/album_artist/track/date/genre）
    public func applying(to tags: [String: String]) -> [String: String] {
        var out = tags
        func set(_ key: String, _ v: String?) {
            guard let v else { return }
            if v.isEmpty { out.removeValue(forKey: key) } else { out[key] = v }
        }
        set("title", title)
        set("artist", artist)
        set("album", album)
        set("album_artist", albumArtist)
        set("track", track)
        set("date", year)
        set("genre", genre)
        return out
    }
}

public struct CustomTagBook: Codable, Equatable, Sendable {
    public var entries: [String: CustomTagEntry] = [:]

    public init(entries: [String: CustomTagEntry] = [:]) {
        self.entries = entries
    }

    public static func key(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    public mutating func apply(_ edit: TagEdit, for url: URL, coverDir: URL) throws {
        let k = Self.key(for: url)
        var e = entries[k] ?? CustomTagEntry()
        if let v = edit.title { e.title = v }
        if let v = edit.artist { e.artist = v }
        if let v = edit.album { e.album = v }
        if let v = edit.albumArtist { e.albumArtist = v }
        if let v = edit.track { e.track = v }
        if let v = edit.year { e.year = v }
        if let v = edit.genre { e.genre = v }
        switch edit.cover {
        case .keep:
            break
        case .remove:
            if let old = e.coverFile { try? FileManager.default.removeItem(at: coverDir.appendingPathComponent(old)) }
            e.coverFile = nil
            e.coverRemoved = true
        case .set(let data, let mime):
            try FileManager.default.createDirectory(at: coverDir, withIntermediateDirectories: true)
            if let old = e.coverFile { try? FileManager.default.removeItem(at: coverDir.appendingPathComponent(old)) }
            let ext = mime.lowercased().contains("png") ? "png" : "jpg"
            let name = "\(DefaultCoverSpec.fnv1a64(k))-\(UInt64.random(in: 1...UInt64.max)).\(ext)"
            try data.write(to: coverDir.appendingPathComponent(name), options: .atomic)
            e.coverFile = name
            e.coverRemoved = false
        }
        if e.isEmpty { entries.removeValue(forKey: k) } else { entries[k] = e }
    }

    public mutating func clear(for url: URL, coverDir: URL) {
        let k = Self.key(for: url)
        if let old = entries.removeValue(forKey: k)?.coverFile {
            try? FileManager.default.removeItem(at: coverDir.appendingPathComponent(old))
        }
    }

    public static func load(from url: URL) -> CustomTagBook {
        guard let d = try? Data(contentsOf: url), let b = try? JSONDecoder().decode(CustomTagBook.self, from: d) else { return CustomTagBook() }
        return b
    }

    public static func save(_ book: CustomTagBook, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(book).write(to: url, options: .atomic)
    }
}

/// 进程内共享的侧车标签表（MetadataReader / FullCover / PlayerController 共用，线程安全）
public final class CustomTags: @unchecked Sendable {
    public static let shared = CustomTags()
    private let lock = NSLock()
    private var book = CustomTagBook()
    private var coverDir: URL?

    public func configure(book: CustomTagBook, coverDir: URL) {
        lock.lock(); defer { lock.unlock() }
        self.book = book
        self.coverDir = coverDir
    }

    public func entry(for url: URL) -> CustomTagEntry? {
        guard url.isFileURL else { return nil }
        lock.lock(); defer { lock.unlock() }
        return book.entries[CustomTagBook.key(for: url)]
    }

    public func coverData(for url: URL) -> Data? {
        guard url.isFileURL else { return nil }
        lock.lock()
        let file = book.entries[CustomTagBook.key(for: url)]?.coverFile
        let dir = coverDir
        lock.unlock()
        guard let file, let dir else { return nil }
        return try? Data(contentsOf: dir.appendingPathComponent(file))
    }

    @discardableResult
    public func apply(_ edit: TagEdit, for url: URL) throws -> CustomTagBook {
        lock.lock()
        let dir = coverDir ?? FileManager.default.temporaryDirectory.appendingPathComponent("liuli-custom-covers", isDirectory: true)
        var copy = book
        lock.unlock()
        try copy.apply(edit, for: url, coverDir: dir)
        lock.lock(); book = copy; lock.unlock()
        return copy
    }

    @discardableResult
    public func clear(for url: URL) -> CustomTagBook {
        lock.lock(); defer { lock.unlock() }
        let dir = coverDir ?? FileManager.default.temporaryDirectory.appendingPathComponent("liuli-custom-covers", isDirectory: true)
        book.clear(for: url, coverDir: dir)
        return book
    }
}
