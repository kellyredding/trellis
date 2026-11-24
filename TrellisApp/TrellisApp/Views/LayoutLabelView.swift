import SwiftUI

/// The layout-mode label: `⌃S  l l` as keys are typed, a missed chord until
/// the next key, and the cheat sheet when settings put it in the label.
struct LayoutLabelView: View {
    @ObservedObject var layoutMode: LayoutMode
    @ObservedObject var configStore: ConfigStore

    private var leader: String {
        let text = configStore.config?.settings.leader ?? Settings.defaultLeader
        return KeyToken(text)?.display(uppercased: true) ?? text
    }

    private var showsCheatSheet: Bool { configStore.config?.settings.cheatSheet == .label }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(leader)
                if !layoutMode.typed.isEmpty {
                    Text("  " + KeyToken.chordDisplay(layoutMode.typed))
                }
                if let missed = layoutMode.missed {
                    Text("  " + KeyToken.chordDisplay(missed))
                        .strikethrough()
                        .foregroundStyle(.white.opacity(0.55))
                    Text("  not bound")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .font(.system(size: 20, weight: .medium, design: .rounded))

            if showsCheatSheet, let bindings = configStore.config?.bindings, !bindings.isEmpty {
                Divider().overlay(Color.white.opacity(0.25))
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                    ForEach(Array(bindings.enumerated()), id: \.offset) { _, binding in
                        GridRow {
                            Text(KeyToken.chordDisplay(binding.tokens))
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                            Text(binding.target.description)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.78))
        )
        .fixedSize()
    }
}
