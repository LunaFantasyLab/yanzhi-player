// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit

/// 「有进就有出」（TANCO 2026-11-19）：凡是能进入的状态，都要有看得见的退出方式，Esc 也能一层层退，
/// 退出用和进入对称的过渡动画，退出后状态恢复正确。
///
/// 这张表就是自测 closureTests() 的清单：每个状态进一次、退一次、断言恢复。
/// 新增状态时：在 ExitState 里加一项（编译器会逼着 SelfTest 里的 switch 补上测试），
/// 并把对应的属性名写进下面的 exit-registry；tools/check-exits.py 在构建时扫描 PlayerController，
/// 发现没登记的状态属性就让构建失败。
///
/// exit-registry: coverViewerOpen videoStageOpen isLifted activeCard cardOpen loopEditorOpen speedPitchOpen subtitlePanelOpen autoEqPanelOpen showShortcuts isScrubbing scanDirection isPinnedMini tab abA abB speed pitchSemitones pitchCents asrProgress showPlayHistory playlistBrowseOpen isRenamingPlaylist isReorderingThemes propertiesOpen tagEditorOpen autoEqBrandOpen
/// exit-exempt（不是“进入的状态”：会自己消失的过程、只读状态、菜单里打勾的偏好开关）: isPlaying isBuffering isVideo isDropTargeted playlistDropTargeted videoDropTargeted chromeVisible lyricsSearching subtitleSearching autoEqLoading analyzingSections isFloating lyricsEnabled loopInputOpen closeAction seekStepSeconds startupMode
enum ExitState: String, CaseIterable {
    case coverViewer, videoStage, lifted, paramCard, shortcuts, scrubbing, scanning, fullScreen, mini, equalizerTab, playlistTab, asr, abLoop, speedPitch, auxWindow, playHistory, playlistBrowse, playlistRename, themeReorder, properties, tagEditor, autoEqBrand

    var name: String {
        switch self {
        case .coverViewer: "封面观赏模式（专辑封面放到最大看）"
        case .videoStage: "视频舞台（正在播放页上的视频大画面）"
        case .lifted: "专辑卡翻面（简介与歌词）"
        case .paramCard: "参数卡片（区间循环 / 变速变调 / 字幕搜索 / 耳机校正）"
        case .shortcuts: "键盘快捷键面板"
        case .scrubbing: "拖动进度条"
        case .scanning: "长按快进 / 快退"
        case .fullScreen: "全屏"
        case .mini: "迷你窗（置顶小窗，代替画中画）"
        case .equalizerTab: "均衡器页"
        case .playlistTab: "播放列表页"
        case .asr: "正在识别字幕"
        case .abLoop: "区间循环（A-B）"
        case .speedPitch: "变速 / 变调"
        case .auxWindow: "设置窗口、检查更新小窗"
        case .playHistory: "播放记录"
        case .playlistBrowse: "看自己的歌单（播放列表页上方选了某个歌单）"
        case .playlistRename: "给歌单起名"
        case .themeReorder: "主题面板拖动排序（长按进入）"
        case .properties: "播放列表行翻面看属性"
        case .tagEditor: "编辑标签（ID3 / FLAC / M4A，含专辑封面）"
        case .autoEqBrand: "耳机校正 ▸ 按品牌浏览的某个品牌"
        }
    }
    var enter: String {
        switch self {
        case .coverViewer: "双击专辑卡（中间、旁边、背面）；右键「观赏封面」（卡片、播放列表行）；⌘Y；双击播放栏小封面；双击迷你窗封面（先回大窗口）"
        case .videoStage: "点 / 双击视频卡；轮播停在视频卡上时继续播放；回车；播放列表里双击视频"
        case .lifted: "点中间那张卡；回车；右键「显示简介与歌词」"
        case .paramCard: "播放栏的按钮；菜单；右键；快捷键（⌥⌘L、⌥⌘K…）"
        case .shortcuts: "右键空白处「键盘快捷键」；帮助菜单"
        case .scrubbing: "按住进度条拖动"
        case .scanning: "按住 ← →，或按住上一首 / 下一首按钮"
        case .fullScreen: "F；绿色按钮；菜单"
        case .mini: "⇧⌘M；右键「迷你窗」；菜单「画中画」"
        case .equalizerTab: "E；⌘3；顶部分段按钮"
        case .playlistTab: "L；⌘2；顶部分段按钮"
        case .asr: "「自动生成字幕」"
        case .abLoop: "⌥⌘B 两次；循环卡片；进度条 ⌥ 拖选；「找副歌并循环」"
        case .speedPitch: "[ ]；变速卡片；菜单"
        case .auxWindow: "⌘,；「检查更新…」"
        case .playHistory: "菜单栏「播放列表 ▸ 播放记录」；播放列表上的「播放记录」"
        case .playlistBrowse: "播放列表页顶上点歌单名；「+」新建后自动进入"
        case .playlistRename: "「+」新建歌单；双击歌单名；歌单空白处右键「重命名」"
        case .themeReorder: "右上调色板 ▸ 长按任意一个色板"
        case .properties: "播放列表里点文件名或封面；右键「属性」"
        case .tagEditor: "属性背面右下角的铅笔；右键「编辑标签…」"
        case .autoEqBrand: "耳机校正卡片 ▸ 品牌列表里点一个品牌"
        }
    }
    var exits: String {
        switch self {
        case .coverViewer: "Esc（观赏里进的全屏先退全屏 → 放大了先回到适应窗口 → 再按退出）；右上 ×；单击封面或空白（无论是否放大，立即飞回原入口）；右键「退出观赏」；再按 ⌘Y（飞回原来的卡片 / 小封面，回到进入前的状态）"
        case .videoStage: "左上「返回」；Esc；点画面外空白处；双指左右滑；右键「返回封面轮播」（回到轮播，视频暂停）"
        case .lifted: "卡背左上「返回」；Esc；回车；点空白处；双指左右滑；再点一下卡片；右键「翻回封面」"
        case .paramCard: "卡片右上「收起」；Esc；点卡片外面；再按一次同一个按钮"
        case .shortcuts: "右上 ×；Esc；点面板外面"
        case .scrubbing: "松手（跳到新位置）；Esc（放弃，回到原位置）"
        case .scanning: "松手；Esc"
        case .fullScreen: "Esc；F；绿色按钮"
        case .mini: "小窗上的「退出迷你窗」按钮；Esc；⇧⌘M；右键"
        case .equalizerTab: "顶部「正在播放」；Esc；E；⌘1"
        case .playlistTab: "顶部「正在播放」；Esc；L；⌘1"
        case .asr: "进度条旁的 ×；Esc"
        case .abLoop: "播放栏里「A-B」小标签上的 ×；循环卡片里的 ×；Esc；⌥⌘B"
        case .speedPitch: "播放栏里速度小标签旁的 ↺；卡片里「全部恢复」；Esc；⌥\\"
        case .auxWindow: "左上关闭；Esc；⌘W；更新小窗的「以后再说」"
        case .playHistory: "右上「关闭」；Esc；再选一次「播放记录」"
        case .playlistBrowse: "点「当前列表」；Esc；歌单空白处右键「回到当前列表」"
        case .playlistRename: "回车（保存）；点别处（保存）；Esc（不改名）"
        case .themeReorder: "点「完成」；点面板外面；Esc"
        case .properties: "再点一下文件名或封面；点背面任意处；Esc"
        case .tagEditor: "「取消」；「保存」；Esc（不保存）"
        case .autoEqBrand: "左上「‹ 品牌」；Esc（回到品牌列表，再按收起卡片）"
        }
    }
}

extension PlayerController {
    /// Esc：从最里面一层往外退，一次只退一层；返回退掉的是哪一层（什么都没退就是 nil）
    @discardableResult
    func escapeOnce() -> ExitState? {
        if viewer.isOpen { viewerEscape(); return .coverViewer }
        if tagEditorOpen { if !tagSaving { closeTagEditor() }; return .tagEditor }
        if isReorderingThemes { endThemeReorder(); return .themeReorder }
        if activeCard == .autoEq && autoEqBrand != nil { closeAutoEqBrand(); return .autoEqBrand }
        if activeCard != nil { closeCard(); return .paramCard }
        if showShortcuts { toggleShortcutsHelp(); return .shortcuts }
        if showPlayHistory { closePlayHistory(); return .playHistory }
        if isRenamingPlaylist { cancelRenamePlaylist(); return .playlistRename }
        if propertiesOpen { closeProperties(); return .properties }
        if isScrubbing { cancelScrub(); return .scrubbing }
        if scanDirection != 0 { endScan(); return .scanning }
        if isLifted { exitLift(); return .lifted }
        if let w = mainWindow, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil); return .fullScreen }
        if isPinnedMini { togglePinnedMini(); return .mini }
        if videoStageOpen && tab == .nowPlaying { exitVideoStage(); return .videoStage }
        if tab == .equalizer { withAnimation(Motion.tab) { tab = .nowPlaying }; return .equalizerTab }
        if tab == .playlist && playlistBrowseOpen { closePlaylistBrowse(); return .playlistBrowse }
        if tab == .playlist { withAnimation(Motion.tab) { tab = .nowPlaying }; return .playlistTab }
        if asrProgress != nil { cancelASR(); showHUD("xmark.circle", "已取消识别字幕"); return .asr }
        if abA != nil || abB != nil { clearABLoop(); return .abLoop }
        if speed != 1 || pitchSemitones != 0 || pitchCents != 0 { resetSpeedPitch(); return .speedPitch }
        return nil
    }

    /// 从卡背翻回封面：和翻过去用同一条弹簧（Motion.lift），轮播位置不动
    func exitLift() {
        guard isLifted else { return }
        withAnimation(Motion.lift) { isLifted = false }
    }

}
