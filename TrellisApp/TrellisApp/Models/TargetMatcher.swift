import Foundation

/// Resolves a request's window target against a window list: exactly one
/// match, or why not.
enum TargetMatcher {
    static func match(_ target: WindowTarget, in windows: [WindowInfo]) -> Result<WindowInfo, RequestError> {
        switch target {
        case .focused:
            guard let window = windows.first(where: \.focused) else {
                return .failure(.notFound("no window is focused"))
            }
            return .success(window)
        case .windowID(let id):
            guard let window = windows.first(where: { $0.id == id }) else {
                return .failure(.notFound("no window with id \(id)"))
            }
            return .success(window)
        case .app(let app, let title):
            switch filter(windows, WindowFilter(app: app, title: title)) {
            case .failure(let error):
                return .failure(error)
            case .success(let matches):
                if matches.count == 1 { return .success(matches[0]) }
                let described = title.map { "\(app) matching /\($0)/" } ?? app
                if matches.isEmpty { return .failure(.notFound("no window of \(described)")) }
                var error = RequestError(
                    code: .ambiguous, message: "\(matches.count) windows of \(described) match"
                )
                error.candidates = matches
                return .failure(error)
            }
        }
    }

    /// `app` equals the app name or bundle ID, ignoring case; `title` is a
    /// regular expression searched for in the title.
    static func filter(_ windows: [WindowInfo], _ filter: WindowFilter) -> Result<[WindowInfo], RequestError> {
        var regex: NSRegularExpression?
        if let title = filter.title {
            do {
                regex = try NSRegularExpression(pattern: title)
            } catch {
                return .failure(.badRequest("title is not a valid regular expression: \(title)"))
            }
        }
        let matches = windows.filter { window in
            if let app = filter.app, !appMatches(window, app) { return false }
            if let screen = filter.screen, window.screen != screen { return false }
            if let regex {
                let range = NSRange(window.title.startIndex..., in: window.title)
                if regex.firstMatch(in: window.title, range: range) == nil { return false }
            }
            return true
        }
        return .success(matches)
    }

    static func appMatches(_ window: WindowInfo, _ app: String) -> Bool {
        window.app.caseInsensitiveCompare(app) == .orderedSame
            || (window.bundleID?.caseInsensitiveCompare(app) == .orderedSame)
    }
}
