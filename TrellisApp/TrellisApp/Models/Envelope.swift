import Foundation

// MIRROR: tools/trellis/src/trellis/socket_client.cr (see docs/contract.md,
// "Socket")

enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var integer: Int? {
        guard let number, number == number.rounded(), abs(number) < 1e15 else { return nil }
        return Int(number)
    }

    var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    var isNull: Bool { self == .null }
}

enum ErrorCode: String, Codable {
    case badRequest = "bad_request"
    case notPermitted = "not_permitted"
    case notFound = "not_found"
    case ambiguous
    case unavailable
    case `internal`
}

struct RequestError: Error, Equatable {
    let code: ErrorCode
    let message: String
    var candidates: [WindowInfo]? = nil

    static func badRequest(_ message: String) -> RequestError {
        RequestError(code: .badRequest, message: message)
    }

    static func notFound(_ message: String) -> RequestError {
        RequestError(code: .notFound, message: message)
    }

    static let notPermitted = RequestError(
        code: .notPermitted, message: "Accessibility permission is not granted"
    )

    static let unavailable = RequestError(code: .unavailable, message: "no config is loaded")
}

// MARK: - Window and screen objects

struct WindowInfo: Codable, Equatable {
    let id: Int
    let app: String
    let bundleID: String?
    let pid: Int
    let title: String
    let frame: Rect
    let screen: Int?
    let focused: Bool
    let minimized: Bool

    enum CodingKeys: String, CodingKey {
        case id, app
        case bundleID = "bundle_id"
        case pid, title, frame, screen, focused, minimized
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(app, forKey: .app)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(pid, forKey: .pid)
        try container.encode(title, forKey: .title)
        try container.encode(frame, forKey: .frame)
        try container.encode(screen, forKey: .screen)
        try container.encode(focused, forKey: .focused)
        try container.encode(minimized, forKey: .minimized)
    }
}

struct ScreenInfo: Codable, Equatable {
    let index: Int
    let uuid: String
    let name: String
    let frame: Rect
    let visibleFrame: Rect
    let scale: Double
    let main: Bool

    enum CodingKeys: String, CodingKey {
        case index, uuid, name, frame
        case visibleFrame = "visible_frame"
        case scale, main
    }
}

enum Direction: String, Codable, Equatable { case east, west }

// MARK: - Requests

struct RequestEnvelope: Decodable {
    let v: Int
    let event: String
    let ts: Int64?
    let detailData: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case v, event, ts
        case detailData = "detail_data"
    }
}

enum WindowTarget: Equatable {
    case focused
    case windowID(Int)
    case app(String, title: String?)
}

enum ScreenSelector: Equatable {
    case index(Int)
    case direction(Direction)
}

struct WindowFilter: Equatable {
    var app: String?
    var title: String?
    var screen: Int?
}

struct PlaceRequest: Equatable {
    enum Shape: Equatable {
        case placement(String)
        case rect(Rect, region: String?)
    }

    let target: WindowTarget
    let shape: Shape
    let screen: ScreenSelector?
}

enum TrellisRequest: Equatable {
    case status
    case screens
    case windows(WindowFilter)
    case place(PlaceRequest)
    case screenMove(WindowTarget, Direction)
    case chord(String)
    case configReload

    static func parse(_ line: Data) -> Result<TrellisRequest, RequestError> {
        let envelope: RequestEnvelope
        do {
            envelope = try JSONDecoder().decode(RequestEnvelope.self, from: line)
        } catch {
            return .failure(.badRequest("the request is not a valid envelope"))
        }
        guard envelope.v == 1 else {
            return .failure(.badRequest("unsupported envelope version \(envelope.v)"))
        }
        do {
            return .success(try parse(event: envelope.event, detail: envelope.detailData ?? [:]))
        } catch let error as RequestError {
            return .failure(error)
        } catch {
            return .failure(.badRequest(error.localizedDescription))
        }
    }

    private static func parse(event: String, detail: [String: JSONValue]) throws -> TrellisRequest {
        switch event {
        case "status": return .status
        case "screens": return .screens
        case "config.reload": return .configReload
        case "windows":
            return .windows(WindowFilter(
                app: try optionalString(detail, "app"),
                title: try optionalString(detail, "title"),
                screen: try optionalInteger(detail, "screen")
            ))
        case "place":
            return .place(try parsePlace(detail))
        case "screen.move":
            guard let raw = detail["direction"]?.string, let direction = Direction(rawValue: raw) else {
                throw RequestError.badRequest("direction must be \"east\" or \"west\"")
            }
            return .screenMove(try parseTarget(detail["target"]), direction)
        case "chord":
            guard let keys = detail["keys"]?.string else {
                throw RequestError.badRequest("chord needs keys")
            }
            return .chord(keys)
        default:
            throw RequestError.badRequest("unknown event \"\(event)\"")
        }
    }

    private static func parsePlace(_ detail: [String: JSONValue]) throws -> PlaceRequest {
        let target = try parseTarget(detail["target"])
        let placement = try optionalString(detail, "placement")
        let region = try optionalString(detail, "region")
        let rectValue = detail["rect"].flatMap { $0.isNull ? nil : $0 }
        let shape: PlaceRequest.Shape
        switch (placement, rectValue) {
        case (let name?, nil):
            if region != nil { throw RequestError.badRequest("region goes with rect, not placement") }
            shape = .placement(name)
        case (nil, let value?):
            let rect = try parseRect(value)
            if let problem = Geometry.validatePlacementRect(rect) {
                throw RequestError.badRequest(problem)
            }
            shape = .rect(rect, region: region)
        default:
            throw RequestError.badRequest("place takes exactly one of placement or rect")
        }
        var screen: ScreenSelector?
        switch detail["screen"] {
        case nil, .null?:
            screen = nil
        case .string(let text)?:
            guard let direction = Direction(rawValue: text) else {
                throw RequestError.badRequest("screen must be an index, \"east\" or \"west\"")
            }
            screen = .direction(direction)
        case let value?:
            guard let index = value.integer else {
                throw RequestError.badRequest("screen must be an index, \"east\" or \"west\"")
            }
            screen = .index(index)
        }
        return PlaceRequest(target: target, shape: shape, screen: screen)
    }

    static func parseTarget(_ value: JSONValue?) throws -> WindowTarget {
        guard let value, !value.isNull else { return .focused }
        guard let object = value.object else { throw RequestError.badRequest("target must be an object") }
        let id = object["window_id"].flatMap { $0.isNull ? nil : $0 }
        let app = try optionalString(object, "app")
        let title = try optionalString(object, "title")
        if let id {
            guard app == nil, title == nil else {
                throw RequestError.badRequest("target takes window_id or app, not both")
            }
            guard let number = id.integer else { throw RequestError.badRequest("window_id must be an integer") }
            return .windowID(number)
        }
        if let app { return .app(app, title: title) }
        if title != nil { throw RequestError.badRequest("a title target also needs app") }
        return .focused
    }

    private static func parseRect(_ value: JSONValue) throws -> Rect {
        guard let object = value.object,
              let x = object["x"]?.number, let y = object["y"]?.number,
              let w = object["w"]?.number, let h = object["h"]?.number
        else { throw RequestError.badRequest("rect must be {x, y, w, h}") }
        return Rect(x: x, y: y, w: w, h: h)
    }

    private static func optionalString(_ detail: [String: JSONValue], _ key: String) throws -> String? {
        switch detail[key] {
        case nil, .null?: return nil
        case .string(let text)?: return text
        default: throw RequestError.badRequest("\(key) must be a string")
        }
    }

    private static func optionalInteger(_ detail: [String: JSONValue], _ key: String) throws -> Int? {
        switch detail[key] {
        case nil, .null?: return nil
        case let value?:
            guard let number = value.integer else { throw RequestError.badRequest("\(key) must be an integer") }
            return number
        }
    }
}

// MARK: - Replies

enum ConfigLoadState: String, Encodable {
    case loading, loaded, failed

    init(hasConfig: Bool, finishedFirstLoad: Bool) {
        self = hasConfig ? .loaded : finishedFirstLoad ? .failed : .loading
    }
}

struct StatusData: Encodable {
    struct Config: Encodable {
        let path: String
        let source: String?
        let state: ConfigLoadState
        let error: String?

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(path, forKey: .path)
            try container.encode(source, forKey: .source)
            try container.encode(state == .loaded, forKey: .loaded)
            try container.encode(state, forKey: .state)
            try container.encode(error, forKey: .error)
        }

        enum CodingKeys: String, CodingKey { case path, source, loaded, state, error }
    }

    let version: String
    let pid: Int
    let accessibility: Bool
    let layoutMode: Bool
    let config: Config

    enum CodingKeys: String, CodingKey {
        case version, pid, accessibility
        case layoutMode = "layout_mode"
        case config
    }
}

struct ScreensData: Encodable { let screens: [ScreenInfo] }
struct WindowsData: Encodable { let windows: [WindowInfo] }
struct WindowData: Encodable { let window: WindowInfo }

struct ChordData: Encodable {
    let keys: String
    let target: BindingTarget?
    let ran: Bool

    enum CodingKeys: String, CodingKey { case keys, target, ran }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keys, forKey: .keys)
        try container.encode(target, forKey: .target)
        try container.encode(ran, forKey: .ran)
    }
}

struct ReloadData: Encodable {
    let loaded: Bool
    let error: String?

    enum CodingKeys: String, CodingKey { case loaded, error }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(loaded, forKey: .loaded)
        try container.encode(error, forKey: .error)
    }
}

/// One JSON line, without its terminating newline.
enum Reply {
    private struct Success<T: Encodable>: Encodable {
        let ok = true
        let data: T
    }

    private struct Failure: Encodable {
        let ok = false
        let error: String
        let code: ErrorCode
        let candidates: [WindowInfo]?
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }

    static func ok<T: Encodable>(_ data: T) -> Data {
        do {
            return try encoder.encode(Success(data: data))
        } catch {
            return failure(RequestError(code: .internal, message: "could not encode the reply"))
        }
    }

    static func failure(_ error: RequestError) -> Data {
        let body = Failure(error: error.message, code: error.code, candidates: error.candidates)
        return (try? encoder.encode(body))
            ?? Data(#"{"ok":false,"error":"could not encode the reply","code":"internal"}"#.utf8)
    }
}
