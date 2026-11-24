import AppKit

/// The Crossed lattice for the menu bar: monochrome, shaded per appearance.
/// Drawn through an `NSImage` drawing handler, so it redraws when the menu
/// bar's appearance changes.
enum LatticeGlyph {
    struct Ink {
        let top: NSColor
        let bottom: NSColor

        static let light = Ink(top: color(0x4A4A4E), bottom: color(0x0A0A0B))
        static let dark = Ink(top: color(0xFFFFFF), bottom: color(0xC2C2C7))
    }

    static func image(for state: MenuIconState) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            cg.setAlpha(CGFloat(state.opacity))
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            draw(cg, weight: state.weight, ink: isDark ? .dark : .light)
            cg.endTransparencyLayer()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = state.accessibilityLabel
        return image
    }

    /// In the 18-unit box, y down.
    static func draw(_ cg: CGContext, weight: LatticeWeight, ink: Ink) {
        let outer = roundedRect(LatticeWeight.outerInset, 16, LatticeWeight.outerRadius)
        let inset = weight.innerInset
        let inner = roundedRect(inset, 18 - inset * 2, weight.innerRadius)
        let o = LatticeWeight.fieldOverlap
        let field = roundedRect(inset - o, 18 - (inset - o) * 2, weight.innerRadius + o)

        let band = CGMutablePath()
        band.addPath(outer)
        band.addPath(inner)
        fill(cg, band, ink, evenOdd: true)

        cg.saveGState()
        cg.addPath(field)
        cg.clip()
        fill(cg, slats(width: weight.slat), ink)
        cg.restoreGState()
    }

    static func slats(width: Double) -> CGPath {
        let spine = CGMutablePath()
        for k in LatticeWeight.slatOffsets {
            let c = CGFloat(k) * CGFloat(LatticeWeight.spacing) / 2
            spine.move(to: CGPoint(x: -21, y: -21 + c))
            spine.addLine(to: CGPoint(x: 39, y: 39 + c))
            spine.move(to: CGPoint(x: -21, y: 39 + c))
            spine.addLine(to: CGPoint(x: 39, y: -21 + c))
        }
        return spine.copy(strokingWithWidth: CGFloat(width), lineCap: .butt, lineJoin: .miter, miterLimit: 10)
    }

    private static func roundedRect(_ origin: Double, _ side: Double, _ radius: Double) -> CGPath {
        CGPath(
            roundedRect: CGRect(x: origin, y: origin, width: side, height: side),
            cornerWidth: CGFloat(radius), cornerHeight: CGFloat(radius), transform: nil
        )
    }

    private static func fill(_ cg: CGContext, _ path: CGPath, _ ink: Ink, evenOdd: Bool = false) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [ink.top.cgColor, ink.bottom.cgColor] as CFArray,
            locations: [0, 1]
        ) else { return }
        cg.saveGState()
        cg.addPath(path)
        if evenOdd { cg.clip(using: .evenOdd) } else { cg.clip() }
        cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 1), end: CGPoint(x: 0, y: 17), options: [])
        cg.restoreGState()
    }

    private static func color(_ hex: Int) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
