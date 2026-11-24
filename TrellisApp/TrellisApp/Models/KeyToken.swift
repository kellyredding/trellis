import Foundation

/// MIRROR: tools/trellis/src/trellis/keys.cr (see docs/contract.md, "Key names")
struct KeyModifiers: OptionSet, Hashable {
    let rawValue: Int

    static let ctrl = KeyModifiers(rawValue: 1 << 0)
    static let alt = KeyModifiers(rawValue: 1 << 1)
    static let shift = KeyModifiers(rawValue: 1 << 2)
    static let cmd = KeyModifiers(rawValue: 1 << 3)

    static let canonical: [(modifier: KeyModifiers, name: String, symbol: String)] = [
        (.ctrl, "ctrl", "⌃"), (.alt, "alt", "⌥"), (.shift, "shift", "⇧"), (.cmd, "cmd", "⌘"),
    ]

    static let names: [String: KeyModifiers] = [
        "ctrl": .ctrl, "control": .ctrl,
        "alt": .alt, "opt": .alt, "option": .alt,
        "shift": .shift,
        "cmd": .cmd, "command": .cmd,
    ]
}

extension KeyModifiers {
    /// From an `NSEvent.modifierFlags` raw value, keeping only the four a key
    /// token names: caps lock, fn and the keypad flag would otherwise make the
    /// same keystroke read differently from one press to the next.
    init(deviceFlags raw: UInt) {
        self = []
        if raw & (1 << 18) != 0 { insert(.ctrl) }
        if raw & (1 << 19) != 0 { insert(.alt) }
        if raw & (1 << 17) != 0 { insert(.shift) }
        if raw & (1 << 20) != 0 { insert(.cmd) }
    }
}

/// Zero or more modifiers and one key, e.g. `ctrl+cmd+h`.
struct KeyToken: Hashable, CustomStringConvertible {
    let modifiers: KeyModifiers
    let key: String

    static let letters = (UInt8(ascii: "a")...UInt8(ascii: "z")).map { String(UnicodeScalar($0)) }
    static let digits = (0...9).map(String.init)
    static let punctuation = ["`", "-", "=", "[", "]", "\\", ";", "'", ",", ".", "/"]
    static let namedKeys = [
        "return", "space", "tab", "escape", "delete", "left", "right", "up", "down",
        "home", "end", "pageup", "pagedown",
    ] + (1...12).map { "f\($0)" }
    static let validKeys = Set(letters + digits + punctuation + namedKeys)

    init?(modifiers: KeyModifiers, key: String) {
        guard KeyToken.validKeys.contains(key) else { return nil }
        self.modifiers = modifiers
        self.key = key
    }

    /// Case-insensitive; modifier aliases accepted in any order.
    init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
            .map(String.init)
        guard let key = parts.last else { return nil }
        var modifiers = KeyModifiers()
        for name in parts.dropLast() {
            guard let modifier = KeyModifiers.names[name] else { return nil }
            modifiers.insert(modifier)
        }
        self.init(modifiers: modifiers, key: key)
    }

    var description: String {
        let names = KeyModifiers.canonical.filter { modifiers.contains($0.modifier) }.map(\.name)
        return (names + [key]).joined(separator: "+")
    }

    /// `⌃h`, `⌘↩`; `uppercased` gives the leader's `⌃S`.
    func display(uppercased: Bool = false) -> String {
        let symbols = KeyModifiers.canonical.filter { modifiers.contains($0.modifier) }
            .map(\.symbol).joined()
        return symbols + KeyToken.keySymbol(key, uppercased: uppercased)
    }

    static func keySymbol(_ key: String, uppercased: Bool = false) -> String {
        switch key {
        case "return": return "↩"
        case "space": return "␣"
        case "tab": return "⇥"
        case "escape": return "⎋"
        case "delete": return "⌫"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "home": return "↖"
        case "end": return "↘"
        case "pageup": return "⇞"
        case "pagedown": return "⇟"
        default:
            if key.count > 1 { return key.uppercased() }
            return uppercased ? key.uppercased() : key
        }
    }

    /// One or more tokens separated by single spaces.
    static func chord(_ text: String) -> [KeyToken]? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var tokens: [KeyToken] = []
        for part in trimmed.split(separator: " ", omittingEmptySubsequences: false) {
            guard let token = KeyToken(String(part)) else { return nil }
            tokens.append(token)
        }
        return tokens
    }

    static func canonicalChord(_ text: String) -> String? {
        chord(text).map(chordDescription)
    }

    static func chordDescription(_ tokens: [KeyToken]) -> String {
        tokens.map(\.description).joined(separator: " ")
    }

    static func chordDisplay(_ tokens: [KeyToken]) -> String {
        tokens.map { $0.display() }.joined(separator: " ")
    }

    /// A leader must carry a modifier, and escape is reserved for leaving
    /// layout mode.
    static func leaderProblem(_ text: String) -> String? {
        guard let token = KeyToken(text) else { return "\"\(text)\" is not a key token" }
        if token.modifiers.isEmpty { return "the leader needs at least one modifier" }
        if token.key == "escape" { return "escape leaves layout mode and cannot be the leader" }
        return nil
    }
}

/// ANSI virtual key codes. Letters and punctuation are by key position, so a
/// non-US layout reads as its US equivalent.
enum KeyCodes {
    static let byCode: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        36: "return", 37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "n", 46: "m", 47: ".", 48: "tab", 49: "space", 50: "`", 51: "delete",
        53: "escape", 76: "return",
        96: "f5", 97: "f6", 98: "f7", 99: "f3", 100: "f8", 101: "f9", 103: "f11",
        109: "f10", 111: "f12", 115: "home", 116: "pageup", 118: "f4", 119: "end",
        120: "f2", 121: "pagedown", 122: "f1", 123: "left", 124: "right", 125: "down",
        126: "up",
    ]

    static let byKey: [String: UInt16] = {
        var map: [String: UInt16] = [:]
        for (code, key) in byCode where map[key] == nil || code < map[key]! {
            map[key] = code
        }
        return map
    }()

    static func token(keyCode: UInt16, modifiers: KeyModifiers) -> KeyToken? {
        guard let key = byCode[keyCode] else { return nil }
        return KeyToken(modifiers: modifiers, key: key)
    }
}
