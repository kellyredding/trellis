import AppKit
import Combine

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private var subscriptions: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?
    private var shownState: MenuIconState?

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        refreshIcon()
        model.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshIcon() } }
            }
            .store(in: &subscriptions)
        appearanceObservation = item.button?.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.item.button?.needsDisplay = true }
            }
        }
    }

    private func refreshIcon() {
        let state = model.iconState
        guard state != shownState else { return }
        shownState = state
        item.button?.image = LatticeGlyph.image(for: state)
        item.button?.toolTip = "Trellis — \(state.statusLine)"
    }

    // MARK: - Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        model.accessibility.refresh()
        menu.removeAllItems()
        let state = model.iconState

        menu.addItem(disabled(state.statusLine))
        if state == .blocked {
            menu.addItem(action("Open System Settings…", #selector(requestAccessibility)))
        }
        if let error = model.configStore.error {
            let line = disabled("Config error — keeping the last good config: \(error)")
            line.toolTip = error
            menu.addItem(line)
        }
        if let problem = model.socketProblem { menu.addItem(disabled("Socket: \(problem)")) }
        if let problem = model.hotkey.problem { menu.addItem(disabled("Leader: \(problem)")) }

        menu.addItem(.separator())
        let enter = action("Enter Layout Mode", #selector(enterLayoutMode))
        let leader = model.leader
        if let character = leader.key.count == 1 ? leader.key : nil {
            enter.keyEquivalent = character
            enter.keyEquivalentModifierMask = Self.flags(leader.modifiers)
        }
        enter.isEnabled = state != .blocked
        menu.addItem(enter)

        menu.addItem(.separator())
        menu.addItem(action("Reload Config", #selector(reloadConfig)))
        let exists = FileManager.default.fileExists(atPath: model.paths.resolvedConfigFile.path)
        let open = action("Open Config File", #selector(openConfig))
        open.isEnabled = exists
        menu.addItem(open)
        let reveal = action("Reveal in Finder", #selector(revealConfig))
        reveal.isEnabled = exists
        menu.addItem(reveal)

        menu.addItem(.separator())
        let settings = action("Settings…", #selector(openSettings))
        settings.keyEquivalent = ","
        menu.addItem(settings)
        let quit = action("Quit Trellis", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: Self.truncated(title), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private static func truncated(_ text: String) -> String {
        let single = text.replacingOccurrences(of: "\n", with: " ")
        return single.count > 90 ? String(single.prefix(89)) + "…" : single
    }

    private static func flags(_ modifiers: KeyModifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.ctrl) { flags.insert(.control) }
        if modifiers.contains(.alt) { flags.insert(.option) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.cmd) { flags.insert(.command) }
        return flags
    }

    @objc private func requestAccessibility() { model.accessibility.requestFromUser() }

    @objc private func enterLayoutMode() {
        DispatchQueue.main.async { [model] in
            MainActor.assumeIsolated { model.enterLayoutMode() }
        }
    }

    @objc private func reloadConfig() { model.reloadConfig() }

    @objc private func openConfig() { NSWorkspace.shared.open(model.paths.resolvedConfigFile) }

    @objc private func revealConfig() {
        NSWorkspace.shared.activateFileViewerSelecting([model.paths.resolvedConfigFile])
    }

    @objc private func openSettings() { PreferencesWindowController.show(model: model) }

    @objc private func quit() { NSApp.terminate(nil) }
}
