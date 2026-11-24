import SwiftUI

enum SettingsTab: String, CaseIterable {
    case general
    case layoutMode
    case bindings
    case about

    var title: String {
        switch self {
        case .general: return "General"
        case .layoutMode: return "Layout Mode"
        case .bindings: return "Bindings"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .layoutMode: return "keyboard"
        case .bindings: return "list.bullet.rectangle"
        case .about: return "info.circle"
        }
    }
}

/// Icon over title, matching Conduit, Assist Ant and Galaxy.
struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 18))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(isSelected ? .primary : .secondary)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.1) : Color.clear)
        )
    }
}

struct SettingsCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
                    .padding(.bottom, 6)
            }
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
}

enum SettingsMetrics {
    static let tileWidth: CGFloat = 124
    static let tileSpacing: CGFloat = 8
    static let tilesPerRow = 5
    /// Fixed heights, so the Bindings tab's height is computed, not measured.
    static let bindingsGrid = BindingsGrid(
        tilesPerRow: tilesPerRow, tileHeight: 80, tileSpacing: Double(tileSpacing),
        headerHeight: 16, headerSpacing: 6, sectionSpacing: 12
    )
    /// Every tab shares the Bindings tab's width: a row of tiles, the card's
    /// and window's padding, and room for a legacy scroller.
    static let windowWidth: CGFloat =
        CGFloat(tilesPerRow) * tileWidth + CGFloat(tilesPerRow - 1) * tileSpacing + 2 * 12 + 2 * 18 + 16
    /// Every popup and slider takes this width, so they share both edges.
    static let controlWidth: CGFloat = 220
    static let readoutWidth: CGFloat = 64
}

/// Label on the left, controls flush against the trailing edge, as in Galaxy.
struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 8) {
            Text(label).lineLimit(1)
            Spacer(minLength: 12)
            content
        }
        .frame(maxWidth: .infinity, minHeight: 22)
    }
}

/// A value readout and a slider, the slider on the trailing edge so it lines
/// up with the popups in the rows around it.
struct SettingsSliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let readout: String
    let onCommit: () -> Void

    var body: some View {
        SettingsRow(label: label) {
            Text(readout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: SettingsMetrics.readoutWidth, alignment: .trailing)
            Slider(value: $value, in: range, step: step) { editing in
                if !editing { onCommit() }
            }
            .frame(width: SettingsMetrics.controlWidth)
        }
    }
}

/// Text on the trailing edge, shortened in the middle when it does not fit.
struct SettingsValue: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(color)
            .textSelection(.enabled)
            .help(text)
    }
}

struct SettingsCaption: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}
