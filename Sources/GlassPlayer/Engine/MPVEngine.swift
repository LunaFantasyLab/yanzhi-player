// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import QuartzCore
import PlayerCore
#if canImport(Libmpv)
import Libmpv
#endif

/// libmpv 的薄封装：一个 mpv 实例同时负责音频和视频。
/// 事件在后台队列读取，转回主线程回调。这个文件只依赖 Foundation + Libmpv（不依赖 AppKit），
/// 便于在 Linux 上用 mpv 头文件做类型检查（tools/linux-check）。
final class MPVEngine {
    enum Event {
        case fileLoaded(path: String)
        case endFile(reason: String)
        case idle
        case property(name: String, value: PropertyValue)
        case shutdown
    }
    enum PropertyValue {
        case double(Double), flag(Bool), int(Int64), string(String), none
        var double: Double? { if case .double(let d) = self { return d }; if case .int(let i) = self { return Double(i) }; return nil }
        var flag: Bool? { if case .flag(let b) = self { return b }; return nil }
        var int: Int64? { if case .int(let i) = self { return i }; return nil }
        var string: String? { if case .string(let s) = self { return s }; return nil }
    }

    struct Track: Identifiable, Hashable {
        enum Kind: String { case audio, video, sub }
        var id: Int
        var kind: Kind
        var title: String?
        var lang: String?
        var codec: String?
        var isExternal: Bool
        var isSelected: Bool
        var isAlbumArt: Bool
        var displayName: String {
            var parts: [String] = []
            if let t = title, !t.isEmpty { parts.append(t) }
            if let l = lang, !l.isEmpty { parts.append(LanguageName.display(l)) }
            if let c = codec, !c.isEmpty { parts.append(c.uppercased()) }
            if isExternal { parts.append("外挂") }
            return parts.isEmpty ? "轨道 \(id)" : parts.joined(separator: " · ")
        }
    }

    var onEvent: ((Event) -> Void)?

    #if canImport(Libmpv)
    private(set) var handle: OpaquePointer?
    private let queue = DispatchQueue(label: "tanco.mpv.events", qos: .userInitiated)
    private var retainedSelf: Unmanaged<MPVEngine>?

    init(initialAudioFilter: String) {
        guard let h = mpv_create() else { return }
        handle = h
        func opt(_ k: String, _ v: String) { _ = mpv_set_option_string(h, k, v) }

        // —— 基础 ——
        opt("config", "no")                    // 不读用户的 mpv.conf，行为可控
        opt("terminal", "no")
        opt("idle", "yes")
        opt("input-default-bindings", "no")
        opt("input-vo-keyboard", "no")
        opt("input-media-keys", "no")          // 媒体键交给系统「正在播放」
        opt("osc", "no")
        // 不加载 mpv 内置的 Lua 脚本（统计、控制台、选择菜单等），App 用不到，省线程
        for k in ["load-stats-overlay", "load-console", "load-select", "load-positioning", "load-commands", "load-context-menu", "load-auto-profiles"] { opt(k, "no") }
        opt("osd-level", "0")
        opt("ytdl", "no")
        opt("keep-open", "no")
        opt("prefetch-playlist", "yes")        // 预读下一首，配合 gapless
        opt("gapless-audio", "weak")           // 格式一致时无缝；不强行重采样（不牺牲音质）
        opt("audio-display", "no")             // 音频文件里的封面不当视频画面
        opt("volume-max", "150")
        opt("audio-pitch-correction", "yes")   // 倍速不变调
        opt("replaygain", "no")
        opt("resume-playback", "no")           // 续播由 App 自己管
        opt("save-position-on-quit", "no")
        opt("demuxer-max-bytes", "150MiB")
        opt("cache", "auto")

        // —— 视频：mpv 渲染 API（vo=libmpv）+ OpenGL 层，每帧按当前画布尺寸渲染（见 MPVGLLayer）——
        // 以前用 wid + gpu-next/moltenvk：改窗口大小时画面只画一角，重建输出又黑一帧，2026-11-18 换掉。
        opt("vo", "libmpv")
        opt("hwdec", "videotoolbox")           // M5 硬解 H.264/HEVC/AV1/ProRes
        opt("hwdec-codecs", "all")
        opt("scale", "ewa_lanczossharp")
        opt("cscale", "ewa_lanczossharp")
        opt("dscale", "mitchell")
        opt("correct-downscaling", "yes")
        opt("linear-downscaling", "yes")
        opt("sigmoid-upscaling", "yes")
        opt("tscale", "oversample")
        opt("deband", "yes")
        opt("dither-depth", "auto")
        opt("keepaspect", "yes")
        opt("background-color", "#000000")

        // —— 字幕：自动加载同名外挂，中文优先，字体用苹方 ——
        opt("sub-auto", "fuzzy")
        opt("sub-file-paths", "subs:Subs:subtitles:Subtitles:字幕")
        opt("slang", "chs,sc,zh-Hans,zh-CN,zh,chi,zho,cht,zh-Hant,eng,en")
        opt("alang", "zh,chi,zho,ja,jpn,en,eng")
        opt("sub-codepage", "auto")
        opt("sub-font", "PingFang SC")
        opt("sub-font-size", "46")
        opt("sub-bold", "no")
        opt("sub-border-size", "2.4")
        opt("sub-shadow-offset", "1")
        opt("sub-shadow-color", "#80000000")
        opt("sub-margin-y", "48")
        opt("sub-ass-override", "no")          // 保留 ASS 原样式

        // —— 声道：单声道等少见布局统一先转成立体声再交给系统。
        // 某些设备（如 BlackHole 2ch）直接收单声道会初始化失败；而 libmpv 的 coreaudio 输出初始化失败后
        // 会留下一个失效的热插拔回调，之后插拔设备时整个进程会崩溃（2026-11-18 自测复现）。
        opt("audio-channels", "stereo,5.1,7.1")
        // 同一个坑的另一种触发：48 kHz 的「分平面」浮点格式（floatp/doublep，视频和 48k 音乐常见）交给 coreaudio 时
        // 设声道布局报 -50 而初始化失败，留下失效回调，之后任何音频设备变化（插耳机、AirPlay 出现）都会崩溃
        // （2026-11-19 离线自测复现）。统一交出交错排列的 32 位浮点：这正是系统混音器内部用的格式，不损音质。
        opt("audio-format", "float")

        // —— 均衡器滤镜链（开机即装好，之后只发 af-command 改参数）——
        opt("af", initialAudioFilter)

        #if DEBUG
        _ = mpv_request_log_messages(h, "warn")
        #endif
        // 排错用：启动参数 -mpvLogFile <路径> 时把 mpv 详细日志写到该文件（默认不写）
        // 不用 mpv 自带的 log-file：它在大量详细日志下会和渲染线程互相等死（2026-11-18 自测在截图时复现）。
        // 改为客户端日志（缓冲满了只丢消息、不阻塞），由事件循环自己写文件。
        let logPath = UserDefaults.standard.string(forKey: "mpvLogFile") ?? ""
        guard mpv_initialize(h) >= 0 else { mpv_destroy(h); handle = nil; return }
        if !logPath.isEmpty {
            FileManager.default.createFile(atPath: logPath, contents: nil)
            logFile = FileHandle(forWritingAtPath: logPath)
            _ = mpv_request_log_messages(h, "v")
        }

        observe("pause", MPV_FORMAT_FLAG)
        observe("time-pos", MPV_FORMAT_DOUBLE)
        observe("duration", MPV_FORMAT_DOUBLE)
        observe("volume", MPV_FORMAT_DOUBLE)
        observe("mute", MPV_FORMAT_FLAG)
        observe("speed", MPV_FORMAT_DOUBLE)
        observe("idle-active", MPV_FORMAT_FLAG)
        observe("paused-for-cache", MPV_FORMAT_FLAG)
        observe("track-list/count", MPV_FORMAT_INT64)
        observe("aid", MPV_FORMAT_STRING)
        observe("sid", MPV_FORMAT_STRING)
        observe("video-out-params/aspect", MPV_FORMAT_DOUBLE)
        observe("audio-params/samplerate", MPV_FORMAT_INT64)
        observe("path", MPV_FORMAT_STRING)

        let me = Unmanaged.passRetained(self)
        retainedSelf = me
        mpv_set_wakeup_callback(h, { ctx in
            guard let ctx else { return }
            Unmanaged<MPVEngine>.fromOpaque(ctx).takeUnretainedValue().drainEvents()
        }, me.toOpaque())
    }

    var isReady: Bool { handle != nil }

    private func observe(_ name: String, _ format: mpv_format) {
        guard let h = handle else { return }
        _ = mpv_observe_property(h, 0, name, format)
    }

    // MARK: 命令
    func command(_ args: [String]) {
        guard let h = handle else { return }
        withCStrings(args) { ptrs in _ = mpv_command(h, ptrs) }
    }

    /// 异步命令：拖均衡器滑杆时用，不阻塞主线程。
    func commandAsync(_ args: [String]) {
        guard let h = handle else { return }
        withCStrings(args) { ptrs in _ = mpv_command_async(h, 0, ptrs) }
    }

    private func withCStrings(_ args: [String], _ body: (UnsafeMutablePointer<UnsafePointer<CChar>?>) -> Void) {
        var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) }
        cargs.append(nil)
        defer { for p in cargs where p != nil { free(p) } }
        cargs.withUnsafeMutableBufferPointer { buf in
            buf.baseAddress!.withMemoryRebound(to: UnsafePointer<CChar>?.self, capacity: buf.count) { body($0) }
        }
    }

    /// 截图：MPVKit 里的 libavcodec 没带图片编码器（screenshot-to-file 报「Could not open libavcodec encoder」，
    /// 2026-11-18 自测发现），所以改用 screenshot-raw 拿原始像素，自己用 ImageIO 存 PNG。
    func screenshotRaw(_ flags: String) -> CGImage? {
        guard let h = handle else { return nil }
        let c0 = strdup("screenshot-raw"), c1 = strdup(flags)
        defer { free(c0); free(c1) }
        var items = [mpv_node(), mpv_node()]
        items[0].format = MPV_FORMAT_STRING; items[0].u.string = c0
        items[1].format = MPV_FORMAT_STRING; items[1].u.string = c1
        var result = mpv_node()
        let rc: Int32 = items.withUnsafeMutableBufferPointer { buf in
            var list = mpv_node_list(num: 2, values: buf.baseAddress, keys: nil)
            return withUnsafeMutablePointer(to: &list) { lp in
                var arg = mpv_node(); arg.format = MPV_FORMAT_NODE_ARRAY; arg.u.list = lp
                return mpv_command_node(h, &arg, &result)
            }
        }
        guard rc >= 0 else { return nil }
        defer { mpv_free_node_contents(&result) }
        guard result.format == MPV_FORMAT_NODE_MAP, let l = result.u.list?.pointee else { return nil }
        var w = 0, ht = 0, stride = 0, fmt = "bgr0"
        var bytes: Data?
        for i in 0..<Int(l.num) {
            guard let kp = l.keys?[i] else { continue }
            let k = String(cString: kp), v = l.values[i]
            switch (k, v.format) {
            case ("w", MPV_FORMAT_INT64): w = Int(v.u.int64)
            case ("h", MPV_FORMAT_INT64): ht = Int(v.u.int64)
            case ("stride", MPV_FORMAT_INT64): stride = Int(v.u.int64)
            case ("format", MPV_FORMAT_STRING): if let sp = v.u.string { fmt = String(cString: sp) }
            case ("data", MPV_FORMAT_BYTE_ARRAY): if let ba = v.u.ba?.pointee, let d = ba.data { bytes = Data(bytes: d, count: ba.size) }
            default: break
            }
        }
        guard w > 0, ht > 0, stride >= w * 4, let data = bytes, data.count >= stride * ht,
              let provider = CGDataProvider(data: data as CFData) else { return nil }
        let alpha: CGImageAlphaInfo = fmt == "bgra" ? .premultipliedFirst : .noneSkipFirst
        let info = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | alpha.rawValue)
        return CGImage(width: w, height: ht, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    func setString(_ name: String, _ value: String) {
        guard let h = handle else { return }
        _ = mpv_set_property_string(h, name, value)
    }
    func setFlag(_ name: String, _ value: Bool) {
        guard let h = handle else { return }
        var v: Int32 = value ? 1 : 0
        _ = mpv_set_property(h, name, MPV_FORMAT_FLAG, &v)
    }
    func setDouble(_ name: String, _ value: Double) {
        guard let h = handle else { return }
        var v = value
        _ = mpv_set_property(h, name, MPV_FORMAT_DOUBLE, &v)
    }
    func getString(_ name: String) -> String? {
        guard let h = handle, let c = mpv_get_property_string(h, name) else { return nil }
        defer { mpv_free(c) }
        return String(cString: c)
    }
    func getDouble(_ name: String) -> Double? {
        guard let h = handle else { return nil }
        var v = 0.0
        return mpv_get_property(h, name, MPV_FORMAT_DOUBLE, &v) >= 0 ? v : nil
    }
    func getInt(_ name: String) -> Int64? {
        guard let h = handle else { return nil }
        var v: Int64 = 0
        return mpv_get_property(h, name, MPV_FORMAT_INT64, &v) >= 0 ? v : nil
    }
    func getFlag(_ name: String) -> Bool? {
        guard let h = handle else { return nil }
        var v: Int32 = 0
        return mpv_get_property(h, name, MPV_FORMAT_FLAG, &v) >= 0 ? (v != 0) : nil
    }

    // MARK: 高层操作
    func load(_ url: URL, start: Double? = nil, mode: String = "replace") {
        var args = ["loadfile", url.isFileURL ? url.path : url.absoluteString, mode]
        if let s = start, s > 0 {
            // mpv ≥0.38：loadfile <url> <flags> <index> <options>
            args += ["-1", "start=\(s)"]
        }
        command(args)
    }

    func append(_ url: URL) { command(["loadfile", url.isFileURL ? url.path : url.absoluteString, "append"]) }
    /// 只保留当前播放项，清掉后面的预读项
    func clearLookahead() { command(["playlist-clear"]) }
    func stop() { command(["stop"]) }
    func seek(absolute t: Double, exact: Bool = true) { commandAsync(["seek", String(t), exact ? "absolute+exact" : "absolute+keyframes"]) }
    func seek(relative t: Double) { commandAsync(["seek", String(t), "relative+exact"]) }
    func addSubtitle(_ url: URL) { command(["sub-add", url.path, "select"]) }

    func tracks() -> [Track] {
        guard let n = getInt("track-list/count"), n > 0 else { return [] }
        var out: [Track] = []
        for i in 0..<Int(n) {
            let p = "track-list/\(i)/"
            guard let type = getString(p + "type"), let kind = Track.Kind(rawValue: type),
                  let id = getInt(p + "id") else { continue }
            out.append(Track(id: Int(id), kind: kind, title: getString(p + "title"), lang: getString(p + "lang"),
                             codec: getString(p + "codec"), isExternal: getFlag(p + "external") ?? false,
                             isSelected: getFlag(p + "selected") ?? false, isAlbumArt: getFlag(p + "albumart") ?? false))
        }
        return out
    }

    private var logFile: FileHandle?
    private let logStart = CACurrentMediaTime()

    // MARK: 事件循环
    private func drainEvents() {
        queue.async { [weak self] in
            guard let self, let h = self.handle else { return }
            while true {
                guard let ev = mpv_wait_event(h, 0) else { break }
                let e = ev.pointee
                if e.event_id == MPV_EVENT_NONE { break }
                var out: Event?
                switch e.event_id {
                case MPV_EVENT_FILE_LOADED:
                    out = .fileLoaded(path: self.getString("path") ?? "")
                case MPV_EVENT_END_FILE:
                    var reason = "eof"
                    if let d = e.data {
                        let ef = d.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                        switch ef.reason {
                        case MPV_END_FILE_REASON_EOF: reason = "eof"
                        case MPV_END_FILE_REASON_STOP: reason = "stop"
                        case MPV_END_FILE_REASON_ERROR: reason = "error"
                        case MPV_END_FILE_REASON_REDIRECT: reason = "redirect"
                        default: reason = "quit"
                        }
                    }
                    out = .endFile(reason: reason)
                case MPV_EVENT_IDLE:
                    out = .idle
                case MPV_EVENT_SHUTDOWN:
                    out = .shutdown
                case MPV_EVENT_PROPERTY_CHANGE:
                    if let d = e.data {
                        let prop = d.assumingMemoryBound(to: mpv_event_property.self).pointee
                        let name = String(cString: prop.name)
                        var value: PropertyValue = .none
                        if let pd = prop.data {
                            switch prop.format {
                            case MPV_FORMAT_DOUBLE: value = .double(pd.assumingMemoryBound(to: Double.self).pointee)
                            case MPV_FORMAT_FLAG: value = .flag(pd.assumingMemoryBound(to: Int32.self).pointee != 0)
                            case MPV_FORMAT_INT64: value = .int(pd.assumingMemoryBound(to: Int64.self).pointee)
                            case MPV_FORMAT_STRING:
                                if let cs = pd.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee {
                                    value = .string(String(cString: cs))
                                }
                            default: break
                            }
                        }
                        out = .property(name: name, value: value)
                    }
                case MPV_EVENT_LOG_MESSAGE:
                    if let d = e.data {
                        let m = d.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                        if let lf = self.logFile, let t = m.text, let pre = m.prefix, let lv = m.level {
                            let line = String(format: "[%.3f][%@][%@] ", CACurrentMediaTime() - self.logStart, String(cString: lv), String(cString: pre)) + String(cString: t)
                            lf.write(line.data(using: .utf8) ?? Data())
                        }
                        #if DEBUG
                        if self.logFile == nil, let t = m.text { print("[mpv]", String(cString: t), terminator: "") }
                        #endif
                    }
                default: break
                }
                if let out {
                    DispatchQueue.main.async { [weak self] in self?.onEvent?(out) }
                }
                if e.event_id == MPV_EVENT_SHUTDOWN { break }
            }
        }
    }

    /// 开一个独立的 mpv 离线解码（不出声：ao=pcm 写 WAV，vo=null），把经过滤镜链后的真实输出采样写到 output。
    /// 用于：区间接缝对齐取波形、自测录接缝波形。不占用正在播放的那个 mpv。
    static func renderOffline(input: String, output: String, options: [(String, String)], timeout: Double = 20) -> Bool {
        guard let h = mpv_create() else { return false }
        func opt(_ k: String, _ v: String) { _ = mpv_set_option_string(h, k, v) }
        opt("config", "no"); opt("terminal", "no"); opt("vo", "null"); opt("video", "no"); opt("sub", "no")
        opt("load-scripts", "no"); opt("ytdl", "no"); opt("hr-seek", "yes")
        opt("ao", "pcm"); opt("ao-pcm-file", output); opt("ao-pcm-waveheader", "yes"); opt("audio-format", "float")
        for (k, v) in options { opt(k, v) }
        guard mpv_initialize(h) >= 0 else { mpv_destroy(h); return false }
        let c0 = strdup("loadfile"), c1 = strdup(input)
        var args: [UnsafePointer<CChar>?] = [UnsafePointer(c0), UnsafePointer(c1), nil]
        _ = mpv_command(h, &args)
        free(c0); free(c1)
        var ok = false
        let t0 = Date()
        while Date().timeIntervalSince(t0) < timeout {
            guard let ev = mpv_wait_event(h, 0.5)?.pointee else { continue }
            if ev.event_id == MPV_EVENT_END_FILE { ok = true; break }
            if ev.event_id == MPV_EVENT_SHUTDOWN { break }
        }
        mpv_terminate_destroy(h)
        return ok
    }

    /// 自测用：离线播放时在指定播放时刻改 af（模拟用户在播放中变调），录下真实输出，量切换处有没有爆音/断音
    static func renderOfflineAFSwap(input: String, output: String, start: Double, length: Double, initialAF: String, swaps: [(Double, String)]) -> Bool {
        guard let h = mpv_create() else { return false }
        func opt(_ k: String, _ v: String) { _ = mpv_set_option_string(h, k, v) }
        opt("config", "no"); opt("terminal", "no"); opt("vo", "null"); opt("video", "no"); opt("sub", "no")
        opt("load-scripts", "no"); opt("ytdl", "no")
        opt("ao", "pcm"); opt("ao-pcm-file", output); opt("ao-pcm-waveheader", "yes"); opt("audio-format", "float")
        opt("start", String(format: "%.6f", start)); opt("length", String(format: "%.6f", length)); opt("af", initialAF)
        guard mpv_initialize(h) >= 0 else { mpv_destroy(h); return false }
        let c0 = strdup("loadfile"), c1 = strdup(input)
        var args: [UnsafePointer<CChar>?] = [UnsafePointer(c0), UnsafePointer(c1), nil]
        _ = mpv_command(h, &args)
        free(c0); free(c1)
        var pending = swaps.sorted { $0.0 < $1.0 }
        var ok = false
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 20 {
            if let ev = mpv_wait_event(h, 0.002)?.pointee {
                if ev.event_id == MPV_EVENT_END_FILE { ok = true; break }
                if ev.event_id == MPV_EVENT_SHUTDOWN { break }
            }
            if let next = pending.first {
                var t: Double = 0
                if mpv_get_property(h, "audio-pts", MPV_FORMAT_DOUBLE, &t) >= 0, t >= next.0 {
                    _ = mpv_set_property_string(h, "af", next.1)
                    pending.removeFirst()
                }
            }
        }
        mpv_terminate_destroy(h)
        return ok
    }

    /// 取 input 在 [start, start+duration) 的原始解码采样（float 交错）
    static func extractPCM(input: String, start: Double, duration: Double) -> (samples: [Float], channels: Int, rate: Int)? {
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("liuli-seam-\(UUID().uuidString).wav").path
        defer { try? FileManager.default.removeItem(atPath: out) }
        guard renderOffline(input: input, output: out, options: [("start", String(format: "%.6f", max(0, start))), ("length", String(format: "%.6f", duration)), ("af", "")], timeout: 8),
              let d = FileManager.default.contents(atPath: out) else { return nil }
        return LoopSeam.readWAV(d)
    }

    func shutdown() {
        guard let h = handle else { return }
        mpv_set_wakeup_callback(h, nil, nil)
        handle = nil
        queue.sync { mpv_terminate_destroy(h) }
        retainedSelf?.release()
        retainedSelf = nil
    }

    deinit { if handle != nil { shutdown() } }
    #else
    // 没有 libmpv 时（例如只想编译 UI 看效果），引擎为空壳。
    init(initialAudioFilter: String) {}
    var isReady: Bool { false }
    func command(_ args: [String]) {}
    func commandAsync(_ args: [String]) {}
    func screenshotRaw(_ flags: String) -> CGImage? { nil }
    func setString(_ name: String, _ value: String) {}
    func setFlag(_ name: String, _ value: Bool) {}
    func setDouble(_ name: String, _ value: Double) {}
    func getString(_ name: String) -> String? { nil }
    func getDouble(_ name: String) -> Double? { nil }
    func getInt(_ name: String) -> Int64? { nil }
    func getFlag(_ name: String) -> Bool? { nil }
    func load(_ url: URL, start: Double? = nil, mode: String = "replace") {}
    func append(_ url: URL) {}
    func clearLookahead() {}
    func stop() {}
    func seek(absolute t: Double, exact: Bool = true) {}
    func seek(relative t: Double) {}
    func addSubtitle(_ url: URL) {}
    func tracks() -> [Track] { [] }
    func shutdown() {}
    static func renderOffline(input: String, output: String, options: [(String, String)], timeout: Double = 20) -> Bool { false }
    static func extractPCM(input: String, start: Double, duration: Double) -> (samples: [Float], channels: Int, rate: Int)? { nil }
    static func renderOfflineAFSwap(input: String, output: String, start: Double, length: Double, initialAF: String, swaps: [(Double, String)]) -> Bool { false }
    #endif
}

enum LanguageName {
    static func display(_ code: String) -> String {
        switch code.lowercased() {
        case "chi", "zho", "zh", "chs", "sc", "zh-hans", "zh-cn": return "中文"
        case "cht", "zh-hant", "zh-tw", "zh-hk": return "繁体中文"
        case "eng", "en": return "英语"
        case "jpn", "ja": return "日语"
        case "kor", "ko": return "韩语"
        case "fre", "fra", "fr": return "法语"
        case "ger", "deu", "de": return "德语"
        case "spa", "es": return "西班牙语"
        case "rus", "ru": return "俄语"
        case "und": return "未标注"
        default: return code
        }
    }
}
