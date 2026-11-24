import Foundation

/// Screen ordering, which screen a window is on, and `screen-east` /
/// `screen-west`. All frames in global top-left points.
enum ScreenNeighbor {
    /// Indexes from 1, left to right, then top to bottom.
    static func order(_ frames: [Rect]) -> [Int] {
        let sorted = frames.indices.sorted { a, b in
            let fa = frames[a], fb = frames[b]
            if fa.x != fb.x { return fa.x < fb.x }
            return fa.y < fb.y
        }
        var indexes = Array(repeating: 0, count: frames.count)
        for (position, original) in sorted.enumerated() { indexes[original] = position + 1 }
        return indexes
    }

    /// The screen holding the window's centre, else the one it overlaps most.
    static func screen(for frame: Rect, among screens: [ScreenInfo]) -> ScreenInfo? {
        if let holder = screens.first(where: { $0.frame.contains(x: frame.midX, y: frame.midY) }) {
            return holder
        }
        let best = screens.max { $0.frame.intersectionArea(frame) < $1.frame.intersectionArea(frame) }
        guard let best, best.frame.intersectionArea(frame) > 0 else { return nil }
        return best
    }

    /// The nearest screen whose frame lies wholly to the east (west); no
    /// wrap-around.
    static func neighbor(of current: ScreenInfo, _ direction: Direction, among screens: [ScreenInfo]) -> ScreenInfo? {
        let tolerance = 0.5
        let candidates = screens.filter { other in
            guard other.index != current.index else { return false }
            switch direction {
            case .east: return other.frame.minX >= current.frame.maxX - tolerance
            case .west: return other.frame.maxX <= current.frame.minX + tolerance
            }
        }
        func distance(_ other: ScreenInfo) -> (Double, Double) {
            let horizontal = direction == .east
                ? other.frame.minX - current.frame.maxX
                : current.frame.minX - other.frame.maxX
            return (horizontal, abs(other.frame.midY - current.frame.midY))
        }
        return candidates.min { distance($0) < distance($1) }
    }
}
