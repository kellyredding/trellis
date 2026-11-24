import Foundation

/// The Bindings tab's size, computed from its sections rather than measured:
/// every header and tile has a fixed height, so rows of tiles decide it.
struct BindingsGrid: Equatable {
    var tilesPerRow: Int
    var tileHeight: Double
    /// Between tiles, across and down.
    var tileSpacing: Double
    var headerHeight: Double
    /// Between a section's header and its first row.
    var headerSpacing: Double
    var sectionSpacing: Double

    func rows(_ section: BindingSection) -> Int {
        (section.bindings.count + tilesPerRow - 1) / tilesPerRow
    }

    func height(_ section: BindingSection) -> Double {
        let rows = Double(rows(section))
        return headerHeight + headerSpacing + rows * tileHeight + max(0, rows - 1) * tileSpacing
    }

    func height(_ sections: [BindingSection]) -> Double {
        guard !sections.isEmpty else { return 0 }
        return sections.map { height($0) }.reduce(0, +) + Double(sections.count - 1) * sectionSpacing
    }

    /// A section's bindings in rows of `tilesPerRow`.
    func chunked(_ bindings: [ChordBinding]) -> [[ChordBinding]] {
        stride(from: 0, to: bindings.count, by: tilesPerRow).map {
            Array(bindings[$0..<min($0 + tilesPerRow, bindings.count)])
        }
    }
}
