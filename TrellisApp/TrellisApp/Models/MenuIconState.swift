import Foundation

enum MenuIconState: String, CaseIterable {
    case normal
    case layout
    case blocked

    static func state(accessibilityTrusted: Bool, layoutModeActive: Bool) -> MenuIconState {
        if !accessibilityTrusted { return .blocked }
        return layoutModeActive ? .layout : .normal
    }

    var weight: LatticeWeight { self == .layout ? .halfway : .light }

    var opacity: Double { self == .blocked ? 0.35 : 1 }

    var statusLine: String {
        switch self {
        case .normal: return "Ready"
        case .layout: return "Layout mode"
        case .blocked: return "Accessibility permission needed"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .normal: return "Trellis"
        case .layout: return "Trellis, layout mode"
        case .blocked: return "Trellis, Accessibility permission needed"
        }
    }
}

/// The Crossed lattice, in an 18-unit box with y down.
struct LatticeWeight: Equatable {
    let frame: Double
    let slat: Double

    static let light = LatticeWeight(frame: 1.2, slat: 1.0)
    static let halfway = LatticeWeight(frame: 1.7, slat: 1.5)

    static let box = 18.0
    static let outerInset = 1.0
    static let outerRadius = 3.6
    static let spacing = 7.0
    static let slatOffsets = [-8, -6, -4, -2, 0, 2, 4, 6, 8]
    /// Slats overlap the frame; meeting it edge to edge left an antialiased seam.
    static let fieldOverlap = 0.3

    var innerInset: Double { LatticeWeight.outerInset + frame }
    var innerRadius: Double { max(LatticeWeight.outerRadius - frame * 0.85, 1.2) }
}
