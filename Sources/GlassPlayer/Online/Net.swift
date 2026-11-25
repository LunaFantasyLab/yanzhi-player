// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import Foundation

/// 联网请求统一走这里：
/// - 不落盘的会话：不往 ~/Library/Caches、HTTPStorages 写 HTTP 缓存和 Cookie（封面、歌词有自己的缓存）
/// - 断网时安静失败：一旦发现没网（连不上、找不到服务器、超时），90 秒内所有联网功能直接放弃、不再发请求，
///   不反复重试刷流量；90 秒后有人用到联网功能时再试一次。
/// - 自测用的「模拟断网」开关（只在 -testSandbox YES 的自测里生效，不碰系统网络设置）
enum Net {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _offlineUntil = Date.distantPast
    nonisolated(unsafe) private static var _attempts = 0
    nonisolated(unsafe) private static var _simulateOffline = Prefs.sandbox && UserDefaults.standard.bool(forKey: "simulateOffline")
    static let backoff: TimeInterval = 90

    /// 自测里模拟断网（正式使用时这个开关永远是关的）
    static var simulateOffline: Bool {
        get { lock.withLock { _simulateOffline } }
        set { lock.withLock { _simulateOffline = newValue && Prefs.sandbox } }
    }
    /// 真正发出去的请求次数（自测统计“断网时有没有反复重试”）
    static var attempts: Int { lock.withLock { _attempts } }
    /// 最近确认没网，在退避时间内
    static var isOffline: Bool { lock.withLock { Date() < _offlineUntil } }
    static func resetOffline() { lock.withLock { _offlineUntil = .distantPast } }

    static let offlineCodes: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                                                   .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed, .secureConnectionFailed]

    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.urlCache = nil
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.waitsForConnectivity = false
        c.protocolClasses = [OfflineSimulator.self] + (c.protocolClasses ?? [])
        return URLSession(configuration: c)
    }()

    static func data(for r: URLRequest) async throws -> (Data, URLResponse) {
        if isOffline { throw URLError(.notConnectedToInternet) }
        lock.withLock { _attempts += 1 }
        do { return try await session.data(for: r) }
        catch let e as URLError where offlineCodes.contains(e.code) {
            lock.withLock { _offlineUntil = Date().addingTimeInterval(backoff) }
            throw e
        }
    }
    static func data(from u: URL) async throws -> (Data, URLResponse) { try await data(for: URLRequest(url: u)) }

    /// 给界面用的一句话：断网就说断网，其他错误原样
    static func describe(_ e: Error) -> String {
        if let u = e as? URLError, offlineCodes.contains(u.code) { return "没有联网" }
        return e.localizedDescription
    }
}

/// 模拟断网：自测开关打开时，所有请求立刻以“未连接到互联网”失败（和真断网时系统给的错误一样）
final class OfflineSimulator: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { Net.simulateOffline }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
