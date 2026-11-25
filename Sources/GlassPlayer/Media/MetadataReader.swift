// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import AVFoundation
import AppKit
import PlayerCore

/// 读取一首歌/一段视频的标签、封面、歌词、技术参数。
/// 顺序：AVFoundation（系统原生格式）→ FFmpeg（FLAC/APE/OGG/WMA/DSD/MKV…）→ 文件名推断。
/// 封面顺序：文件内嵌 → 同目录 cover/folder/front.jpg 等 → 同名图片 → 视频截帧 → 生成的默认封面。
struct MediaDetails {
    var item: MediaItem
    var coverImage: CGImage?
    var lyrics: Lyrics?
    var properties: FileProperties?
}

enum MetadataReader {
    /// 极速单次探测：优先一次 C 级 FFmpegProbe 读完标签 / 时长 / 编码 / 封面 / 歌词并同步构建 FileProperties，
    /// 仅在 FFmpeg 未命中或无结果时回退 AVFoundation，避免对同一文件重复打开 2–3 次磁盘 I/O。
    static func read(_ base: MediaItem) async -> MediaDetails {
        var item = base
        var cover: CGImage?
        var lyricsText: String?
        var props: FileProperties?

        // 1) 单次 FFmpegProbe（极速，全格式一次读全）
        if let p = FFmpegProbe.probe(item.url) {
            let t = p.tags
            if let v = t["title"], !v.isEmpty { item.title = v }
            item.artist = t["artist"] ?? t["album_artist"] ?? t["albumartist"] ?? t["performer"]
            item.album = t["album"]
            if let tn = t["track"] { item.trackNumber = Int(tn.split(separator: "/").first ?? "") }
            if let dn = t["disc"] { item.discNumber = Int(dn.split(separator: "/").first ?? "") }
            item.duration = p.duration
            if let d = p.coverData { cover = decodeImage(d) }
            lyricsText = t["lyrics"] ?? t["unsyncedlyrics"] ?? t["lyrics-eng"] ?? t["uslt"]
            item.formatLine = formatLine(p, url: item.url)
            if p.video != nil && p.audio == nil { item.kind = .video }
            props = PlayerController.buildProperties(from: p, item: item)
        } else {
            // 2) 仅在 FFmpeg 读不到时才回退 AVFoundation
            let asset = AVURLAsset(url: item.url)
            if let common = try? await asset.load(.commonMetadata) {
                for m in common {
                    guard let key = m.commonKey else { continue }
                    switch key {
                    case .commonKeyTitle: if let s = try? await m.load(.stringValue), !s.isEmpty { item.title = s }
                    case .commonKeyArtist: if let s = try? await m.load(.stringValue), !s.isEmpty { item.artist = s }
                    case .commonKeyAlbumName: if let s = try? await m.load(.stringValue), !s.isEmpty { item.album = s }
                    case .commonKeyArtwork:
                        if cover == nil, let d = try? await m.load(.dataValue) { cover = decodeImage(d) }
                    default: break
                    }
                }
            }
            if let d = try? await asset.load(.duration), d.isNumeric, d.seconds > 0 { item.duration = d.seconds }
            if let l = try? await asset.load(.lyrics), !l.isEmpty { lyricsText = l }
            props = PlayerController.buildProperties(from: nil, item: item)
        }

        // 3) 同目录图片
        if cover == nil { cover = folderImage(for: item.url) }
        // 4) 视频截帧
        if cover == nil && item.kind == .video { cover = await videoThumbnail(item.url, duration: item.duration) }
        // 5) 同名 .lrc
        if let lrc = sidecarLyrics(item.url) { lyricsText = lrc }

        // 6) 本地侧车自定义标签与封面覆盖（覆盖 WAV/AIFF/APE/OGG/OPUS/DSD 等全格式编辑结果）
        if let custom = CustomTags.shared.entry(for: item.url) {
            if let v = custom.title { item.title = v.isEmpty ? MediaItem.titleFromFilename(item.url) : v }
            if let v = custom.artist { item.artist = v.isEmpty ? nil : v }
            if let v = custom.album { item.album = v.isEmpty ? nil : v }
            if let v = custom.track { item.trackNumber = Int(v.split(separator: "/").first ?? "") }
            if custom.coverRemoved {
                cover = nil
            } else if let data = CustomTags.shared.coverData(for: item.url), let img = decodeImage(data) {
                cover = img
            }
            if var pr = props {
                pr.tags = custom.applying(to: pr.tags)
                props = pr
            }
        }

        return MediaDetails(item: item, coverImage: cover, lyrics: lyricsText.map { Lyrics.parse($0) }, properties: props)
    }

    /// 只读图片尺寸，不解码
    static func pixelSize(_ data: Data) -> CGSize? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: w, height: h)
    }

    /// 真·全链路 4K 解码：原图长边 ≤ 3840 且无旋转时走完整原生主图解码（不走缩略图捷径），超 4K 或需 EXIF 旋转时按 4K 上限高质量解码。
    static func decodeImage(_ data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let w = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let h = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orient = props?[kCGImagePropertyOrientation] as? Int ?? 1
        if w > 0, h > 0, max(w, h) <= CoverStore.maxSide, orient == 1 {
            let fullOpts: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
            if let full = CGImageSourceCreateImageAtIndex(src, 0, fullOpts as CFDictionary) {
                return full
            }
        }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                     kCGImageSourceThumbnailMaxPixelSize: CoverStore.maxSide,
                                     kCGImageSourceCreateThumbnailWithTransform: true]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func folderImage(for url: URL) -> CGImage? {
        let dir = url.deletingLastPathComponent()
        guard let list = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        let images = list.filter { MediaFormats.imageExts.contains($0.pathExtension.lowercased()) }
        let stem = url.deletingPathExtension().lastPathComponent.lowercased()
        // 同名图片优先，其次 cover/folder/front…，再次目录里唯一的一张图
        if let same = images.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == stem }),
           let img = loadImage(same) { return img }
        for name in MediaFormats.coverNames {
            if let hit = images.first(where: { $0.deletingPathExtension().lastPathComponent.lowercased() == name }), let img = loadImage(hit) { return img }
        }
        if images.count == 1, let img = loadImage(images[0]) { return img }
        return nil
    }

    static func loadImage(_ url: URL) -> CGImage? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        return decodeImage(d)
    }

    static func videoThumbnail(_ url: URL, duration: Double?) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: CoverStore.maxSide, height: CoverStore.maxSide)
        let t = CMTime(seconds: max(1, (duration ?? 20) * 0.12), preferredTimescale: 600)
        if let r = try? await gen.image(at: t) { return r.image }
        // AVFoundation 打不开（MKV/AVI/WebM…）→ FFmpeg 解一帧
        if let rgba = FFmpegProbe.thumbnail(url, maxSide: CoverStore.maxSide) { return makeCGImage(rgba.pixels, width: rgba.width, height: rgba.height) }
        return nil
    }

    static func makeCGImage(_ px: [UInt8], width: Int, height: Int) -> CGImage? {
        let data = Data(px) as CFData
        guard let prov = CGDataProvider(data: data) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    static func sidecarLyrics(_ url: URL) -> String? {
        let lrc = url.deletingPathExtension().appendingPathExtension("lrc")
        guard let d = try? Data(contentsOf: lrc) else { return nil }
        if let s = String(data: d, encoding: .utf8) { return s }
        // 老的中文歌词常是 GB18030
        let gb = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String(data: d, encoding: String.Encoding(rawValue: gb))
    }

    static func formatLine(_ p: FFmpegProbe.Result, url: URL) -> String? {
        if let v = p.video {
            var s = "\(v.codec.uppercased()) · \(v.width)×\(v.height)"
            if let a = p.audio { s += " · \(a.codec.uppercased())" }
            return s
        }
        guard let a = p.audio else { return nil }
        let codec: String = {
            switch a.codec {
            case "flac": return "FLAC"
            case "alac": return "ALAC"
            case "aac": return "AAC"
            case "mp3", "mp3float": return "MP3"
            case "opus": return "Opus"
            case "vorbis": return "Vorbis"
            case "ape": return "APE"
            case let c where c.hasPrefix("pcm"): return url.pathExtension.uppercased() == "AIFF" || url.pathExtension.lowercased() == "aif" ? "AIFF" : "PCM"
            case let c where c.hasPrefix("dsd"): return "DSD"
            case let c where c.hasPrefix("wma"): return "WMA"
            default: return a.codec.uppercased()
            }
        }()
        var parts = [codec]
        let lossy = ["MP3", "AAC", "Opus", "Vorbis", "WMA"].contains(codec)
        if codec == "DSD" {
            parts.append("DSD\(a.sampleRate * 8 / 44100)")
        } else if lossy {
            if a.bitRate > 0 { parts.append("\(a.bitRate / 1000) kbps") }
            parts.append(String(format: "%.1f kHz", Double(a.sampleRate) / 1000).replacingOccurrences(of: ".0 kHz", with: " kHz"))
        } else {
            let khz = String(format: "%g kHz", Double(a.sampleRate) / 1000)
            parts.append(a.bitDepth > 0 ? "\(a.bitDepth) bit / \(khz)" : khz)
        }
        if a.channels > 2 { parts.append("\(a.channels) 声道") }
        return parts.joined(separator: " · ")
    }
}
