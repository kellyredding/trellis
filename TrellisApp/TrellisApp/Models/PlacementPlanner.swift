import Foundation

/// Where a window should go, from a request or a binding: the destination
/// screen, the placement's fractions and region, and the resulting frame.
enum PlacementPlanner {
    static func frame(
        for request: PlaceRequest, window: WindowInfo, screens: [ScreenInfo], config: TrellisConfig?
    ) -> Result<Rect, RequestError> {
        let unit: Rect
        let region: Region
        switch request.shape {
        case .placement(let name):
            guard let config else { return .failure(.unavailable) }
            guard let placement = config.placements[name] else {
                return .failure(.badRequest("no placement named \"\(name)\""))
            }
            guard let resolved = config.region(for: placement) else {
                return .failure(.internal("placement \"\(name)\" names a missing region"))
            }
            unit = placement.rect
            region = resolved
        case .rect(let rect, let regionName):
            unit = rect
            if let regionName {
                guard let config else { return .failure(.unavailable) }
                guard let resolved = config.regions[regionName] else {
                    return .failure(.badRequest("no region named \"\(regionName)\""))
                }
                region = resolved
            } else {
                region = .none
            }
        }
        return destination(for: window, request.screen, screens: screens).map { screen in
            Geometry.frame(unit, visible: screen.visibleFrame, region: region)
        }
    }

    static func frame(
        for target: BindingTarget, window: WindowInfo, screens: [ScreenInfo], config: TrellisConfig
    ) -> Result<Rect, RequestError> {
        switch target {
        case .placement(let name):
            let request = PlaceRequest(target: .focused, shape: .placement(name), screen: nil)
            return frame(for: request, window: window, screens: screens, config: config)
        case .action(let action):
            return move(window, action.direction, screens: screens)
        }
    }

    static func move(_ window: WindowInfo, _ direction: Direction, screens: [ScreenInfo]) -> Result<Rect, RequestError> {
        guard let current = currentScreen(of: window, screens: screens) else {
            return .failure(.notFound("the window is on no screen"))
        }
        guard let next = ScreenNeighbor.neighbor(of: current, direction, among: screens) else {
            return .failure(.notFound("no screen to the \(direction.rawValue)"))
        }
        return .success(Geometry.relocate(window.frame, from: current.visibleFrame, to: next.visibleFrame))
    }

    static func currentScreen(of window: WindowInfo, screens: [ScreenInfo]) -> ScreenInfo? {
        if let index = window.screen, let screen = screens.first(where: { $0.index == index }) {
            return screen
        }
        return ScreenNeighbor.screen(for: window.frame, among: screens)
            ?? screens.first(where: \.main) ?? screens.first
    }

    private static func destination(
        for window: WindowInfo, _ selector: ScreenSelector?, screens: [ScreenInfo]
    ) -> Result<ScreenInfo, RequestError> {
        guard let current = currentScreen(of: window, screens: screens) else {
            return .failure(.notFound("no screens"))
        }
        switch selector {
        case nil:
            return .success(current)
        case .index(let index)?:
            guard let screen = screens.first(where: { $0.index == index }) else {
                return .failure(.notFound("no screen \(index)"))
            }
            return .success(screen)
        case .direction(let direction)?:
            guard let screen = ScreenNeighbor.neighbor(of: current, direction, among: screens) else {
                return .failure(.notFound("no screen to the \(direction.rawValue)"))
            }
            return .success(screen)
        }
    }
}

extension RequestError {
    static func `internal`(_ message: String) -> RequestError {
        RequestError(code: .internal, message: message)
    }
}
