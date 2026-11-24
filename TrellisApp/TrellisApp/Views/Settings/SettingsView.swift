import SwiftUI

/// The window edits settings only, and saves each through
/// `trellis settings set KEY VALUE`; the CLI is the only writer of the config.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selected: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    SettingsTabButton(tab: tab, isSelected: selected == tab) { selected = tab }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                switch selected {
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
        .frame(width: 580)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Setting names as `trellis settings set` takes them.
enum SettingKey {
    static let leader = "leader"
    static let chordWaitMs = "chord_wait_ms"
    static let labelScreens = "label.screens"
    static let labelCorner = "label.corner"
    static let cheatSheet = "cheat_sheet"
    static let dropdownScreens = "dropdown.screens"
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var leaderText = ""
    @State private var leaderProblem: String?
    @State private var chordWait: Double = Double(Settings.defaultChordWaitMs)

    private var settings: Settings? { model.configStore.config?.settings }

    var body: some View {
        SettingsCard(title: "Startup") {
            Toggle("Start Trellis at login", isOn: Binding(
                get: { launchAtLogin },
                set: { launchAtLogin = LaunchAtLogin.set($0) }
            ))
            .toggleStyle(.checkbox)
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
                TextField(Settings.defaultLeader, text: $leaderText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                    .onSubmit(saveLeader)
                Text(KeyToken(leaderText)?.display(uppercased: true) ?? "")
                    .frame(width: 44, alignment: .leading)
                    .foregroundStyle(.secondary)
            }
            if let leaderProblem { SettingsCaption(leaderProblem, color: .red) }
            if let problem = model.hotkey.problem { SettingsCaption(problem, color: .orange) }

            SettingsRow(label: "Chord wait") {
                Slider(value: $chordWait, in: 200...1000, step: 50) { editing in
                    if !editing { model.saveSetting(SettingKey.chordWaitMs, String(Int(chordWait))) }
                }
                .frame(width: 220)
                Text("\(Int(chordWait)) ms")
                    .monospacedDigit()
                    .frame(width: 64, alignment: .trailing)
            }
            SettingsCaption("How long layout mode waits for another key when a chord could still grow.")
        }
        .disabled(settings == nil)

        SettingsCard(title: "Config") {
            SettingsRow(label: "File") {
                Text(model.paths.configFile.path).textSelection(.enabled).foregroundStyle(.secondary)
            }
            if model.paths.configIsSymlink {
                SettingsRow(label: "Resolves to") {
                    Text(model.paths.resolvedConfigFile.path).textSelection(.enabled).foregroundStyle(.secondary)
                }
            }
            SettingsRow(label: "Status") {
                Text(configStatus).foregroundStyle(model.configStore.error == nil ? Color.secondary : Color.red)
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
            SettingsRow(label: model.paths.binary.path) {
                Text(model.cliVersion ?? (model.cli.isInstalled ? "unknown version" : "not installed"))
                    .foregroundStyle(model.cli.isInstalled ? Color.secondary : Color.red)
            }
        }
        .onAppear(perform: sync)
        .onChange(of: model.configStore.config) { _, _ in sync() }
    }

    private var configStatus: String {
        guard let config = model.configStore.config else {
            return model.configStore.error == nil ? "loading…" : "not loaded"
        }
        let source = config.source == "starter" ? "starter config (no file yet)" : "valid"
        return model.configStore.error == nil ? source : "invalid — keeping the last good config"
    }

    private func sync() {
        leaderText = settings?.leader ?? Settings.defaultLeader
        chordWait = Double(settings?.chordWaitMs ?? Settings.defaultChordWaitMs)
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func saveLeader() {
        if let problem = KeyToken.leaderProblem(leaderText) {
            leaderProblem = problem
            return
        }
        leaderProblem = nil
        guard let canonical = KeyToken(leaderText)?.description, canonical != settings?.leader else { return }
        model.saveSetting(SettingKey.leader, canonical)
    }
}

// MARK: - Layout mode

struct LayoutModeSettings: View {
    @ObservedObject var model: AppModel

    private var settings: Settings? { model.configStore.config?.settings }

    var body: some View {
        SettingsCard(title: "Label") {
            picker("Show on", key: SettingKey.labelScreens, value: settings?.label.screens, labels: [
                .all: "Every screen", .main: "The main screen", .target: "The focused window's screen",
            ])
            picker("Corner", key: SettingKey.labelCorner, value: settings?.label.corner, labels: [
                .topLeft: "Top left", .topRight: "Top right", .bottomLeft: "Bottom left", .bottomRight: "Bottom right",
            ])
        }
        .disabled(settings == nil)

        SettingsCard(title: "Cheat sheet") {
            picker("Show bindings", key: SettingKey.cheatSheet, value: settings?.cheatSheet, labels: [
                .off: "Off", .label: "In the label", .dropdown: "In the dropdown",
            ])
            picker("Dropdown on", key: SettingKey.dropdownScreens, value: settings?.dropdown.screens, labels: [
                .off: "Off", .all: "Every screen", .main: "The main screen",
            ])
            SettingsCaption("The dropdown under the menu-bar icon is not built yet; these settings are saved for it.")
        }
        .disabled(settings == nil)
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
            .frame(width: 220)
        }
    }
}

// MARK: - Bindings

struct BindingsSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let config = model.configStore.config {
            SettingsCard(title: "Bindings (\(config.bindings.count))") {
                ScrollView {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                        ForEach(Array(config.bindings.enumerated()), id: \.offset) { _, binding in
                            GridRow {
                                Text(KeyToken.chordDisplay(binding.tokens))
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    .help(binding.keys)
                                PlacementThumbnail(target: binding.target, config: config)
                                Text(binding.target.description)
                                if binding.prefix {
                                    Label("waits", systemImage: "hourglass")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                        .help("A longer chord starts with this one, so it waits before running.")
                                } else {
                                    Text("")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 300)
            }
            if !config.warnings.isEmpty {
                SettingsCard(title: "Warnings") {
                    ForEach(config.warnings, id: \.self) { SettingsCaption($0, color: .orange) }
                }
            }
            SettingsCaption("Bindings are read-only here. Change them with `trellis bind` or by asking an agent.")
        } else {
            SettingsCaption(model.configStore.error ?? "No config is loaded yet.")
        }
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
            SettingsRow(label: "Version") { Text(model.version).foregroundStyle(.secondary) }
            SettingsRow(label: "Build") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")
                    .foregroundStyle(.secondary)
            }
            SettingsRow(label: "Commit") {
                Text(Bundle.main.object(forInfoDictionaryKey: "TrellisCommit") as? String ?? "development build")
                    .foregroundStyle(.secondary)
            }
            SettingsRow(label: "Signed by") { Text(CodeSigning.signer).foregroundStyle(.secondary) }
            SettingsRow(label: "Socket") {
                Text(model.paths.socket.path).textSelection(.enabled).foregroundStyle(.secondary)
            }
        }
    }
}
