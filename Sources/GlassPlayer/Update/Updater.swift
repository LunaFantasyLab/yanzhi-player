// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import AppKit
import SwiftUI
import Sparkle

/// 「检查更新」：只有本人点了（菜单栏 琉璃 ▸ 检查更新…，或设置里的按钮）才联网。
/// - 启动时不创建更新器、不联网、没有后台定时任务；Info.plist 里 SUEnableAutomaticChecks / SUAutomaticallyUpdate /
///   SUAllowsAutomaticUpdates / SUEnableSystemProfiling 全是 NO，也就不会出现 Sparkle 的首次启动询问。
/// - 不发系统通知、不在程序坞加角标、不弹提示框：所有结果只显示在本人打开的那个「检查更新」小窗里。
/// - 更新包必须通过 EdDSA 签名校验（公钥 SUPublicEDKey 在 Info.plist，私钥不在源码里）才会安装；由本人点「安装并重启」。
/// - 更新源地址是配置项：启动参数 / 偏好 updateFeedURL 优先，其次 Info.plist 的 LiuliUpdateFeedURL；都没配就只提示“还没有设置更新源”。
@MainActor @Observable
final class UpdateModel {
    enum Phase: Equatable {
        case idle, notConfigured, checking, upToDate
        case found(version: String, size: UInt64)
        case downloading(Double?), extracting(Double), installing
        case failed(String)
    }
    static let shared = UpdateModel()
    var phase: Phase = .idle
    var notes = ""
    /// 本人已经点了「安装并重启」：下载、校验、解压完后直接安装，不再问第二遍
    var wantsInstall = false

    var currentVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?" }
    var currentBuild: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?" }

    /// 自测用：临时换一个更新源
    var feedOverride: String?
    var feedURL: String? {
        if let s = feedOverride, !s.isEmpty { return s }
        if let s = UserDefaults.standard.string(forKey: "updateFeedURL"), !s.isEmpty { return s }
        if let s = Bundle.main.object(forInfoDictionaryKey: "LiuliUpdateFeedURL") as? String, !s.isEmpty { return s }
        return nil
    }

    private var updater: SPUUpdater?
    private let driver = LiuliUserDriver()
    private let delegate = LiuliUpdaterDelegate()
    var isInstantiated: Bool { updater != nil }
    var sessionInProgress: Bool { updater?.sessionInProgress ?? false }
    var busy: Bool {
        switch phase { case .checking, .downloading, .extracting, .installing: return true; default: return false }
    }
    // Sparkle 交给界面的回调
    var foundReply: ((SPUUserUpdateChoice) -> Void)?
    var readyReply: ((SPUUserUpdateChoice) -> Void)?
    var cancelAction: (() -> Void)?
    var expected: UInt64 = 0
    var received: UInt64 = 0

    /// 本人点「检查更新…」
    func checkNow() {
        UpdateWindow.shared.show()
        guard !busy else { return }
        guard feedURL != nil else { phase = .notConfigured; return }
        // 自测沙盒里用的是本人同一个 App 标识：Sparkle 会往本人的偏好里写检查时间，所以自测时不连（更新流程在单独的测试副本里测）
        if Prefs.sandbox, Bundle.main.bundleIdentifier == "com.tanco.glassplayer" {
            phase = .failed("自测模式下不检查更新（完整流程在单独的测试副本里测）"); return
        }
        if updater == nil {
            let u = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: delegate)
            do { try u.start() } catch { phase = .failed("更新组件没能启动：\(error.localizedDescription)"); return }
            u.automaticallyChecksForUpdates = false
            u.automaticallyDownloadsUpdates = false
            u.sendsSystemProfile = false
            updater = u
        }
        if let u = updater, u.sessionInProgress { return }      // 上一次还没结束：窗口已经在前面，不重复发起
        wantsInstall = false; notes = ""
        phase = .checking
        updater?.checkForUpdates()
    }

    /// 「安装并重启」
    func install() {
        wantsInstall = true
        if let r = readyReply { readyReply = nil; phase = .installing; r(.install); return }
        if let r = foundReply { foundReply = nil; phase = .downloading(nil); r(.install) }
    }
    /// 「以后再说」/「取消」/ 关窗。关掉小窗后更新流程回到空闲（安装中除外）。
    func dismiss() {
        if let r = foundReply { foundReply = nil; r(.dismiss) }
        if let r = readyReply { readyReply = nil; r(.dismiss) }
        switch phase {
        case .checking, .downloading, .extracting: cancelAction?(); cancelAction = nil; phase = .idle
        case .installing: break
        default: phase = .idle
        }
    }
    func skip() {
        if let r = foundReply { foundReply = nil; r(.skip) }
        phase = .idle
    }

    static func friendly(_ e: Error) -> String {
        let ns = e as NSError
        var chain: [NSError] = [ns]
        while let u = chain.last?.userInfo[NSUnderlyingErrorKey] as? NSError, chain.count < 6 { chain.append(u) }
        if chain.contains(where: { $0.domain == NSURLErrorDomain && Net.offlineCodes.contains(URLError.Code(rawValue: $0.code)) }) {
            return "连不上更新服务器（可能没有联网）。联网后再点「检查更新」就行，听歌不受影响。"
        }
        let sigCodes = [Int(SUError.signatureError.rawValue), Int(SUError.validationError.rawValue)]
        if chain.contains(where: { $0.domain == SUSparkleErrorDomain && sigCodes.contains($0.code) })
            || ns.localizedDescription.contains("签名") || ns.localizedDescription.lowercased().contains("signed") {
            return "更新包签名校验没有通过，已经丢弃，没有安装。"
        }
        if ns.domain == SUSparkleErrorDomain, ns.code == Int(SUError.downloadError.rawValue) { return "更新包没有下载下来，稍后再试。" }
        return ns.localizedDescription
    }
}

final class LiuliUpdaterDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? { MainActor.assumeIsolated { UpdateModel.shared.feedURL } }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func feedParameters(for updater: SPUUpdater, sendingSystemProfile sendingProfile: Bool) -> [[String: String]] { [] }
}

/// 自己的界面驱动：不用 Sparkle 自带的弹窗，所有状态只进「检查更新」小窗
final class LiuliUserDriver: NSObject, SPUUserDriver {
    private func ui(_ f: @MainActor (UpdateModel) -> Void) { MainActor.assumeIsolated { f(UpdateModel.shared) } }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        ui { $0.cancelAction = cancellation; $0.phase = .checking }
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        ui { m in
            m.foundReply = reply
            m.notes = UpdateWindow.plain(appcastItem.itemDescription ?? "")
            m.phase = .found(version: appcastItem.displayVersionString, size: appcastItem.contentLength)
            UpdateWindow.shared.show()
        }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        let s = String(data: downloadData.data, encoding: .utf8) ?? ""
        ui { $0.notes = UpdateWindow.plain(s) }
    }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        ui { $0.phase = .upToDate }
        acknowledgement()
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        ui { m in m.phase = .failed(UpdateModel.friendly(error)); m.foundReply = nil; m.readyReply = nil }
        acknowledgement()
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        ui { $0.cancelAction = cancellation; $0.expected = 0; $0.received = 0; $0.phase = .downloading(nil) }
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { ui { $0.expected = expectedContentLength } }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        ui { m in m.received += length; m.phase = .downloading(m.expected > 0 ? min(1, Double(m.received) / Double(m.expected)) : nil) }
    }
    func showDownloadDidStartExtractingUpdate() { ui { $0.phase = .extracting(0) } }
    func showExtractionReceivedProgress(_ progress: Double) { ui { $0.phase = .extracting(progress) } }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        ui { m in
            if m.wantsInstall { m.phase = .installing; reply(.install) }
            else { m.readyReply = reply; m.phase = .found(version: "", size: 0) }
        }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        ui { $0.phase = .installing }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func showUpdateInFocus() { ui { _ in UpdateWindow.shared.show() } }
    func dismissUpdateInstallation() {
        ui { m in m.cancelAction = nil; m.foundReply = nil; m.readyReply = nil; if m.busy, m.phase != .installing { m.phase = .idle } }
    }
}

/// 「检查更新」小窗（一个普通窗口，本人关掉就结束；不弹提示框、不发通知）
@MainActor
final class UpdateWindow: NSObject, NSWindowDelegate {
    static let shared = UpdateWindow()
    private var window: NSWindow?
    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 230), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "检查更新"
            w.identifier = NSUserInterfaceItemIdentifier("update")
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: UpdateView())
            w.delegate = self
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }
    func close() { window?.performClose(nil) }
    func windowWillClose(_ notification: Notification) { UpdateModel.shared.dismiss() }

    /// 更新说明：去掉 HTML 标签，只留文字
    nonisolated static func plain(_ html: String) -> String {
        var s = html.replacingOccurrences(of: "<br\\s*/?>|</p>|</li>", with: "\n", options: .regularExpression)
        s = s.replacingOccurrences(of: "<li>", with: "· ")
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct UpdateView: View {
    @State private var m = UpdateModel.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    Text("当前版本 \(m.currentVersion)（\(m.currentBuild)）· © 唐可创研").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Group {
                switch m.phase {
                case .downloading(let p): progress(p, "正在下载更新包…")
                case .extracting(let p): progress(p, "正在校验签名并解压…")
                case .installing: progress(nil, "正在安装，马上重启…")
                case .checking: progress(nil, "正在连接更新源…")
                default: Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            if case .found = m.phase, !m.notes.isEmpty {
                ScrollView { Text(m.notes).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 80)
            }
            Spacer(minLength: 0)
            HStack {
                Text("只在你点了以后才联网；不推送、不通知、不收集数据。").font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                buttons
            }
        }
        .padding(.horizontal, 20).padding(.top, 30).padding(.bottom, 16)
        .frame(width: 420, height: 230, alignment: .topLeading)
        .background(VisualEffectBackground())
        .onExitCommand { UpdateModel.shared.dismiss(); UpdateWindow.shared.close() }
    }

    private var title: String {
        switch m.phase {
        case .idle: return "检查更新"
        case .notConfigured: return "还没有设置更新源"
        case .checking: return "正在检查更新…"
        case .upToDate: return "已经是最新版本"
        case .found(let v, _): return v.isEmpty ? "更新已准备好" : "有新版本 \(v)"
        case .downloading, .extracting: return "正在下载更新"
        case .installing: return "正在安装"
        case .failed(let m): return m.contains("签名") ? "更新包没通过校验" : "这次没能检查更新"
        }
    }
    private var detail: String {
        switch m.phase {
        case .notConfigured: return "正式的更新地址还没定。定好后填进配置（updateFeedURL），这里就能检查了。"
        case .upToDate: return "你用的就是最新版本。"
        case .found(_, let size): return size > 0 ? String(format: "更新包 %.1f MB，签名校验通过后才会安装。", Double(size) / 1_048_576) : "签名校验通过后才会安装。"
        case .failed(let s): return s
        default: return "点「检查更新」看看有没有新版本。"
        }
    }
    @ViewBuilder private var buttons: some View {
        switch m.phase {
        case .found:
            Button("以后再说") { m.dismiss() }
            Button("安装并重启") { m.install() }.keyboardShortcut(.defaultAction)
        case .checking, .downloading, .extracting:
            Button("取消") { m.dismiss() }
        case .installing:
            EmptyView()
        default:
            Button("检查更新") { m.checkNow() }.keyboardShortcut(.defaultAction)
        }
    }
    private func progress(_ p: Double?, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p { ProgressView(value: p) } else { ProgressView().progressViewStyle(.linear) }
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView(); v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active; return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}
