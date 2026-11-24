import Foundation

/// What one key press means to the settings window's leader recorder.
enum LeaderCapture: Equatable {
    case cancel
    case refuse(String)
    case capture(KeyToken)

    static let escapeKeyCode: UInt16 = 53

    static func interpret(keyCode: UInt16, modifiers: KeyModifiers) -> LeaderCapture {
        if keyCode == escapeKeyCode, modifiers.isEmpty { return .cancel }
        guard let token = KeyCodes.token(keyCode: keyCode, modifiers: modifiers) else {
            return .refuse("That key cannot be the leader")
        }
        if let problem = KeyToken.leaderProblem(token.description) { return .refuse(problem) }
        return .capture(token)
    }
}
