// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import PlayerCore

/// 播放记录页：从菜单或播放列表进入。只查看时不改当前队列；点选才重播。
struct PlayHistoryView: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 26, style: .continuous)
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.inkFill.opacity(0.10))
            if player.playHistory.items.isEmpty {
                Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(player.playHistory.items) { item in
                        Button { player.replayFromHistory(item) } label: { row(item) }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .glass(shape, tint: Color(player.palette.glassTint), amount: 0.07)
        .foregroundStyle(Color.ink)
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("播放记录").font(.system(size: 20, weight: .bold))
                Text(player.playHistory.items.isEmpty ? "空" : "\(player.playHistory.items.count) 首")
                    .font(.system(size: 12)).opacity(0.6)
            }
            Spacer()
            Button { player.promptClearPlayHistory() } label: {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(GlassChipStyle())
            .fixedSize()
            .disabled(player.playHistory.items.isEmpty)
            .help("清空播放记录")
            Button { player.closePlayHistory() } label: {
                Label("关闭", systemImage: "xmark")
            }
            .buttonStyle(GlassChipStyle())
            .fixedSize()
            .help("关闭播放记录")
            .accessibilityLabel("关闭播放记录")
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
    }

    private func row(_ item: PlayHistoryItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.fileExists ? "music.note" : "questionmark.folder")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .opacity(0.7)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                if let artist = item.artist, !artist.isEmpty {
                    Text(artist).font(.system(size: 11)).opacity(0.6).lineLimit(1)
                }
                if !item.fileExists {
                    Text("文件已不在原处").font(.system(size: 11)).opacity(0.55)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(item.fileExists ? 1 : 0.72)
    }
}
