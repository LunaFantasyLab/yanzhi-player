// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 改歌曲标签（ID3 / FLAC），纯本地、按字节重写（TANCO 2026-11-23）。
/// 原则：音频数据一个字节都不动——只重写文件开头的标签区，写完再核对「标签区之后的音频数据」和原文件逐字节相同，
/// 不同就不落盘；替换前先把原文件整份备份。不认识的标签帧 / 块原样保留。
public struct TagEdit: Equatable, Sendable {
    /// nil = 不改这一项；"" = 删掉这一项
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var track: String?
    public var year: String?
    public var genre: String?
    public var cover: CoverChange = .keep
    public init(title: String? = nil, artist: String? = nil, album: String? = nil, albumArtist: String? = nil,
                track: String? = nil, year: String? = nil, genre: String? = nil, cover: CoverChange = .keep) {
        self.title = title; self.artist = artist; self.album = album; self.albumArtist = albumArtist
        self.track = track; self.year = year; self.genre = genre; self.cover = cover
    }
    public enum CoverChange: Equatable, Sendable {
        case keep, remove
        case set(Data, mime: String)
    }
    public var isEmpty: Bool { [title, artist, album, albumArtist, track, year, genre].allSatisfy { $0 == nil } && cover == .keep }
}

public enum TagWriteError: Error, Equatable, CustomStringConvertible {
    case unsupported(String)
    case unsafeTag(String)
    case malformed(String)
    case verifyFailed
    public var description: String {
        switch self {
        case .unsupported(let s): return "这种格式暂不支持改标签（\(s)）"
        case .unsafeTag(let s): return "文件里的标签用了少见的写法，为了不损坏文件没有改（\(s)）"
        case .malformed(let s): return "文件结构读不懂，没有改（\(s)）"
        case .verifyFailed: return "写完核对发现音频数据不一致，已放弃，原文件没动"
        }
    }
}

public enum TagWriter {
    public static let supportedExtensions: Set<String> = ["mp3", "flac"]

    /// 按扩展名选写法；返回新的完整文件内容（已核对音频数据不变）
    public static func rewrite(_ data: Data, ext: String, edit: TagEdit) throws -> Data {
        switch ext.lowercased() {
        case "mp3":
            let out = try ID3Writer.rewrite(data, edit: edit)
            guard try ID3Writer.payload(out) == ID3Writer.payload(data) else { throw TagWriteError.verifyFailed }
            return out
        case "flac":
            let out = try FLACWriter.rewrite(data, edit: edit)
            guard try FLACWriter.payload(out) == FLACWriter.payload(data) else { throw TagWriteError.verifyFailed }
            return out
        default: throw TagWriteError.unsupported(ext)
        }
    }

    /// 安全替换：同目录先写临时文件 → 原文件整份拷到 backupDir → 原子替换。返回备份路径。
    @discardableResult
    public static func safeReplace(_ url: URL, with newData: Data, backupDir: URL, now: Date = Date()) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        var backup = backupDir.appendingPathComponent(f.string(from: now) + " " + url.lastPathComponent)
        var k = 1
        while fm.fileExists(atPath: backup.path) { k += 1; backup = backupDir.appendingPathComponent(f.string(from: now) + "-\(k) " + url.lastPathComponent) }
        try fm.copyItem(at: url, to: backup)
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).liuli-\(UUID().uuidString.prefix(8)).tmp")
        do {
            try newData.write(to: tmp, options: .atomic)
            _ = try fm.replaceItemAt(url, withItemAt: tmp, backupItemName: nil, options: [])
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
        return backup
    }
}

// MARK: - ID3v2（MP3）

public enum ID3Writer {
    struct Frame { var id: String; var raw: Data }       // raw = 整帧（头 + 内容），原样保留用
    struct Tag { var major: UInt8; var frames: [Frame]; var end: Int }

    static func syncsafe(_ d: Data, _ o: Int) -> Int { (Int(d[o]) << 21) | (Int(d[o + 1]) << 14) | (Int(d[o + 2]) << 7) | Int(d[o + 3]) }
    static func be32(_ d: Data, _ o: Int) -> Int { (Int(d[o]) << 24) | (Int(d[o + 1]) << 16) | (Int(d[o + 2]) << 8) | Int(d[o + 3]) }
    static func syncsafeBytes(_ n: Int) -> [UInt8] { [UInt8((n >> 21) & 0x7F), UInt8((n >> 14) & 0x7F), UInt8((n >> 7) & 0x7F), UInt8(n & 0x7F)] }
    static func be32Bytes(_ n: Int) -> [UInt8] { [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] }

    /// 读开头的 ID3v2；没有标签返回 nil
    static func parse(_ d: Data) throws -> Tag? {
        let d = Data(d)   // 下标从 0 开始
        guard d.count >= 10, d[0] == 0x49, d[1] == 0x44, d[2] == 0x33 else { return nil }
        let major = d[3], flags = d[5]
        guard major == 3 || major == 4 else { throw TagWriteError.unsafeTag("ID3v2.\(major)") }
        if flags & 0x80 != 0 { throw TagWriteError.unsafeTag("整体反同步") }
        if flags & 0x40 != 0 { throw TagWriteError.unsafeTag("扩展头") }
        let size = syncsafe(d, 6)
        let end = 10 + size + (major == 4 && flags & 0x10 != 0 ? 10 : 0)
        guard end <= d.count else { throw TagWriteError.malformed("标签长度超出文件") }
        var frames: [Frame] = []
        var o = 10
        let limit = 10 + size
        while o + 10 <= limit {
            if d[o] == 0 { break }                                      // 填充区
            guard let id = String(bytes: d[o..<(o + 4)], encoding: .ascii), id.allSatisfy({ $0.isUppercase || $0.isNumber }) else {
                throw TagWriteError.malformed("帧名")
            }
            let sz = major == 4 ? syncsafe(d, o + 4) : be32(d, o + 4)
            guard sz >= 0, o + 10 + sz <= limit else { throw TagWriteError.malformed("帧 \(id) 长度") }
            frames.append(Frame(id: id, raw: d.subdata(in: o..<(o + 10 + sz))))
            o += 10 + sz
        }
        return Tag(major: major, frames: frames, end: end)
    }

    /// 标签区之后的全部字节（音频 + 末尾的 ID3v1，原样）
    public static func payload(_ d: Data) throws -> Data {
        let d = Data(d)
        guard let t = try parse(d) else { return d }
        return d.subdata(in: t.end..<d.count)
    }

    /// APIC 的图片类型（3 = 封面正面）
    static func apicType(_ f: Frame) -> UInt8? {
        let b = [UInt8](f.raw.dropFirst(10))
        guard b.count > 2 else { return nil }
        var i = 1
        while i < b.count, b[i] != 0 { i += 1 }        // MIME 以 0 结尾
        return i + 1 < b.count ? b[i + 1] : nil
    }

    static func textFrame(_ id: String, _ value: String, major: UInt8) -> Data {
        var body = Data()
        if major == 4 { body.append(3); body.append(contentsOf: Array(value.utf8)) }
        else { body.append(1); body.append(contentsOf: [0xFF, 0xFE]); for u in value.utf16 { body.append(UInt8(u & 0xFF)); body.append(UInt8(u >> 8)) } }
        return header(id, body.count, major: major) + body
    }
    static func apicFrame(_ img: Data, mime: String, major: UInt8) -> Data {
        var body = Data([0])                              // 文字编码 Latin-1（描述为空）
        body.append(contentsOf: Array(mime.utf8)); body.append(0)
        body.append(3)                                    // 封面正面
        body.append(0)                                    // 空描述
        body.append(img)
        return header("APIC", body.count, major: major) + body
    }
    static func header(_ id: String, _ size: Int, major: UInt8) -> Data {
        Data(Array(id.utf8)) + Data(major == 4 ? syncsafeBytes(size) : be32Bytes(size)) + Data([0, 0])
    }

    public static func rewrite(_ data: Data, edit: TagEdit) throws -> Data {
        let d = Data(data)
        let old = try parse(d)
        let major = old?.major ?? 3
        var frames = old?.frames ?? []
        var add: [Data] = []
        func text(_ ids: [String], _ v: String?, write id: String) {
            guard let v else { return }
            frames.removeAll { ids.contains($0.id) }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { add.append(textFrame(id, t, major: major)) }
        }
        text(["TIT2"], edit.title, write: "TIT2")
        text(["TPE1"], edit.artist, write: "TPE1")
        text(["TALB"], edit.album, write: "TALB")
        text(["TPE2"], edit.albumArtist, write: "TPE2")
        text(["TRCK"], edit.track, write: "TRCK")
        text(["TYER", "TDRC"], edit.year, write: major == 4 ? "TDRC" : "TYER")
        text(["TCON"], edit.genre, write: "TCON")
        switch edit.cover {
        case .keep: break
        case .remove: frames.removeAll { $0.id == "APIC" && (apicType($0) ?? 3) == 3 }
        case .set(let img, let mime):
            frames.removeAll { $0.id == "APIC" && (apicType($0) ?? 3) == 3 }
            add.append(apicFrame(img, mime: mime, major: major))
        }
        var body = Data()
        for f in frames { body.append(f.raw) }
        for a in add { body.append(a) }
        body.append(Data(count: 1024))                     // 留一点填充，下次改小标签不用整文件挪
        var out = Data([0x49, 0x44, 0x33, major, 0, 0]) + Data(syncsafeBytes(body.count)) + body
        out.append(try payload(d))
        return out
    }

    /// 读出几个常用文本帧（核对 / 单元测试用）
    public static func readText(_ data: Data) throws -> [String: String] {
        guard let t = try parse(Data(data)) else { return [:] }
        var out: [String: String] = [:]
        for f in t.frames where f.id.hasPrefix("T") {
            let b = [UInt8](f.raw.dropFirst(10))
            guard let enc = b.first else { continue }
            let rest = Data(b.dropFirst())
            var s: String?
            switch enc {
            case 0: s = String(data: rest, encoding: .isoLatin1)
            case 1: s = String(data: rest, encoding: .utf16)
            case 2: s = String(data: rest, encoding: .utf16BigEndian)
            default: s = String(data: rest, encoding: .utf8)
            }
            out[f.id] = s?.trimmingCharacters(in: CharacterSet(charactersIn: "\0"))
        }
        return out
    }
    public static func hasFrontCover(_ data: Data) throws -> Bool {
        guard let t = try parse(Data(data)) else { return false }
        return t.frames.contains { $0.id == "APIC" && apicType($0) == 3 }
    }
}

// MARK: - FLAC（Vorbis comment + PICTURE）

public enum FLACWriter {
    struct Block { var type: UInt8; var body: Data }

    static func parse(_ data: Data) throws -> (blocks: [Block], audioStart: Int) {
        let d = Data(data)
        guard d.count >= 8, d[0] == 0x66, d[1] == 0x4C, d[2] == 0x61, d[3] == 0x43 else {
            if d.count >= 3, d[0] == 0x49, d[1] == 0x44, d[2] == 0x33 { throw TagWriteError.unsafeTag("FLAC 前面带 ID3") }
            throw TagWriteError.malformed("不是 FLAC")
        }
        var o = 4, blocks: [Block] = [], last = false
        while !last {
            guard o + 4 <= d.count else { throw TagWriteError.malformed("元数据块") }
            let h = d[o]; last = h & 0x80 != 0
            let len = (Int(d[o + 1]) << 16) | (Int(d[o + 2]) << 8) | Int(d[o + 3])
            guard o + 4 + len <= d.count else { throw TagWriteError.malformed("块长度") }
            blocks.append(Block(type: h & 0x7F, body: d.subdata(in: (o + 4)..<(o + 4 + len))))
            o += 4 + len
        }
        guard blocks.first?.type == 0 else { throw TagWriteError.malformed("缺 STREAMINFO") }
        return (blocks, o)
    }

    public static func payload(_ data: Data) throws -> Data {
        let d = Data(data)
        return d.subdata(in: try parse(d).audioStart..<d.count)
    }

    static func le32(_ d: [UInt8], _ o: Int) -> Int { Int(d[o]) | (Int(d[o + 1]) << 8) | (Int(d[o + 2]) << 16) | (Int(d[o + 3]) << 24) }
    static func le32Bytes(_ n: Int) -> [UInt8] { [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 24) & 0xFF)] }
    static func be32Bytes(_ n: Int) -> [UInt8] { [UInt8((n >> 24) & 0xFF), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] }

    /// Vorbis comment → (vendor, ["KEY=value"])
    static func comments(_ body: Data) throws -> (String, [String]) {
        let b = [UInt8](body)
        guard b.count >= 8 else { throw TagWriteError.malformed("Vorbis comment") }
        let vl = le32(b, 0); guard 4 + vl + 4 <= b.count else { throw TagWriteError.malformed("vendor") }
        let vendor = String(decoding: b[4..<(4 + vl)], as: UTF8.self)
        var o = 4 + vl
        let n = le32(b, o); o += 4
        var out: [String] = []
        for _ in 0..<n {
            guard o + 4 <= b.count else { throw TagWriteError.malformed("comment") }
            let l = le32(b, o); o += 4
            guard o + l <= b.count else { throw TagWriteError.malformed("comment 长度") }
            out.append(String(decoding: b[o..<(o + l)], as: UTF8.self)); o += l
        }
        return (vendor, out)
    }
    static func commentBlock(vendor: String, _ list: [String]) -> Data {
        var d = Data(le32Bytes(vendor.utf8.count)); d.append(contentsOf: Array(vendor.utf8))
        d.append(contentsOf: le32Bytes(list.count))
        for c in list { d.append(contentsOf: le32Bytes(c.utf8.count)); d.append(contentsOf: Array(c.utf8)) }
        return d
    }
    static func pictureType(_ body: Data) -> Int? { body.count >= 4 ? ID3Writer.be32(Data(body), 0) : nil }
    static func pictureBlock(_ img: Data, mime: String) -> Data {
        var d = Data(be32Bytes(3))
        d.append(contentsOf: be32Bytes(mime.utf8.count)); d.append(contentsOf: Array(mime.utf8))
        d.append(contentsOf: be32Bytes(0))                         // 描述为空
        d.append(contentsOf: be32Bytes(0) + be32Bytes(0) + be32Bytes(0) + be32Bytes(0))   // 宽高色深不填（0 = 未知，标准允许）
        d.append(contentsOf: be32Bytes(img.count)); d.append(img)
        return d
    }

    public static func rewrite(_ data: Data, edit: TagEdit) throws -> Data {
        let d = Data(data)
        let (blocks, audioStart) = try parse(d)
        var vendor = "琉璃"
        var list: [String] = []
        if let vc = blocks.first(where: { $0.type == 4 }) { (vendor, list) = try comments(vc.body) }
        func set(_ keys: [String], _ v: String?, write key: String) {
            guard let v else { return }
            list.removeAll { c in keys.contains { c.uppercased().hasPrefix($0 + "=") } }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { list.append(key + "=" + t) }
        }
        set(["TITLE"], edit.title, write: "TITLE")
        set(["ARTIST"], edit.artist, write: "ARTIST")
        set(["ALBUM"], edit.album, write: "ALBUM")
        set(["ALBUMARTIST", "ALBUM ARTIST"], edit.albumArtist, write: "ALBUMARTIST")
        set(["TRACKNUMBER"], edit.track, write: "TRACKNUMBER")
        set(["DATE", "YEAR"], edit.year, write: "DATE")
        set(["GENRE"], edit.genre, write: "GENRE")
        var out: [Block] = []
        var wroteComment = false
        for b in blocks {
            switch b.type {
            case 1: continue                                           // 旧填充丢掉，末尾重新放
            case 4: if !wroteComment { out.append(Block(type: 4, body: commentBlock(vendor: vendor, list))); wroteComment = true }
            case 6 where edit.cover != .keep && (pictureType(b.body) ?? 3) == 3: continue
            default: out.append(b)
            }
        }
        if !wroteComment { out.insert(Block(type: 4, body: commentBlock(vendor: vendor, list)), at: 1) }
        if case .set(let img, let mime) = edit.cover { out.append(Block(type: 6, body: pictureBlock(img, mime: mime))) }
        out.append(Block(type: 1, body: Data(count: 1024)))
        var r = Data([0x66, 0x4C, 0x61, 0x43])
        for (i, b) in out.enumerated() {
            guard b.body.count < 1 << 24 else { throw TagWriteError.unsafeTag("封面太大（超过 16 MB）") }
            let h = b.type | (i == out.count - 1 ? 0x80 : 0)
            r.append(contentsOf: [h, UInt8((b.body.count >> 16) & 0xFF), UInt8((b.body.count >> 8) & 0xFF), UInt8(b.body.count & 0xFF)])
            r.append(b.body)
        }
        r.append(d.subdata(in: audioStart..<d.count))
        return r
    }

    public static func readComments(_ data: Data) throws -> [String: String] {
        let (blocks, _) = try parse(Data(data))
        guard let vc = blocks.first(where: { $0.type == 4 }) else { return [:] }
        var out: [String: String] = [:]
        for c in try comments(vc.body).1 { if let eq = c.firstIndex(of: "=") { out[c[..<eq].uppercased()] = String(c[c.index(after: eq)...]) } }
        return out
    }
    public static func hasFrontCover(_ data: Data) throws -> Bool {
        try parse(Data(data)).blocks.contains { $0.type == 6 && pictureType($0.body) == 3 }
    }
}
