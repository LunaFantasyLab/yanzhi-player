// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import PlayerCore

/// 本地语音识别出字幕（whisper.cpp，MIT；不联网、不用云端 AI 服务）。
/// 流程：离线 mpv 把音轨解码成 16 kHz 单声道 WAV → whisper-cli 识别 → 视频出 SRT（挂到 mpv）、音频出 LRC（当歌词滚动）。
final class WhisperJob: @unchecked Sendable {
    enum Language: String, CaseIterable { case auto, zh, en, ja, ko
        var title: String { ["自动识别", "中文", "英文", "日文", "韩文"][Self.allCases.firstIndex(of: self)!] }
    }
    let media: URL
    let isVideo: Bool
    let language: Language
    private(set) var process: Process?
    private var cancelled = false
    private(set) var removedJunk = 0
    /// 自测用：保留抽出的音轨、记录命令行（在主线程设置，后台只读）
    var debugDir: URL?
    var logger: (@Sendable (String) -> Void)?
    var onProgress: (@Sendable (Double, String) -> Void)?

    init(media: URL, isVideo: Bool, language: Language) { self.media = media; self.isVideo = isVideo; self.language = language }

    static var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: Runtime.whisperCLI.path) && Runtime.whisperModel != nil }

    func cancel() { cancelled = true; process?.terminate() }

    /// 返回生成的字幕文件（视频 .srt，音频 .lrc）
    func run() throws -> URL {
        guard let model = Runtime.whisperModel, FileManager.default.isExecutableFile(atPath: Runtime.whisperCLI.path) else {
            throw NSError(domain: "whisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "还没装语音识别组件"])
        }
        onProgress?(0, "正在提取音轨…")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("liuli-asr-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: tmp) }
        guard MPVEngine.renderOffline(input: media.path, output: tmp.path, options: [("audio-channels", "mono"), ("audio-samplerate", "16000"), ("audio-format", "s16"), ("af", "")], timeout: 600),
              FileManager.default.fileExists(atPath: tmp.path) else {
            throw NSError(domain: "whisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "提取音轨失败"])
        }
        if cancelled { throw CancellationError() }
        if let dbg = debugDir { let keep = dbg.appendingPathComponent("asr-input-\(Runtime.key(for: media)).wav"); try? FileManager.default.removeItem(at: keep); try? FileManager.default.copyItem(at: tmp, to: keep) }
        let outDir = Runtime.dir(isVideo ? "subtitles" : "lyrics")
        let base = outDir.appendingPathComponent(Runtime.key(for: media) + ".whisper")
        let p = Process()
        p.executableURL = Runtime.whisperCLI
        var args = ["-m", model.path, "-f", tmp.path, "-of", base.path, "-l", language.rawValue,
                    "-t", "\(max(4, ProcessInfo.processInfo.activeProcessorCount - 2))", "-pp", "-np"]
        args.append(isVideo ? "-osrt" : "-olrc")
        // 语音活动检测（Silero VAD，MIT）：只把有人说话的片段送去识别，时间轴更准，也能挡住“静音处编字幕”
        // 参数是用 3 段真实视频（访谈 / 嘈杂实地录音 / 电影）对照人工字幕比出来的：阈值 0.3、前后各留 200ms，
        // 不带上文（-mc 0）防止 whisper 在噪声段陷入“同一句重复几十遍”
        if let vad = Runtime.vadModel { args += ["--vad", "-vm", vad.path, "-vmsd", "8", "-vt", "0.3", "-vp", "200"] }
        args += ["-mc", "0"]
        if language == .zh { args += ["--prompt", "以下是普通话的句子，使用简体中文。"] }
        p.arguments = args
        logger?("  whisper-cli " + args.map { $0.contains(" ") ? "\"\($0)\"" : $0 }.joined(separator: " "))
        let err = Pipe()
        p.standardError = err
        p.standardOutput = FileHandle.nullDevice
        process = p
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            // whisper-cli -pp：「whisper_print_progress_callback: progress =  45%」
            if let r = s.range(of: #"progress\s*=\s*(\d+)%"#, options: .regularExpression) {
                let num = s[r].filter(\.isNumber)
                if let v = Double(num) { self?.onProgress?(v / 100, "正在识别… \(Int(v))%") }
            }
        }
        onProgress?(0.01, "正在识别…")
        try p.run()
        p.waitUntilExit()
        err.fileHandleForReading.readabilityHandler = nil
        if cancelled { throw CancellationError() }
        let out = URL(fileURLWithPath: base.path + (isVideo ? ".srt" : ".lrc"))
        guard p.terminationStatus == 0, FileManager.default.fileExists(atPath: out.path) else {
            throw NSError(domain: "whisper", code: 3, userInfo: [NSLocalizedDescriptionKey: "识别失败（退出码 \(p.terminationStatus)）"])
        }
        // 清理 whisper 在无人声处编出的套话和成串重复
        if let raw = try? String(contentsOf: out, encoding: .utf8) {
            let (clean, removed) = isVideo ? ASRCleanup.cleanSRT(raw) : ASRCleanup.cleanLRC(raw)
            if removed > 0 { try? clean.write(to: out, atomically: true, encoding: .utf8) }
            removedJunk = removed
        }
        onProgress?(1, "完成")
        return out
    }
}
