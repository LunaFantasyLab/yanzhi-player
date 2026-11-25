// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 用户自己的歌单（TANCO 2026-11-23）：退出再打开还在；和「播放记录」分开，记录照旧只读。
/// 存在 ~/Library/Application Support/GlassPlayer/playlists.json（自测时跟着 -sessionPath 放到测试目录）。
public struct UserPlaylist: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var items: [MediaItem]
    public var createdAt: Date
    public init(id: UUID = UUID(), name: String, items: [MediaItem], createdAt: Date = Date()) {
        // 只记到整秒：存进 JSON 再读回来完全一样（毫秒在浮点往返里会有误差）
        self.id = id; self.name = name; self.items = items; self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
    }
    public var totalDuration: Double { items.compactMap(\.duration).reduce(0, +) }
}

public struct PlaylistLibrary: Codable, Equatable, Sendable {
    public var version = 1
    public var lists: [UserPlaylist] = []
    public init() {}

    public static let maxNameLength = 40

    public func index(of id: UUID) -> Int? { lists.firstIndex { $0.id == id } }
    public func list(_ id: UUID) -> UserPlaylist? { index(of: id).map { lists[$0] } }

    /// 「歌单 1」「歌单 2」…取第一个没用过的
    public func defaultName() -> String {
        let used = Set(lists.map(\.name))
        var n = 1
        while used.contains("歌单 \(n)") { n += 1 }
        return "歌单 \(n)"
    }

    /// 名字整理：去掉首尾空白和换行，过长截断；空的返回 nil
    public static func clean(_ s: String) -> String? {
        let t = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return String(t.prefix(maxNameLength))
    }

    /// 新建（同一首只放一次）；返回新歌单 id
    @discardableResult
    public mutating func create(name: String? = nil, items: [MediaItem] = [], now: Date = Date()) -> UUID {
        var seen = Set<String>()
        let unique = items.filter { seen.insert($0.id).inserted }
        let p = UserPlaylist(name: name.flatMap(Self.clean) ?? defaultName(), items: unique, createdAt: now)
        lists.append(p)
        return p.id
    }

    /// 改名：空名字不改，返回是否改了
    @discardableResult
    public mutating func rename(_ id: UUID, to name: String) -> Bool {
        guard let i = index(of: id), let n = Self.clean(name), n != lists[i].name else { return false }
        lists[i].name = n
        return true
    }

    /// 删歌单（不碰磁盘上的音乐文件）
    @discardableResult
    public mutating func delete(_ id: UUID) -> UserPlaylist? {
        guard let i = index(of: id) else { return nil }
        return lists.remove(at: i)
    }

    /// 加歌：已经在里面的不重复加，返回实际加了几首
    @discardableResult
    public mutating func add(_ items: [MediaItem], to id: UUID) -> Int {
        guard let i = index(of: id) else { return 0 }
        var have = Set(lists[i].items.map(\.id))
        var n = 0
        for it in items where have.insert(it.id).inserted { lists[i].items.append(it); n += 1 }
        return n
    }

    public mutating func remove(at row: Int, from id: UUID) {
        guard let i = index(of: id), lists[i].items.indices.contains(row) else { return }
        lists[i].items.remove(at: row)
    }

    /// 歌单里拖动排序（to 是插入点，和 List.onMove 一致）
    public mutating func move(from: Int, to: Int, in id: UUID) {
        guard let i = index(of: id), lists[i].items.indices.contains(from), to >= 0, to <= lists[i].items.count else { return }
        let it = lists[i].items.remove(at: from)
        lists[i].items.insert(it, at: to > from ? to - 1 : to)
    }

    /// 标签改了之后，同一路径的条目一起换成新信息
    public mutating func refresh(_ item: MediaItem) {
        for i in lists.indices { for j in lists[i].items.indices where lists[i].items[j].id == item.id { lists[i].items[j] = item } }
    }
}

public enum PlaylistLibraryStore {
    public static let fileName = "playlists.json"

    /// 读不出来（文件坏了）时：把坏文件改名留着（.damaged-时间），返回空库，绝不在原文件上覆盖
    public static func load(from url: URL) -> PlaylistLibrary {
        guard let data = try? Data(contentsOf: url) else { return PlaylistLibrary() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        if let lib = try? dec.decode(PlaylistLibrary.self, from: data) { return lib }
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let aside = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".damaged-" + f.string(from: Date()) + ".json")
        try? FileManager.default.moveItem(at: url, to: aside)
        return PlaylistLibrary()
    }

    public static func save(_ lib: PlaylistLibrary, to url: URL) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        enc.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try enc.encode(lib)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
