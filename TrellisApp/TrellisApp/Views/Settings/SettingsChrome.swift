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

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            content
        }
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
