// 胭脂 Yanzhi Player — Copyright © 2026 Luna Fantasy Lab
// 源码公开·非商业许可：PolyForm Noncommercial 1.0.0（见 LICENSE.md 与 NOTICE）
// 禁止任何形式的商业使用（包括售卖、收费分发、用于商业产品或接单），商用须获得 Luna Fantasy Lab 书面授权。
// Source-available, non-commercial. ANY commercial use (selling, paid distribution, use in commercial
// products or client work) is prohibited without written permission from Luna Fantasy Lab.

import SwiftUI
import AppKit

/// 一份菜单数据，三处复用：菜单栏（SwiftUI Commands）、SwiftUI 右键菜单、AppKit 右键菜单（视频画面）。
/// 自测时也直接遍历它，保证“看到的每一项”都被实际触发过。
struct MenuNode {
    enum Kind { case action(@MainActor () -> Void), submenu([MenuNode]), divider, header }
    var title: String
    var symbol: String?
    var key: KeyEquivalent?
    var mods: EventModifiers = []
    var checked: Bool?
    var enabled = true
    var destructive = false
    /// 会弹出系统面板/对话框的项（自测时走预设答案）
    var opensPanel = false
    var kind: Kind

    static func item(_ title: String, _ symbol: String? = nil, key: KeyEquivalent? = nil, mods: EventModifiers = .command,
                     checked: Bool? = nil, enabled: Bool = true, destructive: Bool = false, panel: Bool = false,
                     _ action: @escaping @MainActor () -> Void) -> MenuNode {
        MenuNode(title: title, symbol: symbol, key: key, mods: mods, checked: checked, enabled: enabled, destructive: destructive, opensPanel: panel, kind: .action(action))
    }
    static func menu(_ title: String, _ symbol: String? = nil, enabled: Bool = true, _ children: [MenuNode]) -> MenuNode {
        MenuNode(title: title, symbol: symbol, enabled: enabled && !children.isEmpty, kind: .submenu(children))
    }
    static var divider: MenuNode { MenuNode(title: "", kind: .divider) }
    static func header(_ t: String) -> MenuNode { MenuNode(title: t, enabled: false, kind: .header) }

    /// 展开成 (路径, 节点) 列表，自测用
    func flatten(prefix: String = "") -> [(String, MenuNode)] {
        let path = prefix.isEmpty ? title : prefix + " ▸ " + title
        switch kind {
        case .action: return [(path, self)]
        case .submenu(let c): return c.flatMap { $0.flatten(prefix: path) }
        default: return []
        }
    }
}

extension Array where Element == MenuNode {
    func flatten(prefix: String) -> [(String, MenuNode)] { flatMap { $0.flatten(prefix: prefix) } }
}

// MARK: - SwiftUI 渲染
struct MenuContent: View {
    private let make: @MainActor () -> [MenuNode]
    var shortcuts = true
    init(nodes: @autoclosure @escaping @MainActor () -> [MenuNode], shortcuts: Bool = true) {
        self.make = nodes; self.shortcuts = shortcuts
    }
    var body: some View {
        let nodes = make()
        ForEach(Array(nodes.enumerated()), id: \.offset) { _, n in
            node(n)
        }
    }

    @ViewBuilder private func node(_ n: MenuNode) -> some View {
        switch n.kind {
        case .divider: Divider()
        case .header: Text(n.title)
        case .submenu(let children):
            Menu { MenuContent(nodes: children, shortcuts: shortcuts) } label: { label(n) }
                .disabled(!n.enabled)
        case .action(let act):
            if let c = n.checked {
                Toggle(isOn: Binding(get: { c }, set: { _ in act() })) { label(n) }
                    .modifier(Shortcut(key: shortcuts ? n.key : nil, mods: n.mods))
                    .disabled(!n.enabled)
            } else {
                Button(role: n.destructive ? .destructive : nil) { act() } label: { label(n) }
                    .modifier(Shortcut(key: shortcuts ? n.key : nil, mods: n.mods))
                    .disabled(!n.enabled)
            }
        }
    }

    @ViewBuilder private func label(_ n: MenuNode) -> some View {
        if let s = n.symbol { Label(n.title, systemImage: s) } else { Text(n.title) }
    }

    private struct Shortcut: ViewModifier {
        let key: KeyEquivalent?
        let mods: EventModifiers
        func body(content: Content) -> some View {
            if let key { content.keyboardShortcut(key, modifiers: mods) } else { content }
        }
    }
}

// MARK: - AppKit 渲染（视频画面是 NSView，右键走这里；自测也用它来真正触发 NSMenuItem）
final class BlockMenuItem: NSMenuItem {
    let block: @MainActor () -> Void
    init(title: String, block: @escaping @MainActor () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc func fire() { MainActor.assumeIsolated { block() } }
}

@MainActor
enum NSMenuBuilder {
    static func build(_ nodes: [MenuNode], title: String = "") -> NSMenu {
        let m = NSMenu(title: title)
        m.autoenablesItems = false
        for n in nodes {
            switch n.kind {
            case .divider: m.addItem(.separator())
            case .header:
                m.addItem(NSMenuItem.sectionHeader(title: n.title))
            case .submenu(let c):
                let it = NSMenuItem(title: n.title, action: nil, keyEquivalent: "")
                it.submenu = build(c, title: n.title)
                it.isEnabled = n.enabled
                decorate(it, n)
                m.addItem(it)
            case .action(let act):
                let it = BlockMenuItem(title: n.title, block: act)
                it.isEnabled = n.enabled
                if let c = n.checked { it.state = c ? .on : .off }
                if let k = n.key {
                    it.keyEquivalent = String(k.character).lowercased()
                    var f: NSEvent.ModifierFlags = []
                    if n.mods.contains(.command) { f.insert(.command) }
                    if n.mods.contains(.shift) { f.insert(.shift) }
                    if n.mods.contains(.option) { f.insert(.option) }
                    if n.mods.contains(.control) { f.insert(.control) }
                    it.keyEquivalentModifierMask = f
                }
                decorate(it, n)
                m.addItem(it)
            }
        }
        return m
    }

    private static func decorate(_ it: NSMenuItem, _ n: MenuNode) {
        if let s = n.symbol { it.image = NSImage(systemSymbolName: s, accessibilityDescription: nil) }
    }
}
