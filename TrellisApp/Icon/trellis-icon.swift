// Draws Trellis's app icon: the Crossed lattice at its light weight, ivory with
// depth, on Kx's dark icon body. Each size is drawn from the geometry rather
// than resampled. Run by `make icon`:
//
//   swift Icon/trellis-icon.swift <appiconset dir>

import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: trellis-icon.swift <appiconset dir>\n".data(using: .utf8)!)
    exit(2)
}
let directory = CommandLine.arguments[1]

// MARK: - Colour

struct Ink {
    let top: Int
    let bottom: Int
}

let bodyInk = Ink(top: 0x2E2E2C, bottom: 0x121211)
let ivory = Ink(top: 0xF6F2EA, bottom: 0xCBC3B3)

func color(_ value: Int, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
        green: CGFloat((value >> 8) & 0xFF) / 255,
        blue: CGFloat(value & 0xFF) / 255,
        alpha: alpha
    )
}

func gradient(_ ink: Ink) -> CGGradient {
    CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
        colors: [color(ink.top), color(ink.bottom)] as CFArray, locations: [0, 1]
    )!
}

// MARK: - The lattice, in an 18-unit box with y down

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
}

func latticeSlats(spacing: CGFloat, width: CGFloat) -> CGPath {
    let spine = CGMutablePath()
    for k in [-8, -6, -4, -2, 0, 2, 4, 6, 8] {
        let c = CGFloat(k) * spacing / 2
        spine.move(to: CGPoint(x: -21, y: -21 + c))
        spine.addLine(to: CGPoint(x: 39, y: 39 + c))
        spine.move(to: CGPoint(x: -21, y: 39 + c))
        spine.addLine(to: CGPoint(x: 39, y: -21 + c))
    }
    return spine.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
}

/// A vertical two-stop gradient from y 1 to 17, clipped to the path.
func fill(_ cg: CGContext, _ path: CGPath, _ ink: Ink, alpha: CGFloat = 1, evenOdd: Bool = false) {
    cg.saveGState()
    cg.setAlpha(alpha)
    cg.addPath(path)
    if evenOdd { cg.clip(using: .evenOdd) } else { cg.clip() }
    cg.drawLinearGradient(gradient(ink), start: CGPoint(x: 0, y: 1), end: CGPoint(x: 0, y: 17), options: [])
    cg.restoreGState()
}

struct Weight {
    let frame: CGFloat
    let slat: CGFloat

    func draw(_ cg: CGContext, _ ink: Ink, paneAlpha: CGFloat = 0) {
        let outer = roundedRect(1, 1, 16, 16, 3.6)
        let inset = 1 + frame
        let innerRadius = max(3.6 - frame * 0.85, 1.2)
        let inner = roundedRect(inset, inset, 18 - inset * 2, 18 - inset * 2, innerRadius)
        let o: CGFloat = 0.3
        let field = roundedRect(inset - o, inset - o, 18 - (inset - o) * 2, 18 - (inset - o) * 2, innerRadius + o)
        let band = CGMutablePath()
        band.addPath(outer)
        band.addPath(inner)
        fill(cg, band, ink, evenOdd: true)
        if paneAlpha > 0 { fill(cg, field, ink, alpha: paneAlpha) }
        cg.saveGState()
        cg.addPath(field)
        cg.clip()
        fill(cg, latticeSlats(spacing: 7, width: slat), ink)
        cg.restoreGState()
    }
}

let light = Weight(frame: 1.2, slat: 1.0)

// MARK: - The body: an 824-point superellipse (exponent 5) on a 1024 canvas

func body() -> CGPath {
    let path = CGMutablePath()
    let half: CGFloat = 412
    let exponent: CGFloat = 5
    for step in 0...720 {
        let angle = CGFloat(step) / 720 * 2 * .pi
        let c = cos(angle), s = sin(angle)
        let point = CGPoint(
            x: 512 + half * copysign(pow(abs(c), 2 / exponent), c),
            y: 512 + half * copysign(pow(abs(s), 2 / exponent), s)
        )
        if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
    }
    path.closeSubpath()
    return path
}

/// The lattice's 16-unit frame spans 580 of the 1024 canvas, centred.
let unit: CGFloat = 580 / 16

func draw(_ cg: CGContext, size: Int) {
    // Shadows are measured in the bitmap's pixels, y up, whatever the
    // transform, so they are scaled by hand.
    let factor = CGFloat(size) / 1024

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10 * factor), blur: 24 * factor, color: color(0x000000, alpha: 0.35))
    cg.addPath(body())
    cg.setFillColor(color(bodyInk.bottom))
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(body())
    cg.clip()
    cg.drawLinearGradient(gradient(bodyInk), start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
    cg.restoreGState()

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -8 * factor), blur: 18 * factor, color: color(0x000000, alpha: 0.55))
    cg.beginTransparencyLayer(auxiliaryInfo: nil)
    cg.translateBy(x: 512 - 9 * unit, y: 512 - 9 * unit)
    cg.scaleBy(x: unit, y: unit)
    light.draw(cg, ivory, paneAlpha: 0.22)
    cg.endTransparencyLayer()
    cg.restoreGState()
}

func render(size: Int) -> Data {
    let context = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let factor = CGFloat(size) / 1024
    context.translateBy(x: 0, y: CGFloat(size))
    context.scaleBy(x: factor, y: -factor)
    draw(context, size: size)
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

for size in [16, 32, 64, 128, 256, 512, 1024] {
    try render(size: size).write(to: URL(fileURLWithPath: "\(directory)/icon_\(size).png"))
}
