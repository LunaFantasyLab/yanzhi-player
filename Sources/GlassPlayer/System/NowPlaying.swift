// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import AppKit
import MediaPlayer

/// 系统「正在播放」+ 键盘媒体键（F7/F8/F9）、耳机线控、控制中心、锁屏。
@MainActor
final class NowPlayingBridge {
    struct Handlers {
        var play: () -> Void
        var pause: () -> Void
        var toggle: () -> Void
        var next: () -> Void
        var previous: () -> Void
        var seek: (Double) -> Void
        var skip: (Double) -> Void
    }

    private var targets: [(MPRemoteCommand, Any)] = []

    init(_ h: Handlers) {
        let c = MPRemoteCommandCenter.shared()
        func add(_ cmd: MPRemoteCommand, _ f: @escaping () -> Void) {
            cmd.isEnabled = true
            let t = cmd.addTarget { _ in DispatchQueue.main.async { f() }; return .success }
            targets.append((cmd, t))
        }
        add(c.playCommand, h.play)
        add(c.pauseCommand, h.pause)
        add(c.togglePlayPauseCommand, h.toggle)
        add(c.nextTrackCommand, h.next)
        add(c.previousTrackCommand, h.previous)
        c.changePlaybackPositionCommand.isEnabled = true
        let t = c.changePlaybackPositionCommand.addTarget { e in
            guard let e = e as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let pos = e.positionTime
            DispatchQueue.main.async { h.seek(pos) }
            return .success
        }
        targets.append((c.changePlaybackPositionCommand, t))
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: PlayerController.seekStep)]
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: PlayerController.seekStep)]
        add(c.skipForwardCommand) { h.skip(PlayerController.seekStep) }
        add(c.skipBackwardCommand) { h.skip(-PlayerController.seekStep) }
    }

    func update(title: String, artist: String?, album: String?, duration: Double?, position: Double, rate: Double,
                isPlaying: Bool, isVideo: Bool, artwork: CGImage?) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: isVideo ? MPNowPlayingInfoMediaType.video.rawValue : MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let artist { info[MPMediaItemPropertyArtist] = artist }
        if let album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration, duration.isFinite { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork {
            let img = NSImage(cgImage: artwork, size: NSSize(width: artwork.width, height: artwork.height))
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = isPlaying ? .playing : .paused
    }

    func clear() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
