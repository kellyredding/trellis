import Foundation

/// What the label shows for `label.linger_ms` after a chord typed in layout
/// mode runs: the chord, what it ran, and how that went.
struct ChordConfirmation: Equatable {
    enum Outcome: Equatable {
        case running
        case succeeded
        case failed(String)
    }

    let chord: [KeyToken]
    let target: BindingTarget
    var outcome: Outcome = .running

    /// `h → left-half`
    var ran: String { "\(KeyToken.chordDisplay(chord)) → \(target)" }

    /// ` ✓` or `: <the error>`; nothing while the window action runs.
    var result: String {
        switch outcome {
        case .running: return ""
        case .succeeded: return " ✓"
        case .failed(let message): return ": \(message)"
        }
    }
}
