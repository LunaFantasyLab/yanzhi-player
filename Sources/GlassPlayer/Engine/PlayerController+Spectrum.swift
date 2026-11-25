// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import AVFoundation
import PlayerCore

/// 均衡器 32 路真实音频频谱驱动（2026-11-24）：
/// 进入均衡器页或切歌时，在后台极速提取当前曲目的 32 路对数频段 FFT 包络（约 60–150ms）并缓存，
/// 播放时随 player.position 实时同步抖动；若为网络流或格式解码中，平滑回退到谐波律动。
extension PlayerController {
    func ensureTrackSpectrum() {
        guard let cur = current else {
            spectrumTask?.cancel(); spectrumTask = nil
            trackSpectrum = nil; trackSpectrumID = nil
            return
        }
        let id = cur.id
        if trackSpectrumID == id, trackSpectrum != nil { return }
        if let cached = spectrumCache[id] {
            trackSpectrumID = id
            trackSpectrum = cached
            return
        }
        guard cur.url.isFileURL else {
            trackSpectrumID = id
            trackSpectrum = nil
            return
        }
        spectrumTask?.cancel()
        trackSpectrumID = id
        trackSpectrum = nil
        let url = cur.url
        spectrumTask = Task.detached(priority: .utility) { [weak self] in
            guard !Task.isCancelled else { return }
            let spec = Self.computeSpectrum(for: url)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                if let spec {
                    if self.spectrumCache.count > 24 { self.spectrumCache.removeAll() }
                    self.spectrumCache[id] = spec
                    if self.current?.id == id {
                        self.trackSpectrumID = id
                        self.trackSpectrum = spec
                    }
                }
            }
        }
    }

    nonisolated private static func computeSpectrum(for url: URL) -> AudioSpectrum? {
        let targetRate = 22050
        // 1) 优先用 AVAssetReader 极速硬件/系统解码（MP3 / AAC / M4A / FLAC / ALAC / WAV / AIFF，约 60–150ms）
        if let mono = decodeMonoViaAVAssetReader(url: url, sampleRate: targetRate), !mono.isEmpty {
            return AudioSpectrum.analyze(mono: mono, sampleRate: targetRate)
        }
        // 2) 回退用 libmpv 离线解码（覆盖 APE / OGG / OPUS / DSD / MKV 等全格式）
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("liuli-spec-\(UUID().uuidString).wav").path
        defer { try? FileManager.default.removeItem(atPath: out) }
        guard MPVEngine.renderOffline(input: url.path, output: out,
                                      options: [("audio-channels", "mono"), ("audio-samplerate", "\(targetRate)"), ("af", "")],
                                      timeout: 30),
              let data = FileManager.default.contents(atPath: out),
              let wav = LoopSeam.readWAV(data),
              wav.rate > 0, !wav.samples.isEmpty else { return nil }
        let mono: [Float]
        if wav.channels == 1 {
            mono = wav.samples
        } else {
            mono = stride(from: 0, to: wav.samples.count - wav.channels + 1, by: wav.channels).map { i in
                (0..<wav.channels).reduce(Float(0)) { $0 + wav.samples[i + $1] } / Float(wav.channels)
            }
        }
        return AudioSpectrum.analyze(mono: mono, sampleRate: wav.rate)
    }

    nonisolated private static func decodeMonoViaAVAssetReader(url: URL, sampleRate: Int) -> [Float]? {
        let asset = AVURLAsset(url: url)
        let tracks = asset.tracks(withMediaType: .audio)
        guard let track = tracks.first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        // 上限 15 分钟单声道 22.05kHz（避免超长播客占过多内存）
        let maxSamples = sampleRate * 60 * 15
        var samples: [Float] = []
        samples.reserveCapacity(sampleRate * 180)
        while reader.status == .reading, samples.count < maxSamples {
            guard let sb = output.copyNextSampleBuffer() else { break }
            defer { CMSampleBufferInvalidate(sb) }
            guard let bb = CMSampleBufferGetDataBuffer(sb) else { continue }
            var length = 0
            var dataPointer: UnsafeMutablePointer<Int8>?
            let status = CMBlockBufferGetDataPointer(bb, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)
            if status == kCMBlockBufferNoErr, let ptr = dataPointer, length >= 4 {
                let count = min(length / MemoryLayout<Float>.size, maxSamples - samples.count)
                ptr.withMemoryRebound(to: Float.self, capacity: count) { fptr in
                    samples.append(contentsOf: UnsafeBufferPointer(start: fptr, count: count))
                }
            }
        }
        if reader.status == .reading { reader.cancelReading() }
        return samples.count >= 1024 ? samples : nil
    }
}
