import AppKit
import Combine
import SwiftUI

/// The confirmation the overlay's panels show; nil when none is up.
@MainActor
final class ChordConfirmationState: ObservableObject {
    @Published var current: ChordConfirmation?
}

/// The layout-mode label: one click-through, non-activating panel per chosen
/// screen, on every Space and over full-screen apps. Each panel spans the
/// screen's visible frame, transparent, with the label in the chosen corner,
/// so the label can grow as keys are typed without resizing the window.
///
/// After a typed chord runs, the same screens and corner show its
/// confirmation for `label.linger_ms`; it captures nothing, and entering
/// layout mode replaces it at once.
@MainActor
final class Overlay {
    private let layoutMode: LayoutMode
    private let configStore: ConfigStore
    private let screens: ScreenService
    private var panels: [NSPanel] = []
    private var subscriptions: Set<AnyCancellable> = []
    private var targetScreenIndex: Int?

    private let confirmationState = ChordConfirmationState()
    private var confirmationPanels: [NSPanel] = []
    private var confirmationTimer: Timer?
    private var confirmationID = 0

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

    // MARK: - Confirmation

    /// Shows the chord while its window action runs, replacing any earlier
    /// confirmation. Nil when `label.linger_ms` is 0; otherwise pass the id to
    /// `finishConfirmation`, which ignores an id a newer chord has replaced.
    func beginConfirmation(_ confirmation: ChordConfirmation) -> Int? {
        dismissConfirmation()
        let label = configStore.config?.settings.label
        guard (label?.lingerMs ?? Settings.defaultLingerMs) > 0, !layoutMode.isActive else { return nil }
        confirmationID += 1
        confirmationState.current = confirmation
        for screen in chosenScreens(label?.screens ?? .all) {
            let panel = makePanel(corner: label?.corner ?? .bottomRight) {
                ChordConfirmationView(state: confirmationState, configStore: configStore)
            }
            panel.setFrame(screen.visibleFrame, display: true)
            panel.orderFrontRegardless()
            confirmationPanels.append(panel)
        }
        return confirmationID
    }

    /// Shows the outcome and starts the linger timer.
    func finishConfirmation(_ id: Int?, _ outcome: ChordConfirmation.Outcome) {
        guard let id, id == confirmationID, confirmationState.current != nil else { return }
        confirmationState.current?.outcome = outcome
        let lingerMs = configStore.config?.settings.label.lingerMs ?? Settings.defaultLingerMs
        let timer = Timer(timeInterval: Double(lingerMs) / 1000, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissConfirmation() }
        }
        RunLoop.main.add(timer, forMode: .common)
        confirmationTimer = timer
    }

    private func dismissConfirmation() {
        confirmationTimer?.invalidate()
        confirmationTimer = nil
        for panel in confirmationPanels { panel.orderOut(nil) }
        confirmationPanels = []
        confirmationState.current = nil
    }

    // MARK: - Panels

    private func show() {
        hide()
        dismissConfirmation()
        guard layoutMode.isActive else { return }
        let label = configStore.config?.settings.label
        for screen in chosenScreens(label?.screens ?? .all) {
            let panel = makePanel(corner: label?.corner ?? .bottomRight) {
                LayoutLabelView(layoutMode: layoutMode, configStore: configStore)
            }
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

    private func makePanel<Content: View>(corner: Corner, @ViewBuilder content: () -> Content) -> NSPanel {
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
            content()
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
