// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
#if canImport(Libavformat) && canImport(Libavcodec) && canImport(Libavutil) && canImport(Libswscale)
import Libavformat
import Libavcodec
import Libavutil
import Libswscale
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// 用 MPVKit 自带的 FFmpeg 读标签、内嵌封面、音频规格，以及给 AVFoundation 打不开的视频（MKV/AVI/WebM…）截缩略图。
/// 只依赖 Foundation + FFmpeg，可在 Linux 上做类型检查。
enum FFmpegProbe {
    struct AudioInfo { var codec: String; var sampleRate: Int; var channels: Int; var bitDepth: Int; var bitRate: Int64 }
    struct VideoInfo { var codec: String; var width: Int; var height: Int }
    struct Result {
        var tags: [String: String] = [:]
        var duration: Double?
        var audio: AudioInfo?
        var video: VideoInfo?
        var coverData: Data?
        var formatName: String?
    }
    struct RGBAImage { var pixels: [UInt8]; var width: Int; var height: Int }

    static let available = true

    static func probe(_ url: URL) -> Result? {
        var ctxPtr: UnsafeMutablePointer<AVFormatContext>? = nil
        guard avformat_open_input(&ctxPtr, url.path, nil, nil) == 0, let ctx = ctxPtr else { return nil }
        defer { avformat_close_input(&ctxPtr) }
        _ = avformat_find_stream_info(ctx, nil)

        var r = Result()
        readTags(ctx.pointee.metadata, into: &r.tags)
        if ctx.pointee.duration > 0 { r.duration = Double(ctx.pointee.duration) / Double(AV_TIME_BASE) }
        if let ifmt = ctx.pointee.iformat, let n = ifmt.pointee.name { r.formatName = String(cString: n) }

        let n = Int(ctx.pointee.nb_streams)
        for i in 0..<n {
            guard let st = ctx.pointee.streams[i], let par = st.pointee.codecpar else { continue }
            let codec = String(cString: avcodec_get_name(par.pointee.codec_id))
            if (st.pointee.disposition & AV_DISPOSITION_ATTACHED_PIC) != 0 {
                let pkt = st.pointee.attached_pic
                if r.coverData == nil, let d = pkt.data, pkt.size > 0 { r.coverData = Data(bytes: d, count: Int(pkt.size)) }
                continue
            }
            switch par.pointee.codec_type {
            case AVMEDIA_TYPE_AUDIO where r.audio == nil:
                var depth = Int(par.pointee.bits_per_raw_sample)
                if depth == 0 { depth = Int(av_get_bytes_per_sample(AVSampleFormat(rawValue: par.pointee.format)) * 8) }
                r.audio = AudioInfo(codec: codec, sampleRate: Int(par.pointee.sample_rate),
                                    channels: Int(par.pointee.ch_layout.nb_channels), bitDepth: depth,
                                    bitRate: par.pointee.bit_rate > 0 ? par.pointee.bit_rate : ctx.pointee.bit_rate)
                // Ogg/Opus/FLAC 的标签常在流上
                readTags(st.pointee.metadata, into: &r.tags)
            case AVMEDIA_TYPE_VIDEO where r.video == nil:
                r.video = VideoInfo(codec: codec, width: Int(par.pointee.width), height: Int(par.pointee.height))
            default: break
            }
        }
        return r
    }

    private static func readTags(_ dict: OpaquePointer?, into tags: inout [String: String]) {
        guard let dict else { return }
        var e: UnsafePointer<AVDictionaryEntry>? = nil
        while let next = av_dict_iterate(dict, e) {
            if let k = next.pointee.key, let v = next.pointee.value {
                let key = String(cString: k).lowercased()
                if tags[key] == nil { tags[key] = String(cString: v) }
            }
            e = next
        }
    }

    /// 解码一帧做缩略图（默认按 4K 3840px 出图，取 12% 处避开片头黑场）。
    static func thumbnail(_ url: URL, maxSide: Int = 3840, at fraction: Double = 0.12) -> RGBAImage? {
        var ctxPtr: UnsafeMutablePointer<AVFormatContext>? = nil
        guard avformat_open_input(&ctxPtr, url.path, nil, nil) == 0, let ctx = ctxPtr else { return nil }
        defer { avformat_close_input(&ctxPtr) }
        guard avformat_find_stream_info(ctx, nil) >= 0 else { return nil }
        let vs = av_find_best_stream(ctx, AVMEDIA_TYPE_VIDEO, -1, -1, nil, 0)
        guard vs >= 0, let st = ctx.pointee.streams[Int(vs)], let par = st.pointee.codecpar,
              let dec = avcodec_find_decoder(par.pointee.codec_id) else { return nil }
        guard let cc = avcodec_alloc_context3(dec) else { return nil }
        var cctx: UnsafeMutablePointer<AVCodecContext>? = cc
        defer { avcodec_free_context(&cctx) }
        guard avcodec_parameters_to_context(cc, par) >= 0 else { return nil }
        cc.pointee.thread_count = 0
        guard avcodec_open2(cc, dec, nil) >= 0 else { return nil }

        if ctx.pointee.duration > 0 {
            let target = Int64(Double(ctx.pointee.duration) * fraction)
            _ = av_seek_frame(ctx, -1, target, AVSEEK_FLAG_BACKWARD)
            avcodec_flush_buffers(cc)
        }
        guard let p = av_packet_alloc() else { return nil }
        var pkt: UnsafeMutablePointer<AVPacket>? = p
        defer { av_packet_free(&pkt) }
        guard let f = av_frame_alloc() else { return nil }
        var frm: UnsafeMutablePointer<AVFrame>? = f
        defer { av_frame_free(&frm) }

        let eagain = -EAGAIN
        var got = false
        var reads = 0
        while !got && reads < 600 {
            reads += 1
            if av_read_frame(ctx, p) < 0 { _ = avcodec_send_packet(cc, nil) }
            else {
                defer { av_packet_unref(p) }
                if p.pointee.stream_index != vs { continue }
                if avcodec_send_packet(cc, p) < 0 { continue }
            }
            let rc = avcodec_receive_frame(cc, f)
            if rc == 0 { got = true } else if rc != eagain { break }
        }
        guard got, f.pointee.width > 0, f.pointee.height > 0 else { return nil }

        let sw = Int(f.pointee.width), sh = Int(f.pointee.height)
        var sar = 1.0
        if f.pointee.sample_aspect_ratio.num > 0 && f.pointee.sample_aspect_ratio.den > 0 {
            sar = Double(f.pointee.sample_aspect_ratio.num) / Double(f.pointee.sample_aspect_ratio.den)
        }
        let dispW = Double(sw) * sar, dispH = Double(sh)
        let scale = min(1, Double(maxSide) / max(dispW, dispH))
        let dw = max(2, Int((dispW * scale).rounded())), dh = max(2, Int((dispH * scale).rounded()))
        guard let sws = sws_getContext(Int32(sw), Int32(sh), AVPixelFormat(rawValue: f.pointee.format),
                                       Int32(dw), Int32(dh), AV_PIX_FMT_RGBA, Int32(truncatingIfNeeded: SWS_BICUBIC.rawValue), nil, nil, nil) else { return nil }
        defer { sws_freeContext(sws) }
        var out = [UInt8](repeating: 0, count: dw * dh * 4)
        let ok: Bool = out.withUnsafeMutableBufferPointer { ob -> Bool in
            var dstData: [UnsafeMutablePointer<UInt8>?] = [ob.baseAddress, nil, nil, nil]
            var dstStride: [Int32] = [Int32(dw * 4), 0, 0, 0]
            return withUnsafePointer(to: &f.pointee.data) { dataTuple -> Bool in
                dataTuple.withMemoryRebound(to: UnsafePointer<UInt8>?.self, capacity: 8) { src in
                    withUnsafePointer(to: &f.pointee.linesize) { lsTuple in
                        lsTuple.withMemoryRebound(to: Int32.self, capacity: 8) { ls in
                            sws_scale(sws, src, ls, 0, Int32(sh), &dstData, &dstStride) > 0
                        }
                    }
                }
            }
        }
        return ok ? RGBAImage(pixels: out, width: dw, height: dh) : nil
    }
}
#else
enum FFmpegProbe {
    struct AudioInfo { var codec: String; var sampleRate: Int; var channels: Int; var bitDepth: Int; var bitRate: Int64 }
    struct VideoInfo { var codec: String; var width: Int; var height: Int }
    struct Result {
        var tags: [String: String] = [:]
        var duration: Double?
        var audio: AudioInfo?
        var video: VideoInfo?
        var coverData: Data?
        var formatName: String?
    }
    struct RGBAImage { var pixels: [UInt8]; var width: Int; var height: Int }
    static let available = false
    static func probe(_ url: URL) -> Result? { nil }
    static func thumbnail(_ url: URL, maxSide: Int = 3840, at fraction: Double = 0.12) -> RGBAImage? { nil }
}
#endif
