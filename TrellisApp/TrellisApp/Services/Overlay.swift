import AppKit
import Combine
import SwiftUI

/// The layout-mode label: one click-through, non-activating panel per chosen
/// screen, on every Space and over full-screen apps. Each panel spans the
/// screen's visible frame, transparent, with the label in the chosen corner,
/// so the label can grow as keys are typed without resizing the window.
@MainActor
final class Overlay {
    private let layoutMode: LayoutMode
    private let configStore: ConfigStore
    private let screens: ScreenService
    private var panels: [NSPanel] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var targetScreenIndex: Int?

    init(layoutMode: LayoutMode, configStore: ConfigStore, screens: ScreenService) {
        self.layoutMode = layoutMode
        self.configStore = configStore
        self.screens = screens
        layoutMode.$isActive
            .removeDuplicates()
            .sink { [weak self] active in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { active ? self?.show() : self?.hide() }
                }
            }
            .store(in: &subscriptions)
        configStore.$config
            .map { $0?.settings.label }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.refresh() } }
            }
            .store(in: &subscriptions)
    }

    /// For `label.screens: target`: the focused window's screen, looked up
    /// off the main thread after the mode opens.
    func setTargetScreen(_ index: Int?) {
        targetScreenIndex = index
        refresh()
    }

    func refresh() {
        if layoutMode.isActive { show() }
    }

    private func show() {
        hide()
        guard layoutMode.isActive else { return }
        let label = configStore.config?.settings.label
        for screen in chosenScreens(label?.screens ?? .all) {
            let panel = makePanel(corner: label?.corner ?? .bottomRight)
            panel.setFrame(screen.visibleFrame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    private func hide() {
        for panel in panels { panel.orderOut(nil) }
        panels = []
    }

    private func chosenScreens(_ choice: LabelScreens) -> [NSScreen] {
        switch choice {
        case .all:
            return NSScreen.screens
        case .main:
            return screens.primary.map { [$0] } ?? []
        case .target:
            if let index = targetScreenIndex, let screen = screens.nsScreen(forIndex: index) { return [screen] }
            return screens.primary.map { [$0] } ?? []
        }
    }

    private func makePanel(corner: Corner) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.overlayWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:
            LayoutLabelView(layoutMode: layoutMode, configStore: configStore)
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Self.alignment(corner))
        )
        return panel
    }

    private static func alignment(_ corner: Corner) -> Alignment {
        switch corner {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }
}
