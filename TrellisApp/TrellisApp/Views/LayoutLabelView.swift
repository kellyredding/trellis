import SwiftUI

/// The layout-mode label: `⌃S  l l` as keys are typed, and a missed chord
/// until the next key.
struct LayoutLabelView: View {
    @ObservedObject var layoutMode: LayoutMode
    @ObservedObject var configStore: ConfigStore

    /// The chord and key text in the label and the chord confirmation.
    static let keysFont = Font.system(size: 20, weight: .medium, design: .monospaced)

    static func leader(_ config: TrellisConfig?) -> String {
        let text = config?.settings.leader ?? Settings.defaultLeader
        return KeyToken(text)?.display(uppercased: true) ?? text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(Self.leader(configStore.config))
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
        .font(Self.keysFont)
        .labelChrome()
    }
}

/// `⌃S  h → left-half ✓`, or the error when the window action failed.
struct ChordConfirmationView: View {
    @ObservedObject var state: ChordConfirmationState
    @ObservedObject var configStore: ConfigStore

    var body: some View {
        if let confirmation = state.current {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(LayoutLabelView.leader(configStore.config))
                Text("  " + confirmation.ran)
                switch confirmation.outcome {
                case .running:
                    EmptyView()
                case .succeeded:
                    Text(confirmation.result).foregroundStyle(.green)
                case .failed:
                    Text(confirmation.result)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.orange)
                }
            }
            .font(LayoutLabelView.keysFont)
            .labelChrome()
        }
    }
}

private extension View {
    func labelChrome() -> some View {
        foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.78))
            )
            .fixedSize()
    }
}
