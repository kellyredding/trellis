import AppKit
import SwiftUI

/// A capture field that records one keystroke as the new leader, after
/// Galactic's `KeystrokeRecorder`: click to arm, press a keystroke, Escape to
/// cancel.
///
/// A local `NSEvent` monitor only sees keys already routed to this window, so
/// recording cannot claim a chord system-wide; every key it sees while armed
/// is consumed.
struct LeaderRecorder: View {
    let leader: KeyToken?
    let onCapture: (KeyToken) -> Void
    let onRefusal: (String) -> Void
    let onRecordingChange: (Bool) -> Void

    @State private var isRecording = false
    @State private var isHovering = false
    @State private var monitor: Any?

    /// Fixed so the field does not resize under the pointer when it arms.
    static let width: CGFloat = 120

    private var borderColor: Color {
        if isRecording { return .accentColor }
        return isHovering ? Color(NSColor.labelColor) : Color(NSColor.tertiaryLabelColor)
    }

    private var textColor: Color {
        if isRecording { return Color(NSColor.secondaryLabelColor) }
        return Color(NSColor.labelColor)
    }

    var body: some View {
        Button {
            if isRecording { teardown() } else { arm() }
        } label: {
            Text(isRecording ? "Press a key…" : leader?.display(uppercased: true) ?? "—")
                .font(.system(size: isRecording ? 11 : 13, design: .monospaced))
                .lineLimit(1)
                .foregroundColor(textColor)
                .frame(width: Self.width, height: 18)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color(NSColor.controlBackgroundColor)))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(borderColor, lineWidth: isRecording ? 1.5 : 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isRecording ? "Press the new leader, or Escape to cancel" : "Click, then press the new leader")
        .onHover { inside in
            isHovering = inside
            if inside { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            if isRecording { teardown() }
        }
        .onDisappear {
            teardown()
            if isHovering { NSCursor.arrow.set() }
        }
    }

    private func arm() {
        guard monitor == nil else { return }
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = KeyModifiers(deviceFlags: event.modifierFlags.rawValue)
            let outcome = LeaderCapture.interpret(keyCode: event.keyCode, modifiers: modifiers)
            DispatchQueue.main.async {
                teardown()
                switch outcome {
                case .cancel: break
                case .refuse(let message): onRefusal(message)
                case .capture(let token): onCapture(token)
                }
            }
            return nil
        }
    }

    private func teardown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard isRecording else { return }
        isRecording = false
        onRecordingChange(false)
    }
}
