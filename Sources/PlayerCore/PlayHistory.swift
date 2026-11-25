// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 一条真实播放过的记录。用路径（或远程 URL 字符串）去重，不依赖临时 id。
public struct PlayHistoryItem: Codable, Equatable, Identifiable, Sendable {
    public var path: String
    public var title: String
    public var artist: String?
    public var playedAt: Date

    public var id: String { path }

    public init(path: String, title: String, artist: String? = nil, playedAt: Date) {
        self.path = path
        self.title = title
        self.artist = artist
        self.playedAt = playedAt
    }

    public init(url: URL, title: String, artist: String? = nil, playedAt: Date = Date()) {
        self.init(path: PlayHistoryBook.key(for: url), title: title, artist: artist, playedAt: playedAt)
    }

    public var url: URL {
        if path.hasPrefix("/"), !path.hasPrefix("//") { return URL(fileURLWithPath: path) }
        return URL(string: path) ?? URL(fileURLWithPath: path)
    }

    public var fileExists: Bool {
        url.isFileURL ? FileManager.default.fileExists(atPath: url.path) : true
    }
}

/// 与启动会话分离的播放历史：冷启动不会把它写进队列，也不会自动播放。
public struct PlayHistoryBook: Codable, Equatable, Sendable {
    public var items: [PlayHistoryItem]
    public static let limit = 100

    public init(items: [PlayHistoryItem] = []) { self.items = items }

    public static func key(for url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    /// 记一次真实播放：同一路径只保留一条，移到最前；超出上限丢掉最旧的。不改当前队列。
    public mutating func record(url: URL, title: String, artist: String?, at date: Date = Date()) {
        let path = Self.key(for: url)
        items.removeAll { $0.path == path }
        items.insert(PlayHistoryItem(path: path, title: title, artist: artist, playedAt: date), at: 0)
        if items.count > Self.limit { items = Array(items.prefix(Self.limit)) }
    }

    public mutating func remove(path: String) { items.removeAll { $0.path == path } }

    /// 只清空历史，不删文件、不动当前队列或其它偏好。
    public mutating func clear() { items = [] }
}

public enum PlayHistoryStore {
    public static let fileName = "play-history.json"

    public static func load(from url: URL) -> PlayHistoryBook {
        guard let data = try? Data(contentsOf: url) else { return PlayHistoryBook() }
        return (try? JSONDecoder().decode(PlayHistoryBook.self, from: data)) ?? PlayHistoryBook()
    }

    public static func save(_ book: PlayHistoryBook, to url: URL) throws {
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(book)
        try data.write(to: url, options: .atomic)
    }
}

/// 空工程仍保留顶栏与播放条；是否隐藏只跟 VideoLayout（沉浸视频等）走，不因队列为空而拆掉布局。
public enum EmptyProjectLayout {
    public static func showsApplicationHeader(queueIsEmpty: Bool, videoStageOpen: Bool, mini: Bool, nowPlaying: Bool) -> Bool {
        _ = queueIsEmpty
        return VideoLayout.showsApplicationHeader(videoStageOpen: videoStageOpen, mini: mini, nowPlaying: nowPlaying)
    }

    public static func showsPlayChrome(queueIsEmpty: Bool, videoStageOpen: Bool, mini: Bool, nowPlaying: Bool) -> Bool {
        _ = queueIsEmpty
        return VideoLayout.showsPlayChrome(videoStageOpen: videoStageOpen, mini: mini, nowPlaying: nowPlaying)
    }
}
