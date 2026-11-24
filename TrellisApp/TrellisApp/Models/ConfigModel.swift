import Foundation

/// The normalized config from `trellis config export --json`.
///
/// MIRROR: tools/trellis/src/trellis/config/export.cr (see docs/contract.md,
/// "Config export"); fixtures/export.json pins the shape.
struct TrellisConfig: Decodable, Equatable {
    let version: Int
    let source: String
    let path: String
    let settings: Settings
    /// Display order of the Bindings tab's sections.
    let groups: [String]
    let regions: [String: Region]
    let placements: [String: Placement]
    /// Only the built-in actions the config gives a group, keyed by action name.
    let actions: [String: ActionGroup]
    let bindings: [ChordBinding]
    let warnings: [String]

    static func decode(_ data: Data) throws -> TrellisConfig {
        try JSONDecoder().decode(TrellisConfig.self, from: data)
    }

    var resolverBindings: [ResolverBinding] {
        bindings.map { ResolverBinding(chord: $0.tokens, target: $0.target) }
    }

    /// A placement's region; nil region means the bare visible frame.
    func region(for placement: Placement) -> Region? {
        guard let name = placement.region else { return Region.none }
        return regions[name]
    }

    /// Each group that has bindings, in `groups` order, with its bindings in
    /// export order (sorted by canonical chord).
    var bindingSections: [BindingSection] {
        groups.compactMap { group in
            let members = bindings.filter { $0.group == group }
            return members.isEmpty ? nil : BindingSection(group: group, bindings: members)
        }
    }
}

struct BindingSection: Equatable {
    let group: String
    let bindings: [ChordBinding]
}

struct ActionGroup: Decodable, Equatable {
    let group: String
}

enum LabelScreens: String, Codable, CaseIterable { case all, main, target }

enum Corner: String, Codable, CaseIterable {
    case topLeft = "top-left"
    case topRight = "top-right"
    case bottomLeft = "bottom-left"
    case bottomRight = "bottom-right"
}

struct Settings: Decodable, Equatable {
    struct Label: Decodable, Equatable {
        let screens: LabelScreens
        let corner: Corner
        let lingerMs: Int

        enum CodingKeys: String, CodingKey {
            case screens
            case corner
            case lingerMs = "linger_ms"
        }
    }

    let leader: String
    let chordWaitMs: Int
    let label: Label

    enum CodingKeys: String, CodingKey {
        case leader
        case chordWaitMs = "chord_wait_ms"
        case label
    }

    static let defaultLeader = "ctrl+s"
    static let defaultChordWaitMs = 600
    static let defaultLingerMs = 2000

    var leaderToken: KeyToken? { KeyToken(leader) }
}

struct Placement: Decodable, Equatable {
    let rect: Rect
    let region: String?
    let group: String
}

enum BuiltInAction: String, Codable, CaseIterable {
    case screenEast = "screen-east"
    case screenWest = "screen-west"

    var direction: Direction {
        switch self {
        case .screenEast: return .east
        case .screenWest: return .west
        }
    }
}

enum BindingTarget: Codable, Equatable, CustomStringConvertible {
    case placement(String)
    case action(BuiltInAction)

    private enum CodingKeys: String, CodingKey { case placement, action }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let placement = try container.decodeIfPresent(String.self, forKey: .placement)
        let action = try container.decodeIfPresent(BuiltInAction.self, forKey: .action)
        switch (placement, action) {
        case let (name?, nil): self = .placement(name)
        case let (nil, action?): self = .action(action)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .placement, in: container,
                debugDescription: "a target has exactly one of placement or action"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .placement(let name): try container.encode(name, forKey: .placement)
        case .action(let action): try container.encode(action, forKey: .action)
        }
    }

    var description: String {
        switch self {
        case .placement(let name): return name
        case .action(let action): return action.rawValue
        }
    }
}

/// Named apart from SwiftUI's `Binding`, which the views also use.
struct ChordBinding: Decodable, Equatable {
    let keys: String
    let chord: [String]
    let target: BindingTarget
    /// The target's group, resolved by the CLI.
    let group: String
    let prefix: Bool
    let tokens: [KeyToken]

    enum CodingKeys: String, CodingKey { case keys, chord, target, group, prefix }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        keys = try container.decode(String.self, forKey: .keys)
        chord = try container.decode([String].self, forKey: .chord)
        target = try container.decode(BindingTarget.self, forKey: .target)
        group = try container.decode(String.self, forKey: .group)
        prefix = try container.decode(Bool.self, forKey: .prefix)
        var parsed: [KeyToken] = []
        for text in chord {
            guard let token = KeyToken(text) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .chord, in: container,
                    debugDescription: "\"\(text)\" is not a key token"
                )
            }
            parsed.append(token)
        }
        guard !parsed.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .chord, in: container, debugDescription: "a chord has at least one key"
            )
        }
        tokens = parsed
    }
}
