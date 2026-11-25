// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation
import AppKit
import Observation
import QuartzCore
import SwiftUI
import UniformTypeIdentifiers
import PlayerCore

enum MainTab: String, CaseIterable, Identifiable {
    case nowPlaying, playlist, equalizer
    var id: String { rawValue }
    var title: String { self == .nowPlaying ? "正在播放" : (self == .playlist ? "播放列表" : "均衡器") }
    var symbol: String { self == .nowPlaying ? "play.circle" : (self == .playlist ? "list.bullet" : "slider.vertical.3") }
}

/// 播放条上方的参数卡片：同一时间最多一张
enum ParamCard: String, CaseIterable {
    case loop, speedPitch, subtitle, autoEq
    var title: String {
        switch self { case .loop: "区间循环"; case .speedPitch: "变速与变调"; case .subtitle: "字幕搜索"; case .autoEq: "耳机校正" }
    }
}

struct HUDMessage: Equatable, Identifiable {
    let id = UUID()
    var symbol: String
    var text: String
}

/// App 的大脑：持有播放队列、mpv 引擎、封面缓存、均衡器、轮播物理；所有界面都只读它的状态、调它的方法。
/// 点击窗口关闭按钮时的行为（设置里可选）
enum WindowCloseAction: String, CaseIterable, Identifiable, Sendable {
    case minimize
    case quit
    var id: String { rawValue }
    var title: String { self == .minimize ? "最小化" : "彻底退出" }
}

/// 启动时「正在播放」的初始状态（设置里可选；默认「全新空白」，歌单与播放记录始终保留）
enum StartupMode: String, CaseIterable, Identifiable, Sendable {
    case fresh
    case resume
    var id: String { rawValue }
    var title: String { self == .fresh ? "全新空白" : "延续上次" }
}

@MainActor
@Observable
final class PlayerController {
    // MARK: 对外状态
    var queue = PlayQueue()
    private(set) var isPlaying = false
    private(set) var hasMedia = false { didSet { updateCardOpen() } }
    /// 120Hz 插值后的播放位置（只有进度条读它，其他视图不会因此重绘）
    private(set) var position: Double = 0
    private(set) var duration: Double?
    private(set) var volume: Double = 80
    private(set) var muted = false
    private(set) var speed: Double = 1
    private(set) var eq = EQState()
    private(set) var customPresets: [EQPreset] = []
    private(set) var tracks: [MPVEngine.Track] = []
    private(set) var videoAspect: Double = 16.0 / 9.0
    private(set) var isBuffering = false
    private(set) var coverPalette: AmbientPalette = .fallback
    private(set) var coverKey: String = "fallback"
    /// 配色主题（记在 UserDefaults 里，下次打开沿用）
    /// 没选过主题时默认「跟随系统」：系统浅色→白，深色→黑
    private(set) var theme: AppTheme = AppTheme(rawValue: Prefs.string("theme") ?? "") ?? .system
    /// 系统当前是否为深色外观（App 自己的外观会被主题强制，所以直接读系统设置并监听变化）
    private(set) var systemDark: Bool = PlayerController.readSystemDark()
    static func readSystemDark() -> Bool { UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark" }
    @ObservationIgnored private var appearanceObserver: NSObjectProtocol?
    func watchSystemAppearance() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let d = PlayerController.readSystemDark()
                guard d != self.systemDark else { return }
                withAnimation(Motion.themeChange) { self.systemDark = d }
                self.updatePaletteForCurrent()
            }
        }
    }
    /// 实际生效的外观（「默认」已落到白/黑）
    var look: AppTheme { theme.resolved(systemDark: systemDark) }
    /// 界面实际使用的配色：跟随封面时取封面色，否则用主题色
    /// 11-23 规范：界面实际用色一律走「三色块柔光」色板（固定主题 softLightPalette，跟随封面 softLight 提亮）；
    /// `AppTheme.palette` 原值保留给测试与历史对照，不再直接上屏。
    var palette: AmbientPalette { look.softLightPalette ?? coverPalette.softLight }
    /// 背景层的身份：换主题或（跟随封面时）换歌，背景整体交叉淡入淡出
    var paletteKey: String { look.followsCover ? "cover-\(coverKey)" : "theme-\(look.rawValue)" }
    var lyrics: Lyrics?
    /// 自动搜索歌词（LRCLIB）：默认关；开关状态保存在偏好里（自测时只在内存里）
    var lyricsEnabled: Bool = Prefs.bool("lyricsAutoSearch")
    /// 联网补官方专辑封面：默认开
    var onlineCoversEnabled: Bool = Prefs.object("onlineCovers") as? Bool ?? true
    /// MusicBrainz 查不到时也用 iTunes 补：默认关（苹果条款限制）
    var iTunesCoversEnabled: Bool = Prefs.bool("onlineCoversITunes")
    @ObservationIgnored var coverTried: Set<MediaItem.ID> = []
    /// 每首最近一次联网查封面的结果（自测和菜单用）：online / none / noinfo / userDefault / failed
    @ObservationIgnored var coverOutcome: [MediaItem.ID: String] = [:]
    /// 联网查到的封面出处（曲目 id → 来源 / 专辑 / 链接）
    var coverInfo: [MediaItem.ID: CoverService.Found] = [:]
    /// 在线查到的歌词（按曲目），以及查过的曲目（查不到就不再打扰）
    @ObservationIgnored var onlineLyrics: [MediaItem.ID: Lyrics] = [:]
    @ObservationIgnored var lyricsTried: Set<MediaItem.ID> = []
    var lyricsSearching = false
    var lyricsSource: String?
    var lastOpenedURL: URL?
    private(set) var coverVersion = 0
    var hud: HUDMessage?
    private(set) var isPinnedMini = false
    var carousel = CarouselPhysics(count: 0)
    var tab: MainTab = .nowPlaying
    var isDropTargeted = false
    var chromeVisible = true
    var isLifted = false
    var isScrubbing = false
    @ObservationIgnored var scrubOrigin: Double?
    /// 自测用：上一次「添加」是不是在选择对话框里点了取消
    @ObservationIgnored var lastAddCancelled = false
    /// 卡片翻着时的那一次横扫只用来翻回，不带动轮播（回到原来的位置）
    @ObservationIgnored var swallowCarouselDrag = false

    // —— 菜单里的播放/音频/视频状态（都会反映到菜单勾选和 HUD）——
    var abA: Double?
    var abB: Double?
    /// 启动状态：全新空白（默认） / 延续上次（仅控制「正在播放」队列，歌单与播放记录始终保留）
    var startupMode: StartupMode = StartupMode(rawValue: Prefs.string("startupMode") ?? "") ?? .fresh {
        didSet { Prefs.set(startupMode.rawValue, "startupMode") }
    }
    /// 点击窗口关闭按钮时的行为：彻底退出 / 最小化（默认彻底退出）
    var closeAction: WindowCloseAction = WindowCloseAction(rawValue: Prefs.string("windowCloseAction") ?? "") ?? .quit {
        didSet { Prefs.set(closeAction.rawValue, "windowCloseAction") }
    }
    /// 快进 / 快退步长（秒）：5 / 10 / 15 / 30
    var seekStepSeconds: Double = {
        let v = Prefs.object("seekStepSeconds") as? Double ?? 15
        return [5, 10, 15, 30].contains(v) ? v : 15
    }() {
        didSet { Prefs.set(seekStepSeconds, "seekStepSeconds") }
    }
    /// 区间循环「无缝接缝」：把 A/B 各自微调到波形能连续接上的采样（默认开）
    var loopSeamAlign: Bool = Prefs.object("loopSeamAlign") as? Bool ?? true {
        didSet { Prefs.set(loopSeamAlign, "loopSeamAlign"); scheduleLoopSeam() }
    }
    /// 最近一次对齐结果（给输入条和自测显示）：A、B 各挪了多少毫秒，接缝跳变前后
    var loopSeamInfo: LoopSeamResult?
    /// 当前打开的参数卡片（区间循环 / 变速变调 / 字幕搜索 / 耳机校正）：同一时间最多一张，打开新的旧的自动收起
    var activeCard: ParamCard? {
        didSet {
            guard oldValue != activeCard else { return }
            lastCardChange = CACurrentMediaTime()
            updateCardOpen()
            // 旧卡片里的输入框交出键盘焦点（隐藏的卡片不能再吃按键）
            if oldValue != nil, let w = mainWindow, w.firstResponder is NSText || w.firstResponder is NSTextView { w.makeFirstResponder(nil) }
            // 卡片开着时视频控件不自动隐藏；关上后重新开始计时
            if activeCard != nil { if !chromeVisible { chromeVisible = true } } else { pokeChrome() }
            videoSurface.setBlur(visibleCard != nil && isVideo ? 6 : 0)
            scheduleMenuCardSync()
        }
    }
    /// 菜单栏和右键菜单里「打开 / 收起某张卡片」的标题读这个：读到的永远是真实的当前卡片，
    /// 但菜单视图只在卡片过渡结束后（最后一次开 / 关 / 切换 0.8 秒后）才跟着重算一次。
    /// 原因（第8轮自测定位）：每开 / 关 / 切换一次卡片，二十多个菜单视图会在过渡的第一帧一起重建，
    /// 主线程那一下要 20–25ms，过渡必然掉一帧。右键、打开菜单栏之前会先立刻同步，所以弹出来的菜单标题总是对的。
    var menuCard: ParamCard? { _ = menuCardVersion; return _activeCard }
    private(set) var menuCardVersion = 0
    @ObservationIgnored private var menuCardSynced: ParamCard?
    @ObservationIgnored private var menuCardTimer: Timer?
    private func scheduleMenuCardSync() {
        menuCardTimer?.invalidate()
        menuCardTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncMenuCardNow() }
        }
    }
    /// 立刻让菜单跟上当前卡片（右键 / 点菜单栏前调用；没有变化时什么都不做）
    func syncMenuCardNow() {
        menuCardTimer?.invalidate(); menuCardTimer = nil
        if menuCardSynced != _activeCard { menuCardSynced = _activeCard; menuCardVersion &+= 1 }
    }
    /// 是否有卡片显示着（只在“开 / 关”时变，卡片之间切换不变）。背景磨砂、歌词条等只看它，
    /// 这样卡片之间切换时只有卡片那一小块界面需要重算，整页不跟着重算。
    private(set) var cardOpen = false
    private func updateCardOpen() { let o = visibleCard != nil; if cardOpen != o { cardOpen = o } }
    /// 最近一次开 / 关 / 切换参数卡片的时间（顶部菜单栏重建会避开这段过渡）
    @ObservationIgnored var lastCardChange: CFTimeInterval = 0
    /// 真正显示的卡片（没有媒体时，区间 / 变速 / 字幕卡不显示）
    var visibleCard: ParamCard? {
        guard let c = activeCard else { return nil }
        return (c == .autoEq || hasMedia) ? c : nil
    }
    func closeCard() { if activeCard != nil { withAnimation(Motion.panel) { activeCard = nil } } }
    private func cardFlag(_ c: ParamCard, _ on: Bool) {
        if on { activeCard = c } else if activeCard == c { activeCard = nil }
    }
    /// 区间时间输入条是否展开
    var loopEditorOpen: Bool { get { activeCard == .loop } set { cardFlag(.loop, newValue) } }
    /// 变调：半音（±12）与音分（±50），和速度互不影响
    var pitchSemitones = 0
    var pitchCents = 0
    var speedPitchOpen: Bool { get { activeCard == .speedPitch } set { cardFlag(.speedPitch, newValue) } }
    // —— 长按快进 / 快退 ——
    /// 0 = 没在快进快退；1 = 快进；-1 = 快退
    var scanDirection = 0
    var scanRate: Double = 0
    @ObservationIgnored var scanTask: Task<Void, Never>?
    @ObservationIgnored var scanFadeTask: Task<Void, Never>?
    @ObservationIgnored var scanEndedAt: CFTimeInterval = 0
    @ObservationIgnored var scanKeyDown: (dir: Int, at: CFTimeInterval)?
    /// 快进快退淡出 / 淡入期间，mpv 回报的音量不要覆盖用户设定的音量
    @ObservationIgnored var scanVolumeOverride = false
    /// 段落检测结果（当前曲目；第一个是副歌）
    var sections: [ChorusDetector.Section] = []
    var analyzingSections = false
    @ObservationIgnored var sectionsURL: URL?
    @ObservationIgnored var sectionCache: [String: [ChorusDetector.Section]] = [:]
    // —— 字幕：本地语音识别 / 在线搜索 ——
    var asrProgress: Double?          // nil = 没在识别
    var asrStatus = ""
    @ObservationIgnored var asrJob: WhisperJob?
    var subtitlePanelOpen: Bool { get { activeCard == .subtitle } set { cardFlag(.subtitle, newValue) } }
    var subtitleResults: [SubtitleSearch.Result] = []
    var subtitleSearching = false
    var subtitleMessage = ""
    var subtitleQuery = ""
    // —— 耳机校正（AutoEq）——
    var autoEqPanelOpen: Bool { get { activeCard == .autoEq } set { cardFlag(.autoEq, newValue) } }
    @ObservationIgnored var autoEqApplyWork: Task<Void, Never>?
    var autoEqQuery = ""
    var autoEqIndex: [AutoEq.Entry] = []
    var autoEqLoading = false
    var autoEqMessage = ""
    var autoEqEntry: AutoEq.Entry? = Prefs.data("autoEqEntry").flatMap { try? JSONDecoder().decode(AutoEq.Entry.self, from: $0) }
    var autoEqCurve: AutoEq.Curve? = Prefs.data("autoEqCurve").flatMap { try? JSONDecoder().decode(AutoEq.Curve.self, from: $0) }
    var autoEqEnabled: Bool = Prefs.bool("autoEqEnabled")
    var autoEqStrength: Double = Prefs.object("autoEqStrength") as? Double ?? 1
    var autoEqRecent: [AutoEq.Entry] = Prefs.data("autoEqRecent").flatMap { try? JSONDecoder().decode([AutoEq.Entry].self, from: $0) } ?? []
    /// 进度条上拖选/拖手柄时的临时区间（给输入条实时显示）
    var loopPreview: ClosedRange<Double>?
    @ObservationIgnored var loopSeamToken = 0
    var audioDelay: Double = 0
    var subDelay: Double = 0
    var channelMode: ChannelMode = .stereo
    var aspectOverride: String = "no"
    var videoZoom: Double = 0
    var panscan = false
    var videoRotate = 0
    var isFloating = false
    var recent: [URL] = Prefs.recent
    /// 与启动会话分离的播放历史；冷启动不会把它装进队列。
    var playHistory = PlayHistoryBook()
    var showPlayHistory = false
    var asksClearPlayHistory = false
    var showShortcuts = false
    // —— 歌单（2026-11-23）：用户自己建的歌单，存 playlists.json；和「当前播放列表」（队列）、「播放记录」三者分开 ——
    var library = PlaylistLibrary()
    /// 播放列表页正在看哪个歌单；nil = 当前播放列表
    var viewingPlaylistID: UUID?
    var playlistBrowseOpen: Bool { viewingPlaylistID != nil }
    /// 正在给哪个歌单起名（新建后直接进入、双击歌单名进入）
    var renamingPlaylistID: UUID?
    var isRenamingPlaylist: Bool { renamingPlaylistID != nil }
    var asksDeletePlaylist: UUID?
    @ObservationIgnored var libraryURL: URL!
    @ObservationIgnored var librarySaveWork: Task<Void, Never>?
    // —— 主题面板排序（长按进入拖动排序，只挪不删）——
    var themeOrder: [AppTheme] = ThemeOrder.resolve(saved: Prefs.object("themeOrder") as? [String])
    var isReorderingThemes = false
    // —— 生成封面「换一张」的随机数（cover-rerolls.json）——
    @ObservationIgnored var rerollURL: URL!
    // —— 播放列表行翻面看属性 / 改标签 ——
    var flippedRowID: String?
    var propertiesOpen: Bool { flippedRowID != nil }
    var tagEditorItemID: String?
    var tagEditorOpen: Bool { tagEditorItemID != nil }
    var tagSaving = false
    var fileProperties: [String: FileProperties] = [:]
    @ObservationIgnored var tagBackupDir: URL!
    @ObservationIgnored var customTagsURL: URL!
    @ObservationIgnored var customCoversDir: URL!
    // —— 耳机校正：按品牌浏览 ——
    var autoEqBrand: String?
    var autoEqBrandOpen: Bool { autoEqBrand != nil }
    var autoEqBrandIndex: AutoEq.BrandIndex?
    var autoEqBrandModels: [AutoEq.Entry] = []
    // —— 均衡器 32 路实时音频频谱缓存 ——
    var trackSpectrum: AudioSpectrum?
    @ObservationIgnored var trackSpectrumID: String?
    @ObservationIgnored var spectrumCache: [String: AudioSpectrum] = [:]
    @ObservationIgnored var spectrumTask: Task<Void, Never>?
    /// 正在往播放列表里拖文件时，插入线所在的位置
    var dropInsertIndex: Int?
    var playlistDropTargeted = false
    /// 视频画面（AppKit 视图）上正在拖入
    var videoDropTargeted = false
    /// 每次 +1：播放列表滚动到当前曲目
    var locateToken = 0

    var current: MediaItem? { queue.current }
    var isVideo: Bool { current?.kind == .video }
    /// 视频舞台：「正在播放」页上播视频时的大画面。点 / 双击视频卡、回车、在列表里播视频都会进来。
    /// 第8轮 TANCO 实测发现它没有出口（以前把它当成「不是进入的状态」豁免掉了）。现在的出口：
    /// 左上「返回」、Esc、点画面外的空白处、双指左右滑、右键「返回封面轮播」——回到封面轮播（停在这张视频卡上），视频暂停。
    /// 在轮播里再点这张视频卡 / 回车 / 按空格继续播放，就回到视频舞台。
    var videoStageOpen: Bool { isVideo && !videoStageDismissed }
    /// 封面观赏模式（状态与界面见 UI/CoverViewer.swift、PlayerController+Viewer.swift）
    let viewer = CoverViewerModel()
    private(set) var videoStageDismissed = false
    /// 进入视频舞台的时间：双击视频卡时，第二下会落在刚出现的画面上，这一下不算「双击画面 = 全屏」
    @ObservationIgnored var videoStageEnteredAt: CFTimeInterval = 0
    /// 专辑卡单击 / 双击分辨（见 PlayerController+Viewer.cardClicked）
    @ObservationIgnored var pendingCardClick: (index: Int, time: CFTimeInterval)?
    @ObservationIgnored var pendingCardWork: Task<Void, Never>?
    @ObservationIgnored var suppressCardTapUntil: CFTimeInterval = 0
    @ObservationIgnored var cardDoubleDownAt: CFTimeInterval = 0
    /// 测试用：最近一次单击翻面 / 换歌实际等了多久
    @ObservationIgnored var lastCardClickDelay: Double = 0
    func exitVideoStage() {
        guard videoStageOpen else { return }
        if let w = mainWindow, w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil) }
        if isPlaying { pause() }
        if let i = queue.currentIndex, carousel.centeredIndex != i { carousel.jump(to: i); runCarousel() }
        withAnimation(Motion.panel) { videoStageDismissed = true }
    }
    func enterVideoStage() {
        guard isVideo, videoStageDismissed else { return }
        videoStageEnteredAt = CACurrentMediaTime()
        withAnimation(Motion.panel) { videoStageDismissed = false }
    }
    /// 视频舞台上的双指横扫（VideoStage 的滚动监听调用）：一次手势里横向累计超过 70pt 就回到封面轮播
    @ObservationIgnored private var videoSwipeAccum: CGFloat = 0
    @ObservationIgnored private var videoSwipeDone = false
    func videoSwipe(dx: CGFloat, dy: CGFloat, began: Bool, ended: Bool) {
        if began { videoSwipeAccum = 0; videoSwipeDone = false }
        if !videoSwipeDone, abs(dx) >= abs(dy) {
            videoSwipeAccum += dx
            if abs(videoSwipeAccum) > 70 { videoSwipeDone = true; exitVideoStage() }
        }
        if ended { videoSwipeAccum = 0 }
    }
    var audioTracks: [MPVEngine.Track] { tracks.filter { $0.kind == .audio } }
    var subtitleTracks: [MPVEngine.Track] { tracks.filter { $0.kind == .sub } }
    var allPresets: [EQPreset] { EQPreset.builtIns + customPresets }

    // MARK: 内部
    @ObservationIgnored let videoSurface = VideoSurfaceView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
    @ObservationIgnored let covers = CoverStore()
    @ObservationIgnored var engine: MPVEngine!
    @ObservationIgnored private var nowPlaying: NowPlayingBridge?
    @ObservationIgnored var session = SessionState()
    @ObservationIgnored let sessionURL: URL
    @ObservationIgnored let historyURL: URL?
    @ObservationIgnored private var historySaveWork: Task<Void, Never>?
    @ObservationIgnored private var basePos: Double = 0
    @ObservationIgnored private var baseTime: CFTimeInterval = 0
    @ObservationIgnored private var clockID: UUID?
    @ObservationIgnored private var carouselClockID: UUID?
    @ObservationIgnored var details: [String: MediaDetails] = [:]
    @ObservationIgnored private var loading: Set<String> = []
    /// 有文件自带 / 同目录封面的曲目（解码好的封面不再长期挂在 details 里，2K 图太占内存）
    @ObservationIgnored var fileCoverIDs: Set<String> = []
    @ObservationIgnored private var saveWork: Task<Void, Never>?
    @ObservationIgnored private var hudWork: Task<Void, Never>?
    @ObservationIgnored private var chromeWork: Task<Void, Never>?
    @ObservationIgnored private var lastResumeSave: Double = 0
    @ObservationIgnored private var pendingStart: Double?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var settleWork: Task<Void, Never>?
    @ObservationIgnored private var frameBeforeMini: CGRect?
    @ObservationIgnored private var windowAnim: Timer?
    @ObservationIgnored private var styleMemo: [String: DefaultCoverStyle] = [:]
    @ObservationIgnored private var styleMemoKey: Int?
    @ObservationIgnored private var restyling: Set<String> = []

    /// 窗口尺寸动画：自己按 120Hz 逐步 setFrame（每一步都同步重画视频）。
    /// 不用 NSWindow 的 animate:true——它在主线程跑自己的动画循环，期间视频层按新尺寸失效却来不及画，
    /// 退出迷你窗时会黑 2–3 帧（2026-11-19 连拍 r3 第 16–17 张）。
    func animateWindow(_ w: NSWindow, to target: CGRect, duration: Double = 0.34) {
        windowAnim?.invalidate()
        let start = w.frame, t0 = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] t in
            let p = min(1, (CACurrentMediaTime() - t0) / duration)
            let e = 1 - pow(1 - p, 3)        // ease-out
            func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(e) }
            let f = CGRect(x: lerp(start.minX, target.minX), y: lerp(start.minY, target.minY),
                           width: lerp(start.width, target.width), height: lerp(start.height, target.height)).integral
            MainActor.assumeIsolated {
                w.setFrame(p >= 1 ? target : f, display: true)
                if p >= 1 { t.invalidate(); self?.windowAnim = nil }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        windowAnim = timer
    }
    @ObservationIgnored private var eqRampID: UUID?
    @ObservationIgnored var dropClearWork: Task<Void, Never>?

    @ObservationIgnored private var savedQueueSnapshot: PlayQueue?
    @ObservationIgnored private var userModifiedQueueInSession = false

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GlassPlayer", isDirectory: true)
        // 自测时用 -sessionPath 指到项目文件夹，不碰本人的播放列表
        let explicitSession = UserDefaults.standard.string(forKey: "sessionPath") != nil
        if let sp = UserDefaults.standard.string(forKey: "sessionPath"), !sp.isEmpty { sessionURL = URL(fileURLWithPath: sp) }
        else { sessionURL = support.appendingPathComponent("session.json") }
        if let hp = UserDefaults.standard.string(forKey: "playHistoryPath"), !hp.isEmpty {
            historyURL = URL(fileURLWithPath: hp)
        } else if Prefs.sandbox {
            historyURL = nil
        } else {
            historyURL = sessionURL.deletingLastPathComponent().appendingPathComponent(PlayHistoryStore.fileName)
        }
        let rawSaved = SessionStore.load(from: sessionURL)
        let shouldResumeQueue = explicitSession || startupMode == .resume
        if !shouldResumeQueue && !rawSaved.queue.items.isEmpty {
            savedQueueSnapshot = rawSaved.queue
        }
        session = LaunchPolicy.preparedSession(from: rawSaved, resumeQueue: shouldResumeQueue)
        if let historyURL { playHistory = PlayHistoryStore.load(from: historyURL) }
        // 启动始终落在「正在播放」页，歌单（playlists.json）与播放记录始终独立完好保留
        tab = .nowPlaying
        queue = session.queue
        let side = Self.sidecarURL(sessionURL: sessionURL, defaultDir: support, name: "playlists", explicit: explicitSession)
        libraryURL = side
        library = PlaylistLibraryStore.load(from: side)
        rerollURL = Self.sidecarURL(sessionURL: sessionURL, defaultDir: support, name: "cover-rerolls", explicit: explicitSession)
        CoverRerolls.shared.set(CoverRerollBook.load(from: rerollURL))
        let baseDataDir = explicitSession ? sessionURL.deletingLastPathComponent() : (Prefs.sandbox ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("liuli-sandbox-\(getpid())", isDirectory: true) : support)
        tagBackupDir = baseDataDir.appendingPathComponent("tag-backups", isDirectory: true)
        customTagsURL = Self.sidecarURL(sessionURL: sessionURL, defaultDir: support, name: "custom-tags", explicit: explicitSession)
        customCoversDir = baseDataDir.appendingPathComponent("custom-covers", isDirectory: true)
        CustomTags.shared.configure(book: CustomTagBook.load(from: customTagsURL), coverDir: customCoversDir)
        volume = session.volume
        muted = session.muted
        eq = session.eq
        if eq.gains.count != eq.bandCount.rawValue { eq = EQState() }
        customPresets = session.customPresets

        engine = MPVEngine(initialAudioFilter: MPVEqualizerGraph.filterString(for: eq))
        #if canImport(Libmpv)
        if let h = engine.handle { videoSurface.glLayer.attach(h) }
        #endif
        engine.onEvent = { [weak self] e in self?.handle(e) }
        engine.setDouble("volume", volume)
        engine.setFlag("mute", muted)
        watchSystemAppearance()
        videoSurface.onDoubleClick = { [weak self] in
            guard let self, CACurrentMediaTime() - self.videoStageEnteredAt > 0.6 else { return }
            self.toggleFullScreen()
        }
        videoSurface.menuProvider = { [weak self] in
            MainActor.assumeIsolated { self.map { NSMenuBuilder.build(MenuCatalog.videoSurface($0)) } }
        }
        videoSurface.onDragHover = { [weak self] on in
            MainActor.assumeIsolated { guard let self, self.videoDropTargeted != on else { return }; withAnimation(Motion.panel) { self.videoDropTargeted = on } }
        }
        videoSurface.onDropURLs = { [weak self] urls in MainActor.assumeIsolated { self?.open(urls, playNow: true) } }

        nowPlaying = NowPlayingBridge(.init(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            toggle: { [weak self] in self?.togglePlay() },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] t in self?.seek(to: t) },
            skip: { [weak self] d in self?.seek(by: d) }))

        carousel = CarouselPhysics(count: queue.items.count, index: queue.currentIndex ?? 0)
        // 恢复的列表只显示、不加载进播放器；按播放（空格 / 播放键）时才从当前曲目开头播。显式打开 / 拖入照旧交给 open(_:playNow:)。
    }

    // MARK: - 打开
    func presentOpenPanel(folders: Bool) {
        if let urls = TestHooks.openPanel(folders: folders) { if !urls.isEmpty { open(urls, playNow: true) }; return }
        let p = NSOpenPanel()
        p.canChooseFiles = !folders
        p.canChooseDirectories = folders
        p.allowsMultipleSelection = true
        p.prompt = "播放"
        p.message = folders ? "选择一个或多个文件夹，里面的音乐和视频会全部加入播放列表" : "选择音乐或视频文件"
        if !folders { p.allowedContentTypes = [.audio, .movie, .audiovisualContent, .data] }
        if p.runModal() == .OK { open(p.urls, playNow: true) }
    }

    func presentSubtitlePanel() {
        if let u = TestHooks.subtitleFile() { engine.addSubtitle(u); refreshTracksSoon(); showHUD("captions.bubble", "已加载字幕"); return }
        let p = NSOpenPanel()
        p.allowedContentTypes = MediaFormats.subtitles.compactMap { UTType(filenameExtension: $0) } + [.data]
        p.prompt = "加载字幕"
        if p.runModal() == .OK, let u = p.url { engine.addSubtitle(u); showHUD("captions.bubble", "已加载字幕") }
    }

    /// 打开文件/文件夹（拖放、Finder“打开方式”、菜单都走这里）。
    func open(_ urls: [URL], playNow: Bool) {
        // 播放列表文件（.m3u8 / .m3u / .pls）：载入其中的曲目
        if let pl = urls.first(where: { ["m3u8", "m3u", "pls"].contains($0.pathExtension.lowercased()) }), urls.count == 1 { loadPlaylist(at: pl); return }
        let files = Self.expand(urls)
        // 单独拖进来的字幕：挂到当前视频上
        let subs = urls.filter { MediaFormats.subtitles.contains($0.pathExtension.lowercased()) }
        if files.isEmpty, !subs.isEmpty, isVideo { subs.forEach { engine.addSubtitle($0) }; showHUD("captions.bubble", "已加载字幕"); return }
        guard !files.isEmpty else { showHUD("exclamationmark.circle", "没有可播放的文件"); return }
        noteRecent(urls.filter { !MediaFormats.subtitles.contains($0.pathExtension.lowercased()) })
        let items = files.map { MediaItem(url: $0) }
        let n0 = queue.items.count
        let first = queue.append(items)
        let added = queue.items.count - n0
        syncCarouselCount()
        for it in items.prefix(24) { ensureDetails(it) }
        if playNow, let f = first { play(index: f) }
        else { refreshLookahead() }
        if added == 0 { showHUD("checkmark.circle", items.count == 1 ? "这首已经在列表里了" : "这些已经都在列表里了") }
        else { showHUD("plus.circle", playNow ? "已添加 \(added) 项" : "已添加 \(added) 项 · 在卡片和列表的最后") }
        scheduleSave()
    }

    nonisolated static func expand(_ urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for u in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: u.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let e = fm.enumerator(at: u, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
                var found: [URL] = []
                while let f = e?.nextObject() as? URL { if MediaFormats.isPlayable(f) { found.append(f) } }
                found.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
                out += found
            } else if MediaFormats.isPlayable(u) {
                out.append(u)
            }
        }
        return out
    }

    // MARK: - 播放控制
    func play(index: Int, from start: Double? = nil) {
        guard queue.items.indices.contains(index) else { return }
        saveResumeForCurrent()
        queue.select(index)
        let item = queue.items[index]
        hasMedia = true
        pendingStart = start ?? resumePosition(for: item)
        engine.load(item.url, start: pendingStart)
        engine.setFlag("pause", false)
        // 播完整个列表后 mpv 进入空闲但 pause 仍是 false，这时再播不会收到 pause 变化——这里直接标成“播放中”
        if !isPlaying { isPlaying = true; startClock(); updateActivity() }
        position = pendingStart ?? 0
        basePos = position; baseTime = CACurrentMediaTime()
        duration = item.duration
        isLifted = false
        if item.kind == .video { videoStageEnteredAt = CACurrentMediaTime(); videoStageDismissed = false }
        ensureDetails(item)
        updatePaletteForCurrent()
        if !carousel.isDragging { carousel.jump(to: index); runCarousel() }
        prefetchAround(index)
        if item.kind == .video { tab = .nowPlaying }
        notePlayed(item)
        scheduleSave()
    }

    func play() {
        if isVideo && videoStageDismissed { enterVideoStage() }   // 在轮播里继续播视频：回到视频舞台
        guard hasMedia, engine.getFlag("idle-active") != true else {
            if !queue.isEmpty { play(index: queue.currentIndex ?? 0, from: 0) }
            return
        }
        engine.setFlag("pause", false)
    }
    func pause() { engine.setFlag("pause", true) }
    func togglePlay() { isPlaying ? pause() : play() }

    func next() {
        guard let n = queue.nextIndex(manual: true) else { carousel.bumpEdge(direction: 1); runCarousel(); return }
        play(index: n, from: 0)
    }

    func previous() {
        // 播放超过 3 秒：回到开头；否则上一首
        if position > 3 { seek(to: 0); return }
        guard let p = queue.previousIndex(), p != queue.currentIndex else { carousel.bumpEdge(direction: -1); runCarousel(); seek(to: 0); return }
        play(index: p, from: 0)
    }

    func seek(to t: Double) {
        let d = duration ?? .infinity
        let tt = min(max(0, t), d.isFinite ? max(0, d - 0.25) : t)
        engine.seek(absolute: tt)
        position = tt; basePos = tt; baseTime = CACurrentMediaTime()
        pushNowPlaying()
    }

    /// 快进快退时用：关键帧跳转（快），不弹提示
    func scanMove(to t: Double) {
        let tt = ScanMath.clamp(t, duration: duration)
        engine.seek(absolute: tt, exact: false)
        position = tt; basePos = tt; baseTime = CACurrentMediaTime()
    }
    /// 用户设定的实际音量（静音时为 0）
    var effectiveVolume: Double { muted ? 0 : volume }

    /// 所有固定步长的快进快退（方向键、菜单、右键、迷你窗、系统「正在播放」）统一用这个值（TANCO 2026-11-19：统一 15 秒）
    nonisolated static let seekStep: Double = 15
    func seek(by delta: Double) {
        seek(to: position + delta)
        showHUD(delta > 0 ? "goforward" : "gobackward", delta > 0 ? "快进 \(Int(abs(delta))) 秒" : "快退 \(Int(abs(delta))) 秒")
    }

    func setVolume(_ v: Double, showsHUD: Bool = false) {
        volume = min(max(0, v), 100)
        engine.setDouble("volume", volume)
        if muted && volume > 0 { setMuted(false) }
        if showsHUD { showHUD(volume == 0 ? "speaker.slash" : "speaker.wave.2", "音量 \(Int(volume.rounded()))%") }
        scheduleSave()
    }

    func setMuted(_ m: Bool) {
        muted = m
        engine.setFlag("mute", m)
        scheduleSave()
    }

    func setSpeed(_ s0: Double, hud: Bool = true) {
        let s = SpeedPitch.clampSpeed(s0)
        speed = s
        engine.setDouble("speed", s)
        if hud { showHUD("speedometer", s == 1 ? "正常速度（100%）" : "速度 \(SpeedPitch.speedText(s))（音高不变）") }
    }

    func cycleRepeat() {
        queue.repeatMode = queue.repeatMode.next
        refreshLookahead()
        showHUD(queue.repeatMode == .one ? "repeat.1" : "repeat", queue.repeatMode.label)
        scheduleSave()
    }

    func toggleShuffle() {
        queue.setShuffle(!queue.shuffle)
        refreshLookahead()
        showHUD("shuffle", queue.shuffle ? "随机播放" : "顺序播放")
        scheduleSave()
    }

    func selectAudioTrack(_ id: Int) { engine.setString("aid", String(id)); refreshTracksSoon() }
    // MARK: - 主题
    /// 切主题：所有颜色在 0.9 秒内插值过渡，背景层交叉淡入淡出（不跳变）
    func setTheme(_ t: AppTheme) {
        guard t != theme else { return }
        withAnimation(Motion.themeChange) { theme = t }
        Prefs.set(t.rawValue, "theme")
    }

    // MARK: - 输出设备（mpv 的 audio-device-list，切换时不中断播放）
    struct AudioDevice: Identifiable, Hashable { var id: String; var name: String }
    /// 设备列表会被各处右键菜单在界面刷新时反复读取：缓存 3 秒，避免每次都同步去问 mpv（会卡主线程）
    @ObservationIgnored private var deviceCache: (at: CFTimeInterval, list: [AudioDevice], current: String)?
    func audioDevices() -> [AudioDevice] {
        if let c = deviceCache, CACurrentMediaTime() - c.at < 3 { return c.list }
        let l = readAudioDevices()
        deviceCache = (CACurrentMediaTime(), l, engine.getString("audio-device") ?? "auto")
        return l
    }
    private func readAudioDevices() -> [AudioDevice] {
        guard let json = engine.getString("audio-device-list"), let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let n = d["name"] as? String else { return nil }
            let desc = (d["description"] as? String) ?? n
            return AudioDevice(id: n, name: n == "auto" ? "跟随系统" : desc)
        }.filter { $0.id == "auto" || $0.id.hasPrefix("coreaudio") }
    }
    var currentAudioDevice: String {
        if let c = deviceCache, CACurrentMediaTime() - c.at < 3 { return c.current }
        return engine.getString("audio-device") ?? "auto"
    }
    func selectAudioDevice(_ d: AudioDevice) {
        defer { deviceCache = nil }
        let prev = currentAudioDevice
        if let i = queue.currentIndex { deviceSwitch = (prev, i, position, !isPlaying, CACurrentMediaTime() + 3) }
        engine.setString("audio-device", d.id)
        showHUD("hifispeaker.fill", d.name)
    }
    /// 刚切换输出设备后 3 秒内如果这首因为“设备打不开”而结束，就切回原设备、从原位置接着放
    @ObservationIgnored var deviceSwitch: (prev: String, index: Int, pos: Double, paused: Bool, until: CFTimeInterval)?
    func recoverFromDeviceFailure() -> Bool {
        guard let s = deviceSwitch, CACurrentMediaTime() < s.until, s.index < queue.items.count else { deviceSwitch = nil; return false }
        deviceSwitch = nil; deviceCache = nil
        engine.setString("audio-device", s.prev)
        play(index: s.index, from: s.pos)
        if s.paused { after(0.4) { [weak self] in self?.pause() } }
        let name = audioDevices().first { $0.id == s.prev }?.name ?? "原设备"
        showHUD("exclamationmark.triangle", "该设备无法播放这个格式，已切回「\(name)」")
        return true
    }

    func selectSubtitle(_ id: Int?) { engine.setString("sid", id.map(String.init) ?? "no"); refreshTracksSoon() }

    func remove(at index: Int) {
        let wasCurrent = index == queue.currentIndex
        queue.remove(at: index)
        syncCarouselCount()
        if wasCurrent {
            if let c = queue.currentIndex { play(index: c, from: 0) } else { engine.stop(); hasMedia = false; isPlaying = false }
        } else { refreshLookahead() }
        scheduleSave()
    }

    func move(from: IndexSet, to: Int) {
        guard let f = from.first else { return }
        queue.move(from: f, to: to)
        syncCarouselCount()
        if let c = queue.currentIndex { carousel.jump(to: c); runCarousel() }
        refreshLookahead()
        scheduleSave()
    }

    func clearQueue() {
        engine.stop()
        queue.replace(with: [])
        hasMedia = false; isPlaying = false; duration = nil; position = 0
        syncCarouselCount()
        nowPlaying?.clear()
        scheduleSave()
    }

    func revealInFinder(_ item: MediaItem) {
        guard item.url.isFileURL else { showHUD("globe", "网络地址没有本地文件"); return }
        if TestHooks.active { TestHooks.log("reveal \(item.url.path)"); showHUD("folder", "在访达中显示"); return }   // 自测不弹访达窗口
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    // MARK: - 均衡器
    func setEQGain(_ db: Double, band: Int) {
        eq.setGain(db, band: band)
        engine.commandAsync(MPVEqualizerGraph.gainCommand(band: band, db: eq.gains[band]))
        scheduleSave()
    }

    func setPreamp(_ db: Double) {
        eq.preamp = min(max(db, EQState.preampRange.lowerBound), EQState.preampRange.upperBound)
        if eq.enabled { engine.commandAsync(MPVEqualizerGraph.preampCommand(db: eq.preamp)) }
        scheduleSave()
    }

    func applyPreset(_ p: EQPreset) {
        eq.apply(p)
        for (i, g) in eq.gains.enumerated() { engine.commandAsync(MPVEqualizerGraph.gainCommand(band: i, db: g)) }
        if !eq.enabled { setEQEnabled(true) }
        scheduleSave()
    }

    func resetEQ() {
        eq.reset()
        for i in eq.gains.indices { engine.commandAsync(MPVEqualizerGraph.gainCommand(band: i, db: 0)) }
        engine.commandAsync(MPVEqualizerGraph.preampCommand(db: 0))
        scheduleSave()
    }

    func setBandCount(_ c: EQBandCount) {
        guard c != eq.bandCount else { return }
        eq.switchBandCount(c)
        // 段数变化需要重建滤镜链（唯一一次重建；拖滑杆、开关都不重建）
        applyAudioFilters()
        scheduleSave()
    }

    /// 开关均衡器：mix 与前级在 160ms 内平滑过渡，听感上也没有“咔哒”一下的跳变。
    func setEQEnabled(_ on: Bool) {
        guard on != eq.enabled else { return }
        eq.enabled = on
        if let id = eqRampID { FrameClock.shared.unsubscribe(id) }
        let start = CACurrentMediaTime()
        let duration = 0.16
        let n = eq.gains.count
        let pre = eq.preamp
        var lastStep = -1
        eqRampID = FrameClock.shared.subscribe { [weak self] _, now in
            guard let self else { return false }
            let t = min(1, (now - start) / duration)
            let step = Int(t * 10)         // 10 级渐变，避免每帧发 32 条命令
            if step != lastStep {
                lastStep = step
                let k = on ? t : 1 - t
                let eased = k * k * (3 - 2 * k)
                for i in 0..<n { self.engine.commandAsync(MPVEqualizerGraph.mixCommand(band: i, mix: eased)) }
                self.engine.commandAsync(MPVEqualizerGraph.preampCommand(db: pre * eased))
            }
            return t < 1
        }
        scheduleSave()
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let p = EQPreset(customName: trimmed, frequencies: eq.frequencies, gains: eq.gains)
        // 同名的自定义预设：覆盖旧的，不在预设菜单里出现两个一样的名字
        let replaced = customPresets.contains { $0.name == trimmed }
        customPresets.removeAll { $0.name == trimmed }
        customPresets.append(p)
        eq.presetID = p.id
        showHUD("checkmark.circle", replaced ? "已更新预设「\(trimmed)」" : "已保存预设「\(trimmed)」")
        scheduleSave()
    }

    func deletePreset(_ p: EQPreset) {
        customPresets.removeAll { $0.id == p.id }
        if eq.presetID == p.id { eq.presetID = nil }
        scheduleSave()
    }

    // MARK: - 轮播
    /// 拖动/滚动结束后，轮播停在某张卡上
    func carouselSettled(at index: Int) {
        guard index != queue.currentIndex, queue.items.indices.contains(index) else { return }
        settleWork?.cancel()
        settleWork = after(0.12) { [weak self] in
            guard let self, self.carousel.centeredIndex == index, !self.carousel.isDragging else { return }
            if self.isPlaying { self.play(index: index) }
            else {
                self.queue.select(index)
                let item = self.queue.items[index]
                self.pendingStart = self.resumePosition(for: item)
                self.engine.load(item.url, start: self.pendingStart)
                self.engine.setFlag("pause", true)
                self.updatePaletteForCurrent()
                self.duration = item.duration
                self.position = self.pendingStart ?? 0
            }
        }
    }

    func carouselTap(_ index: Int) {
        if index == carousel.centeredIndex && index == queue.currentIndex {
            if isVideo { enterVideoStage(); if !isPlaying { play() }; return }   // 视频卡：回到视频舞台（视频卡不翻面）
            isLifted.toggle()
        } else {
            isLifted = false
            carousel.jump(to: index)
            runCarousel()
            play(index: index)
        }
    }

    func carouselBeginDrag() {
        if isLifted { exitLift(); swallowCarouselDrag = true; return }
        swallowCarouselDrag = false
        carousel.beginDrag(time: CACurrentMediaTime()); settleWork?.cancel()
    }
    func carouselDrag(deltaCards: Double) {
        if swallowCarouselDrag { return }
        let before = carousel.centeredIndex
        carousel.drag(deltaCards: deltaCards, time: CACurrentMediaTime())
        if carousel.centeredIndex != before { Haptics.tick() }
    }
    func carouselEndDrag() { if swallowCarouselDrag { swallowCarouselDrag = false; return }; carousel.endDrag(time: CACurrentMediaTime()); runCarousel() }
    func carouselStep(_ d: Int) {
        if isLifted { exitLift(); return }      // 翻着的时候先翻回，不换卡
        let t = carousel.target + d
        if t < 0 || t > carousel.maxIndex { carousel.bumpEdge(direction: d) } else { carousel.jump(to: t, gentle: false); Haptics.tick() }
        runCarousel()
    }

    /// 把轮播物理挂到 120Hz 帧时钟上，直到静止
    func runCarousel() {
        guard carouselClockID == nil else { return }
        var lastCentered = carousel.centeredIndex
        carouselClockID = FrameClock.shared.subscribe { [weak self] dt, _ in
            guard let self else { return false }
            let moving = self.carousel.tick(dt: dt)
            let c = self.carousel.centeredIndex
            if c != lastCentered { lastCentered = c; if !self.carousel.isDragging { Haptics.tick() } }
            if !moving && !self.carousel.isDragging {
                self.carouselClockID = nil
                self.carouselSettled(at: self.carousel.target)
                return false
            }
            return true
        }
    }

    func syncCarouselCount() {
        carousel.setCount(queue.items.count, keeping: queue.currentIndex ?? carousel.target)
    }

    // MARK: - 视频 / 窗口
    /// 全屏切换：
    /// - 音频曲目：全屏模式与鉴赏模式完全统一（绝不展示“放大版卡片界面”），进入全屏即同步进入全屏鉴赏，退出全屏即同步回到窗口卡片态；
    /// - 视频曲目：进入/退出沉浸视频全屏；
    /// - 空白工程：标准窗口全屏切换。
    func toggleFullScreen() {
        guard let w = mainWindow else { return }
        let full = w.styleMask.contains(.fullScreen)
        if full {
            if viewer.isOpen {
                viewer.fullscreenByViewer = true
                closeCoverViewer()
            } else {
                w.toggleFullScreen(nil)
            }
            return
        }
        // 进入全屏
        if isPinnedMini {
            togglePinnedMini()
            after(0.45) { [weak self] in self?.toggleFullScreen() }
            return
        }
        if !queue.items.isEmpty && !isVideo {
            withAnimation(Motion.panel) {
                showPlayHistory = false
                activeCard = nil
                tagEditorItemID = nil
                isLifted = false
                tab = .nowPlaying
            }
            if !viewer.isOpen {
                let src: ViewerSource = .carousel
                openCoverViewer(from: src, enterFullScreen: true)
            } else {
                viewer.fullscreenByViewer = true
            }
            w.toggleFullScreen(nil)
        } else {
            if isVideo && !videoStageOpen {
                enterVideoStage()
            }
            w.toggleFullScreen(nil)
        }
    }

    /// 主窗口是否处于系统全屏（镜像 styleMask，供界面观察；进出由系统通知 / 出现时同步）。
    var windowFullScreen = false
    func syncWindowFullScreen() {
        let prev = windowFullScreen
        let v = mainWindow?.styleMask.contains(.fullScreen) ?? false
        if windowFullScreen != v { windowFullScreen = v }
        // 若用户通过系统左上角绿色按钮直接进全屏，音频态自动同步切入鉴赏模式（绝不出现放大的卡片界面）
        if v && !prev {
            if !queue.items.isEmpty && !isVideo && !viewer.isOpen && !viewer.opening {
                withAnimation(Motion.panel) {
                    showPlayHistory = false
                    activeCard = nil
                    tagEditorItemID = nil
                    isLifted = false
                    tab = .nowPlaying
                }
                openCoverViewer(from: .carousel, enterFullScreen: true)
            }
        } else if !v && prev {
            // 退出系统全屏时同步退出鉴赏模式，无缝回到窗口卡片模式
            if viewer.isOpen && viewer.fullscreenByViewer && !viewer.closing {
                viewer.fullscreenByViewer = false
                closeCoverViewer()
            }
        }
    }

    /// 主播放窗口（设置窗口、弹层不算）
    var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }
            ?? NSApp.windows.first { $0.frameAutosaveName == "main" }
            ?? NSApp.mainWindow
    }

    func togglePinnedMini() {
        guard let w = mainWindow else { return }
        if w.styleMask.contains(.fullScreen) { w.toggleFullScreen(nil); after(0.9) { [weak self] in self?.togglePinnedMini() }; return }
        let entering = !isPinnedMini
        withAnimation(Motion.panel) { isPinnedMini = entering }
        w.level = entering || isFloating ? .floating : .normal
        w.collectionBehavior = entering ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenPrimary]
        w.isMovableByWindowBackground = entering            // 迷你窗：拖背景即可移动窗口
        // 迷你窗保留关闭 / 最小化 / 最大化三个红绿灯，全部可点（点最大化即平滑恢复主窗）
        w.styleMask.insert([.closable, .miniaturizable, .resizable])
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            if let btn = w.standardWindowButton(b) {
                btn.isHidden = false
                btn.isEnabled = true
                btn.alphaValue = 1
            }
        }
        if entering {
            frameBeforeMini = w.frame
            if !isVideo {
                w.isOpaque = false
                w.backgroundColor = .clear
                w.hasShadow = true
            }
            w.contentMinSize = CGSize(width: 340, height: 152)
            let vf = w.screen?.visibleFrame ?? .zero
            let size = isVideo ? CGSize(width: 520, height: max(200, 520 / max(0.5, videoAspect))) : CGSize(width: 452, height: 156)
            let target = CGRect(x: vf.maxX - size.width - 24, y: vf.minY + 24, width: size.width, height: size.height)
            after(0.02) { [weak self] in self?.animateWindow(w, to: target) }
        } else {
            w.isOpaque = true
            w.backgroundColor = .black
            w.contentMinSize = CGSize(width: 760, height: 520)
            if let f = frameBeforeMini { after(0.02) { [weak self] in self?.animateWindow(w, to: f) } }
            frameBeforeMini = nil
        }
        showHUD(entering ? "pip.enter" : "pip.exit", entering ? "迷你窗（置顶）" : "退出迷你窗")
    }

    /// 清除联网封面与歌词本地缓存（设置页一键清理）
    func clearOnlineCache() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: CoverService.cacheDir, includingPropertiesForKeys: nil) {
            for f in files { try? fm.removeItem(at: f) }
        }
        if let files = try? fm.contentsOfDirectory(at: LyricsService.cacheDir, includingPropertiesForKeys: nil) {
            for f in files { try? fm.removeItem(at: f) }
        }
        coverTried.removeAll()
        coverOutcome.removeAll()
        coverInfo.removeAll()
        onlineLyrics.removeAll()
        lyricsTried.removeAll()
        showHUD("trash", "已清除缓存")
    }

    /// 视频播放时鼠标静止 2.5 秒隐藏控件；动一下立刻浮现
    func pokeChrome() {
        if !chromeVisible { chromeVisible = true }
        chromeWork?.cancel()
        guard isVideo && isPlaying && tab == .nowPlaying else { return }
        chromeWork = after(2.5) { [weak self] in
            guard let self, self.isVideo, self.isPlaying, !self.isScrubbing, self.activeCard == nil else { return }
            self.chromeVisible = false
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    // MARK: - HUD
    func showHUD(_ symbol: String, _ text: String) {
        hud = HUDMessage(symbol: symbol, text: text)
        hudWork?.cancel()
        hudWork = after(1.3) { [weak self] in self?.hud = nil }
    }

    // MARK: - 封面
    func art(for item: MediaItem) -> CoverArt? {
        _ = coverVersion   // 让 SwiftUI 在封面就绪时刷新
        let a = covers.art(for: item.id)
        // 因为内存上限被清掉了：要用时重新读（文件 → 原图；联网的 → 本地缓存；默认封面 → 重画）
        if a == nil, covers.evicted.contains(item.id), !loading.contains(item.id) {
            DispatchQueue.main.async { [weak self] in self?.reloadArt(item) }
        }
        // 默认封面：歌单变了（排序、增删、邻居的专辑信息读到了）导致分配的风格变了 → 后台重画这一张
        if let a, a.isGenerated, let st = a.style, st != defaultStyle(for: item), !restyling.contains(item.id) {
            restyling.insert(item.id)
            DispatchQueue.main.async { [weak self] in self?.regenerateDefaultCover(item) }
        }
        return a
    }

    /// 默认封面风格：按歌单顺序分配（相邻不重样、同一张专辑一致），结果按歌单内容缓存
    func defaultStyle(for item: MediaItem) -> DefaultCoverStyle {
        var h = Hasher()
        for it in queue.items { h.combine(it.id); h.combine(it.coverSeed) }
        let key = h.finalize()
        if styleMemoKey != key {
            let items = queue.items
            let st = DefaultCoverStyle.assign(seeds: items.map(\.coverSeed))
            styleMemo = Dictionary(zip(items.map(\.id), st), uniquingKeysWith: { a, _ in a })
            styleMemoKey = key
        }
        return styleMemo[item.id] ?? DefaultCoverStyle.preference(seed: item.coverSeed)[0]
    }

    private func regenerateDefaultCover(_ item: MediaItem) {
        let it = details[item.id]?.item ?? item
        let st = defaultStyle(for: it)
        Task.detached(priority: .utility) { [weak self] in
            let art = await CoverStore.makeArtGated(cover: nil, item: it, style: st)
            await MainActor.run {
                guard let self else { return }
                self.restyling.remove(item.id)
                guard self.covers.art(for: item.id)?.isGenerated == true else { return }   // 期间读到了真实封面就不动
                self.covers.store(art, for: item.id)
                self.coverVersion &+= 1
                if self.queue.current?.id == item.id { self.updatePaletteForCurrent() }
            }
        }
    }

    func details(for item: MediaItem) -> MediaDetails? { details[item.id] }

    private func reloadArt(_ item: MediaItem) {
        let id = item.id
        guard covers.evicted.contains(id), covers.art(for: id) == nil, !loading.contains(id) else { return }
        loading.insert(id)
        covers.markReloading(id)
        let it = details[id]?.item ?? item
        let style = defaultStyle(for: it)
        let online = coverOutcome[id] == "online"
        let q = coverQuery(it)
        Task.detached(priority: .userInitiated) { [weak self] in
            var img: CGImage?
            var origin = "file"
            if online, case .found(let d, _, _) = await CoverService.lookupShared(q) { img = MetadataReader.decodeImage(d); origin = "online" }
            else { img = await MetadataReader.read(it).coverImage }
            let art = await CoverStore.makeArtGated(cover: img, item: it, style: style, origin: origin)
            await MainActor.run {
                guard let self else { return }
                self.loading.remove(id)
                self.covers.store(art, for: id)
                self.coverVersion &+= 1
                TestHooks.log("  封面：内存上限清掉后重新读「\(it.title)」\(art.image.width)×\(art.image.height)")
            }
        }
    }

    func ensureDetails(_ item: MediaItem) {
        guard details[item.id] == nil, !loading.contains(item.id) else { return }
        loading.insert(item.id)
        Task.detached(priority: .userInitiated) { [weak self] in
            let d = await MetadataReader.read(item)
            let style = await MainActor.run { self?.defaultStyle(for: d.item) ?? .softGlass }
            let art = await CoverStore.makeArtGated(cover: d.coverImage, item: d.item, style: style)
            await MainActor.run {
                guard let self else { return }
                self.loading.remove(item.id)
                var dd = d
                if d.coverImage != nil { self.fileCoverIDs.insert(item.id) }
                dd.coverImage = nil                 // 封面已在 CoverStore 里，不在这里再挂一份 4K 图
                self.details[item.id] = dd
                if let pr = dd.properties { self.fileProperties[item.id] = pr }
                self.queue.update(d.item)
                self.covers.store(art, for: item.id)
                self.coverVersion &+= 1
                if d.coverImage == nil { self.lookupOnlineCoverIfNeeded(d.item) }
                if self.queue.current?.id == item.id {
                    self.lyrics = d.lyrics ?? self.savedASRLyrics(for: d.item) ?? self.onlineLyrics[d.item.id]
                    self.lookupOnlineLyricsIfNeeded()
                    if self.duration == nil { self.duration = d.item.duration }
                    self.updatePaletteForCurrent()
                    self.pushNowPlaying()
                }
            }
        }
    }

    /// 预加载轮播里可见卡片的封面
    func prefetchAround(_ index: Int) {
        guard !queue.items.isEmpty else { return }
        let r = max(0, index - 5)...min(queue.items.count - 1, index + 5)
        // 轮播看得见的这几张和当前曲目：内存紧张时也不清
        covers.pinned = Set(r.compactMap { queue.items.indices.contains($0) ? queue.items[$0].id : nil } + [queue.current?.id].compactMap { $0 })
        for i in r where queue.items.indices.contains(i) {
            ensureDetails(queue.items[i])
            if covers.evicted.contains(queue.items[i].id) { reloadArt(queue.items[i]) }
        }
    }

    /// 换上一张新封面（联网查到 / 改回默认）：卡片、倒影、磨砂框、背景、播放条缩略图一起交叉淡入，不跳变
    func applyCover(_ art: CoverArt, for id: MediaItem.ID) {
        covers.store(art, for: id)
        withAnimation(.easeInOut(duration: 0.7)) {
            coverVersion &+= 1
            if queue.current?.id == id { updatePaletteForCurrent() }
        }
        if queue.current?.id == id { pushNowPlaying() }
    }

    /// 立刻撤下已显示的封面（关掉自动补封面时先拿掉官方图，再后台生成默认封面）
    func forgetDisplayedCover(_ id: MediaItem.ID) {
        covers.remove(id)
        coverVersion &+= 1
        if queue.current?.id == id { coverPalette = .fallback; coverKey = id + "-cleared" }
    }

    func updatePaletteForCurrent() {
        guard let cur = queue.current else { return }
        if let a = covers.art(for: cur.id) {
            coverPalette = a.palette
            coverKey = cur.id + "-" + a.fadeID
        }
        lyrics = details[cur.id]?.lyrics ?? savedASRLyrics(for: cur) ?? onlineLyrics[cur.id]
        lookupOnlineLyricsIfNeeded()
    }

    // MARK: - mpv 事件
    private func handle(_ e: MPVEngine.Event) {
        switch e {
        case .fileLoaded(let path):
            if let idx = queue.items.firstIndex(where: { $0.url.path == path }), idx != queue.currentIndex {
                // 无缝切到了预读的下一首
                saveResumeForCurrent()
                queue.select(idx)
                updatePaletteForCurrent()
                isLifted = false
                if !carousel.isDragging { carousel.jump(to: idx); runCarousel() }
                ensureDetails(queue.items[idx])
                scheduleSave()
            }
            pendingStart = nil
            duration = engine.getDouble("duration") ?? current?.duration
            position = engine.getDouble("time-pos") ?? 0
            basePos = position; baseTime = CACurrentMediaTime()
            refreshTracks()
            promoteToVideoIfNeeded()
            abA = nil; abB = nil; loopSeamInfo = nil; sections = []; sectionsURL = nil
            attachSavedSubtitles()
            refreshLookahead()
            updateActivity()
            pushNowPlaying()
        case .endFile(let reason):
            if reason == "error", !recoverFromDeviceFailure() { showHUD("exclamationmark.triangle", "这个文件无法播放") }
        case .idle:
            if engine.getFlag("idle-active") == true && queue.nextIndex(manual: false) == nil {
                isPlaying = false
                stopClock()
                updateActivity()
                pushNowPlaying()
            }
        case .shutdown:
            break
        case .property(let name, let v):
            switch name {
            case "pause":
                let paused = v.flag ?? true
                isPlaying = !paused && hasMedia
                basePos = position; baseTime = CACurrentMediaTime()
                isPlaying ? startClock() : stopClock()
                if !isPlaying { saveResumeForCurrent(); chromeVisible = true } else if isVideo { pokeChrome() }   // 开播即开始计时，鼠标不动 2.5 秒后控件淡出
                updateActivity()
                pushNowPlaying()
            case "time-pos":
                guard let t = v.double, !isScrubbing else { return }
                basePos = t; baseTime = CACurrentMediaTime()
                if !isPlaying { position = t }
                if abs(t - lastResumeSave) > 10 { lastResumeSave = t; saveResumeForCurrent() }
            case "duration":
                if let d = v.double, d > 0 { duration = d }
            case "volume":
                if let d = v.double, !scanVolumeOverride { volume = min(100, d) }
            case "mute":
                muted = v.flag ?? false
            case "speed":
                speed = v.double ?? 1
            case "paused-for-cache":
                isBuffering = v.flag ?? false
            case "track-list/count", "aid", "sid":
                refreshTracks()
            case "video-out-params/aspect":
                if let a = v.double, a > 0.1 { withAnimation(Motion.panel) { videoAspect = a } }
            default: break
            }
        }
    }

    func refreshTracks() { tracks = engine.tracks().filter { !$0.isAlbumArt } }
    func refreshTracksSoon() { after(0.15) { [weak self] in self?.refreshTracks() } }

    /// 在 mpv 内部播放列表里只保留 [当前, 下一首]：下一首由我们的队列逻辑（随机/循环）决定，mpv 负责无缝衔接。
    func refreshLookahead() {
        guard hasMedia else { return }
        engine.clearLookahead()
        if queue.repeatMode == .one {
            engine.setString("loop-file", "inf")
            return
        }
        engine.setString("loop-file", "no")
        if let n = queue.nextIndex(manual: false), n != queue.currentIndex {
            engine.append(queue.items[n].url)
        } else if let n = queue.nextIndex(manual: false), n == queue.currentIndex, queue.items.count == 1, queue.repeatMode == .all {
            engine.setString("loop-file", "inf")
        }
    }

    // MARK: - 120Hz 进度插值
    private func startClock() {
        guard clockID == nil else { return }
        clockID = FrameClock.shared.subscribe { [weak self] _, _ in
            guard let self else { return false }
            if !self.isScrubbing {
                var p = self.basePos + (CACurrentMediaTime() - self.baseTime) * self.speed
                if let d = self.duration, d.isFinite { p = min(p, d) }
                self.position = p
            }
            return self.isPlaying
        }
    }
    private func stopClock() {
        if let id = clockID { FrameClock.shared.unsubscribe(id) }
        clockID = nil
        position = basePos
    }

    func applyVideoAspect(_ a: Double) { if a > 0.1 && a.isFinite { videoAspect = a } }

    func beginScrub() { scrubOrigin = position; isScrubbing = true }
    func scrub(to t: Double) { if isScrubbing { position = t } }
    /// 拖动中按过 Esc（已放弃）就不再跳转
    func endScrub(at t: Double) { guard isScrubbing else { return }; isScrubbing = false; scrubOrigin = nil; seek(to: t) }
    /// 拖进度条时按 Esc：放弃这次拖动，进度回到按下时的位置
    func cancelScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        if let o = scrubOrigin { withAnimation(Motion.toggle) { position = o } }
        scrubOrigin = nil
    }

    // MARK: - 续播、持久化、系统
    private func fileKey(_ item: MediaItem) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: item.url.path)
        return ResumeBook.key(path: item.url.path, size: (attrs?[.size] as? NSNumber)?.int64Value, modified: attrs?[.modificationDate] as? Date)
    }

    private func resumePosition(for item: MediaItem) -> Double? { session.resume.position(for: fileKey(item)) }

    private func saveResumeForCurrent() {
        guard let cur = current, let d = duration else { return }
        session.resume.record(key: fileKey(cur), position: position, duration: d, kind: cur.kind)
        scheduleSave()
    }

    func scheduleSave() {
        saveWork?.cancel()
        saveWork = after(1.0) { [weak self] in self?.saveNow() }
    }

    func saveNow() {
        if !queue.items.isEmpty {
            userModifiedQueueInSession = true
            savedQueueSnapshot = nil
        }
        // 若本次是「全新空白」启动且未载入新曲目，退出时不抹掉历史快照，方便以后切到「延续上次」
        if !userModifiedQueueInSession, queue.items.isEmpty, let snap = savedQueueSnapshot {
            var preserved = snap
            preserved.repeatMode = queue.repeatMode
            preserved.setShuffle(queue.shuffle)
            session.queue = preserved
        } else {
            session.queue = queue
        }
        session.volume = volume
        session.muted = muted
        session.eq = eq
        session.customPresets = customPresets
        session.lastPosition = position
        try? SessionStore.save(session, to: sessionURL)
        saveHistoryNow()
    }

    func scheduleHistorySave() {
        historySaveWork?.cancel()
        historySaveWork = after(0.4) { [weak self] in self?.saveHistoryNow() }
    }

    func saveHistoryNow() {
        historySaveWork?.cancel(); historySaveWork = nil
        guard let historyURL else { return }
        try? PlayHistoryStore.save(playHistory, to: historyURL)
    }

    func prepareForQuit() {
        saveResumeForCurrent()
        saveNow()
        #if canImport(Libmpv)
        videoSurface.glLayer.detach()
        #endif
        engine.shutdown()
    }

    func updateActivity() {
        let needs = isPlaying && isVideo
        if needs && activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .userInitiated], reason: "正在播放视频")
        } else if !needs, let a = activity {
            ProcessInfo.processInfo.endActivity(a); activity = nil
        }
    }

    func pushNowPlaying() {
        guard let cur = current else { nowPlaying?.clear(); return }
        nowPlaying?.update(title: cur.title, artist: cur.knownArtist, album: cur.album, duration: duration,
                           position: position, rate: speed, isPlaying: isPlaying, isVideo: cur.kind == .video,
                           artwork: covers.art(for: cur.id)?.image)
    }
}

/// 主线程延时（可取消）。用 Task 代替 GCD 延时，避免 Sendable 闭包里调用主线程方法的并发告警。
@MainActor @discardableResult
func after(_ seconds: Double, _ f: @escaping @MainActor () -> Void) -> Task<Void, Never> {
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        if !Task.isCancelled { f() }
    }
}

/// 触控板轻触反馈：滑过每一张卡时“咔”一下（只在 Force Touch 触控板上有感觉）。
enum Haptics {
    @MainActor static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
