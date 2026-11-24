import Foundation

/// `{x, y, w, h}` on the wire: a frame in points, or a placement's fractions.
struct Rect: Codable, Equatable, Hashable, CustomStringConvertible {
    var x: Double
    var y: Double
    var w: Double
    var h: Double

    var minX: Double { x }
    var minY: Double { y }
    var maxX: Double { x + w }
    var maxY: Double { y + h }
    var midX: Double { x + w / 2 }
    var midY: Double { y + h / 2 }

    var description: String { "(\(x), \(y), \(w), \(h))" }

    func contains(x px: Double, y py: Double) -> Bool {
        px >= minX && px < maxX && py >= minY && py < maxY
    }

    func intersectionArea(_ other: Rect) -> Double {
        let width = min(maxX, other.maxX) - max(minX, other.minX)
        let height = min(maxY, other.maxY) - max(minY, other.minY)
        return width > 0 && height > 0 ? width * height : 0
    }
}

struct Margins: Codable, Equatable {
    var top: Double
    var right: Double
    var bottom: Double
    var left: Double

    static let zero = Margins(top: 0, right: 0, bottom: 0, left: 0)
}

struct Gap: Codable, Equatable {
    var x: Double
    var y: Double

    static let zero = Gap(x: 0, y: 0)
}

struct Region: Codable, Equatable {
    var margins: Margins
    var gap: Gap

    static let none = Region(margins: .zero, gap: .zero)
}

/// See docs/contract.md, "Geometry". Every frame here is in global top-left
/// points, the space of the Accessibility API.
enum Geometry {
    static let tolerance = 1e-9

    static func area(visible v: Rect, region: Region) -> Rect {
        let m = region.margins
        return Rect(
            x: v.x + m.left * v.w,
            y: v.y + m.top * v.h,
            w: v.w * (1 - m.left - m.right),
            h: v.h * (1 - m.top - m.bottom)
        )
    }

    /// The contract's steps 1–3, before rounding.
    static func slot(_ rect: Rect, visible v: Rect, region: Region) -> Rect {
        let a = area(visible: v, region: region)
        var left = a.x + rect.x * a.w
        var top = a.y + rect.y * a.h
        var right = left + rect.w * a.w
        var bottom = top + rect.h * a.h
        let halfX = region.gap.x * v.w / 2
        let halfY = region.gap.y * v.h / 2
        if rect.x > tolerance { left += halfX }
        if rect.x + rect.w < 1 - tolerance { right -= halfX }
        if rect.y > tolerance { top += halfY }
        if rect.y + rect.h < 1 - tolerance { bottom -= halfY }
        return Rect(x: left, y: top, w: right - left, h: bottom - top)
    }

    static func frame(_ rect: Rect, visible: Rect, region: Region) -> Rect {
        rounded(slot(rect, visible: visible, region: region))
    }

    /// Edges are rounded rather than origin and size, so two slots sharing an
    /// edge still share it after rounding.
    static func rounded(_ r: Rect) -> Rect {
        let left = r.minX.rounded(), top = r.minY.rounded()
        let right = r.maxX.rounded(), bottom = r.maxY.rounded()
        return Rect(x: left, y: top, w: right - left, h: bottom - top)
    }

    static func validatePlacementRect(_ r: Rect) -> String? {
        if r.x < 0 || r.y < 0 { return "rect x and y must be at least 0" }
        if r.w <= 0 || r.h <= 0 { return "rect w and h must be greater than 0" }
        if r.x + r.w > 1 + tolerance || r.y + r.h > 1 + tolerance {
            return "rect must fit within 1 (x + w ≤ 1, y + h ≤ 1)"
        }
        return nil
    }

    /// AppKit's bottom-left space → global top-left. `primaryHeight` is the
    /// height of the screen at AppKit's origin (the one with the menu bar).
    static func globalFromAppKit(_ r: Rect, primaryHeight: Double) -> Rect {
        Rect(x: r.x, y: primaryHeight - r.y - r.h, w: r.w, h: r.h)
    }

    static func appKitFromGlobal(_ r: Rect, primaryHeight: Double) -> Rect {
        Rect(x: r.x, y: primaryHeight - r.y - r.h, w: r.w, h: r.h)
    }

    /// Keeps a window's position and size as fractions of the visible frame.
    static func relocate(_ frame: Rect, from source: Rect, to destination: Rect) -> Rect {
        let fx = (frame.x - source.x) / source.w
        let fy = (frame.y - source.y) / source.h
        let fw = frame.w / source.w
        let fh = frame.h / source.h
        return rounded(Rect(
            x: destination.x + fx * destination.w,
            y: destination.y + fy * destination.h,
            w: fw * destination.w,
            h: fh * destination.h
        ))
    }
}
