// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 记住每个文件播到哪里（文件路径 + 大小 + 修改时间 作为键，文件被替换后不会错位）。
public struct ResumeBook: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var position: Double
        public var duration: Double
        public var updatedAt: Date
    }
    public private(set) var entries: [String: Entry] = [:]
    public var maxEntries = 2000

    public init() {}

    public static func key(path: String, size: Int64?, modified: Date?) -> String {
        "\(path)|\(size ?? -1)|\(Int(modified?.timeIntervalSince1970 ?? 0))"
    }

    /// 规则：短于 3 分钟的音频不记（歌曲从头听更自然）；视频/长音频记；
    /// 离开头 < 10 秒或离结尾 < 15 秒（或已播 97%）视为“没开始/已看完”，清除记录。
    public mutating func record(key: String, position: Double, duration: Double, kind: MediaKind, now: Date = Date()) {
        guard duration.isFinite, duration > 0, position.isFinite else { return }
        let shortSong = kind == .audio && duration < 180
        if shortSong || position < 10 || duration - position < 15 || position / duration > 0.97 {
            entries[key] = nil
            return
        }
        entries[key] = Entry(position: position, duration: duration, updatedAt: now)
        if entries.count > maxEntries {
            let drop = entries.sorted { $0.value.updatedAt < $1.value.updatedAt }.prefix(entries.count - maxEntries)
            for (k, _) in drop { entries[k] = nil }
        }
    }

    public func position(for key: String) -> Double? { entries[key]?.position }
}

/// 整个 App 需要持久化的状态。
public struct SessionState: Codable, Equatable, Sendable {
    public var queue = PlayQueue()
    public var volume: Double = 80
    public var muted = false
    public var eq = EQState()
    public var customPresets: [EQPreset] = []
    public var resume = ResumeBook()
    /// 音乐继续上次的位置
    public var lastPosition: Double = 0
    public init() {}
}

public enum SessionStore {
    public static func load(from url: URL) -> SessionState {
        guard let data = try? Data(contentsOf: url) else { return SessionState() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return (try? dec.decode(SessionState.self, from: data)) ?? SessionState()
    }

    public static func save(_ s: SessionState, to url: URL) throws {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(s)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}


/// 启动策略：
/// - `resumeQueue == false`（默认「全新空白」）：首页「正在播放」以空白工程启动（显示添加文件 / 添加文件夹），
///   歌单（playlists.json）、播放记录、音量、静音、均衡器、预设、循环/随机偏好、续播书全部完好保留；
/// - `resumeQueue == true`（「延续上次」）：恢复上次的播放列表（不自动播放、不带上次进度）。
public enum LaunchPolicy {
    public static func preparedSession(from saved: SessionState, resumeQueue: Bool = true) -> SessionState {
        var s = SessionState()
        if resumeQueue {
            s.queue = saved.queue
        } else {
            var empty = PlayQueue()
            empty.repeatMode = saved.queue.repeatMode
            empty.setShuffle(saved.queue.shuffle)
            s.queue = empty
        }
        s.volume = saved.volume
        s.muted = saved.muted
        s.eq = saved.eq
        s.customPresets = saved.customPresets
        s.resume = saved.resume
        s.lastPosition = 0
        return s
    }

    /// 访达「打开方式」、拖到 Dock 图标、onOpenURL 带来的本地文件；冷启动清空工程之后仍应交予播放器，不得丢弃。
    public static func explicitOpenURLs(_ urls: [URL]) -> [URL] {
        urls.filter(\.isFileURL)
    }
}

/// LRC 歌词（同名 .lrc 或内嵌 LYRICS 标签）——中心卡翻面后显示，跟着播放进度滚动。
public struct Lyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable { public var time: Double; public var text: String }
    public var lines: [Line]
    public var isSynced: Bool

    public static func parse(_ text: String) -> Lyrics {
        var out: [Line] = []
        var offset = 0.0
        let tag = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.lowercased().hasPrefix("[offset:") {
                let v = line.dropFirst(8).dropLast().trimmingCharacters(in: .whitespaces)
                offset = (Double(v) ?? 0) / 1000
                continue
            }
            let ns = line as NSString
            let ms = tag.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard !ms.isEmpty else { continue }
            let body = ns.substring(from: ms.last!.range.location + ms.last!.range.length).trimmingCharacters(in: .whitespaces)
            for m in ms {
                let mm = Double(ns.substring(with: m.range(at: 1))) ?? 0
                let ss = Double(ns.substring(with: m.range(at: 2))) ?? 0
                var frac = 0.0
                if m.range(at: 3).location != NSNotFound {
                    let f = ns.substring(with: m.range(at: 3))
                    frac = (Double(f) ?? 0) / pow(10, Double(f.count))
                }
                out.append(Line(time: max(0, mm * 60 + ss + frac - offset), text: body))
            }
        }
        if out.isEmpty {
            let plain = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return Lyrics(lines: plain.map { Line(time: 0, text: $0) }, isSynced: false)
        }
        return Lyrics(lines: out.sorted { $0.time < $1.time }, isSynced: true)
    }

    /// 当前应高亮的行
    public func index(at t: Double) -> Int? {
        guard isSynced, !lines.isEmpty else { return nil }
        var lo = 0, hi = lines.count - 1, ans: Int? = nil
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lines[mid].time <= t { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }
}
