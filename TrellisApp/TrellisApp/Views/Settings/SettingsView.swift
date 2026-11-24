import SwiftUI

/// The window edits settings only, and saves each through
/// `trellis settings set KEY VALUE`; the CLI is the only writer of the config.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(tab: tab, isSelected: navigation.selected == tab) { navigation.selected = tab }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                switch navigation.selected {
                case .general: GeneralSettings(model: model)
                case .layoutMode: LayoutModeSettings(model: model)
                case .bindings: BindingsSettings(model: model)
                case .about: AboutSettings(model: model)
                }
                if let error = model.settingsError {
                    SettingsCaption("Could not save: \(error)", color: .red)
                }
            }
            .padding(18)
        }
        .frame(width: SettingsMetrics.windowWidth)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Setting names as `trellis settings set` takes them.
enum SettingKey {
    static let leader = "leader"
    static let chordWaitMs = "chord_wait_ms"
    static let labelScreens = "label.screens"
    static let labelCorner = "label.corner"
    static let labelLingerMs = "label.linger_ms"
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var leaderProblem: String?
    @State private var chordWait: Double = Double(Settings.defaultChordWaitMs)

    private var settings: Settings? { model.configStore.config?.settings }
    private var leader: KeyToken? { settings?.leaderToken }
    private var defaultLeader: KeyToken { KeyToken(Settings.defaultLeader)! }

    var body: some View {
        SettingsCard(title: "Startup") {
            SettingsRow(label: "Start Trellis at login") {
                Toggle("", isOn: Binding(
                    get: { launchAtLogin },
                    set: { launchAtLogin = LaunchAtLogin.set($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            if LaunchAtLogin.requiresApproval {
                SettingsCaption("Waiting for approval in System Settings › General › Login Items.", color: .orange)
            }
        }

        SettingsCard(title: "Accessibility") {
            SettingsRow(label: model.accessibility.isTrusted ? "Permission granted" : "Permission needed") {
                Button("Open System Settings") { model.accessibility.requestFromUser() }
            }
            SettingsCaption(model.accessibility.isTrusted
                ? "Trellis can read and move windows."
                : "Trellis needs the Accessibility permission to read and move windows and to capture keys in layout mode.",
                color: model.accessibility.isTrusted ? .secondary : .orange)
        }

        SettingsCard(title: "Keys") {
            SettingsRow(label: "Leader") {
                if let leader, leader != defaultLeader {
                    Button {
                        saveLeader(defaultLeader)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to \(defaultLeader.display(uppercased: true))")
                }
                LeaderRecorder(
                    leader: leader,
                    onCapture: saveLeader,
                    onRefusal: { leaderProblem = $0 },
                    onRecordingChange: { recording in
                        if recording { leaderProblem = nil }
                        model.setCapturingLeader(recording)
                    }
                )
            }
            if let leaderProblem { SettingsCaption(leaderProblem, color: .red) }
            if let problem = model.hotkey.problem { SettingsCaption(problem, color: .orange) }

            SettingsSliderRow(
                label: "Chord wait", value: $chordWait, range: 200...1000, step: 50,
                readout: "\(Int(chordWait)) ms"
            ) {
                model.saveSetting(SettingKey.chordWaitMs, String(Int(chordWait)))
            }
            SettingsCaption("How long layout mode waits for another key when a chord could still grow.")
        }
        .disabled(settings == nil)

        SettingsCard(title: "Config") {
            SettingsRow(label: "File") { SettingsValue(text: model.paths.configFile.path) }
            if model.paths.configIsSymlink {
                SettingsRow(label: "Resolves to") { SettingsValue(text: model.paths.resolvedConfigFile.path) }
            }
            SettingsRow(label: "Status") {
                SettingsValue(text: configStatus, color: model.configStore.error == nil ? .secondary : .red)
                Button("Reload") { model.reloadConfig() }
            }
            if let error = model.configStore.error {
                SettingsCaption(error, color: .red)
            }
            ForEach(model.configStore.config?.warnings ?? [], id: \.self) { warning in
                SettingsCaption(warning, color: .orange)
            }
        }

        SettingsCard(title: "Command line") {
            SettingsRow(label: "Location") { SettingsValue(text: model.paths.binary.path) }
            SettingsRow(label: "Version") {
                SettingsValue(
                    text: model.cliVersion ?? (model.cli.isInstalled ? "unknown version" : "not installed"),
                    color: model.cli.isInstalled ? .secondary : .red
                )
            }
        }
        .onAppear(perform: sync)
        .onChange(of: model.configStore.config) { _, _ in sync() }
    }

    private var configStatus: String {
        guard let config = model.configStore.config else {
            return model.configStore.state == .loading ? "loading…" : "not loaded"
        }
        let source = config.source == "starter" ? "starter config (no file yet)" : "valid"
        return model.configStore.error == nil ? source : "invalid — keeping the last good config"
    }

    private func sync() {
        chordWait = Double(settings?.chordWaitMs ?? Settings.defaultChordWaitMs)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func saveLeader(_ token: KeyToken) {
        leaderProblem = nil
        guard token.description != settings?.leader else { return }
        model.saveSetting(SettingKey.leader, token.description)
    }
}

// MARK: - Layout mode

struct LayoutModeSettings: View {
    @ObservedObject var model: AppModel
    @State private var linger: Double = Double(Settings.defaultLingerMs)

    private var settings: Settings? { model.configStore.config?.settings }

    var body: some View {
        SettingsCard(title: "Label") {
            picker("Show on", key: SettingKey.labelScreens, value: settings?.label.screens, labels: [
                .all: "Every screen", .main: "The main screen", .target: "The focused window's screen",
            ])
            picker("Corner", key: SettingKey.labelCorner, value: settings?.label.corner, labels: [
                .topLeft: "Top left", .topRight: "Top right", .bottomLeft: "Bottom left", .bottomRight: "Bottom right",
            ])
            SettingsSliderRow(
                label: "Show result for", value: $linger, range: 0...3000, step: 100,
                readout: linger == 0 ? "Off" : "\(Int(linger)) ms"
            ) {
                model.saveSetting(SettingKey.labelLingerMs, String(Int(linger)))
            }
            SettingsCaption("How long the label stays up after a chord runs, showing what it did.")
        }
        .disabled(settings == nil)
        .onAppear(perform: sync)
        .onChange(of: model.configStore.config) { _, _ in sync() }
    }

    private func sync() {
        linger = Double(settings?.label.lingerMs ?? Settings.defaultLingerMs)
    }

    private func picker<Value: RawRepresentable & CaseIterable & Hashable>(
        _ label: String, key: String, value: Value?, labels: [Value: String]
    ) -> some View where Value.RawValue == String, Value.AllCases: RandomAccessCollection {
        SettingsRow(label: label) {
            Picker("", selection: Binding(
                get: { value ?? Value.allCases.first! },
                set: { if $0 != value { model.saveSetting(key, $0.rawValue) } }
            )) {
                ForEach(Value.allCases, id: \.self) { option in
                    Text(labels[option] ?? option.rawValue).tag(option)
                }
            }
            .labelsHidden()
            .frame(width: SettingsMetrics.controlWidth, alignment: .trailing)
        }
    }
}

// MARK: - Bindings

/// The tab grows with its bindings, up to the screen's height; only a config
/// taller than that scrolls.
struct BindingsSettings: View {
    @ObservedObject var model: AppModel

    private let grid = SettingsMetrics.bindingsGrid

    var body: some View {
        if let config = model.configStore.config {
            let sections = config.bindingSections
            SettingsCard(title: "Bindings (\(config.bindings.count))") {
                ScrollView(.vertical) {
                    content(sections, config: config)
                }
                .frame(height: min(CGFloat(grid.height(sections)), Self.maxHeight))
            }
            SettingsCaption("Bindings are read-only here. Change them with `trellis bind` or by asking an agent.")
        } else {
            SettingsCaption(model.configStore.error ?? "No config is loaded yet.")
        }
    }

    private func content(_ sections: [BindingSection], config: TrellisConfig) -> some View {
        VStack(alignment: .leading, spacing: grid.sectionSpacing) {
            ForEach(sections, id: \.group) { section in
                VStack(alignment: .leading, spacing: grid.headerSpacing) {
                    Text(section.group)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                        .frame(height: grid.headerHeight)
                    VStack(alignment: .leading, spacing: SettingsMetrics.tileSpacing) {
                        ForEach(Array(grid.chunked(section.bindings).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: SettingsMetrics.tileSpacing) {
                                ForEach(row, id: \.keys) { binding in
                                    BindingTile(binding: binding, config: config)
                                }
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The screen's visible height less the window's title bar, tab bar,
    /// padding, card title and caption, and a margin.
    @MainActor private static var maxHeight: CGFloat {
        max(200, (NSScreen.main?.visibleFrame.height ?? 800) - 260)
    }
}

/// One binding: its chord, what it does to a window, and its target's name.
struct BindingTile: View {
    let binding: ChordBinding
    let config: TrellisConfig

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(KeyToken.chordDisplay(binding.tokens))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                    .help(binding.keys)
                if binding.prefix {
                    Image(systemName: "hourglass")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("A longer chord starts with this one, so it waits before running.")
                }
            }
            PlacementThumbnail(target: binding.target, config: config)
            Text(binding.target.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .truncationMode(.middle)
                .help(binding.target.description)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .frame(width: SettingsMetrics.tileWidth, height: SettingsMetrics.bindingsGrid.tileHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }
}

/// A placement's slot on a 16:10 screen, with its region's margins shaded.
struct PlacementThumbnail: View {
    let target: BindingTarget
    let config: TrellisConfig

    var body: some View {
        Canvas { context, size in
            let screen = Rect(x: 0, y: 0, w: Double(size.width), h: Double(size.height))
            context.fill(Path(roundedRect: cg(screen), cornerRadius: 2), with: .color(.secondary.opacity(0.18)))
            switch target {
            case .placement(let name):
                guard let placement = config.placements[name],
                      let region = config.region(for: placement)
                else { return }
                let area = Geometry.area(visible: screen, region: region)
                context.stroke(Path(cg(area)), with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)
                let slot = Geometry.slot(placement.rect, visible: screen, region: region)
                context.fill(Path(roundedRect: cg(slot), cornerRadius: 1.5), with: .color(.accentColor))
            case .action(let action):
                let arrow = action.direction == .east ? "arrow.right" : "arrow.left"
                context.draw(Image(systemName: arrow), at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
        }
        .frame(width: 48, height: 30)
    }

    private func cg(_ r: Rect) -> CGRect { CGRect(x: r.x, y: r.y, width: r.w, height: r.h) }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCard(title: "Trellis") {
            SettingsRow(label: "Version") { SettingsValue(text: model.version) }
            SettingsRow(label: "Build") {
                SettingsValue(text: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
            }
            SettingsRow(label: "Commit") {
                SettingsValue(text: Bundle.main.object(forInfoDictionaryKey: "TrellisBuildCommit") as? String ?? "development build")
            }
            SettingsRow(label: "Signed by") { SettingsValue(text: CodeSigning.signer) }
            SettingsRow(label: "Socket") { SettingsValue(text: model.paths.socket.path) }
        }
    }
}
