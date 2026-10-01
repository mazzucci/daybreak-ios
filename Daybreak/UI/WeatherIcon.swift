import SwiftUI

/// Colours for one icon: amber sun, blue rain and grey clouds on cards, or all white on the sky.
struct IconPalette {
    var cloud: Color
    var sun: Color
    var rain: Color

    static let card = IconPalette(cloud: Palette.cloud, sun: Palette.sun, rain: Palette.rain)
    static func mono(_ color: Color) -> IconPalette { IconPalette(cloud: color, sun: color, rain: color) }
}

/// The weather glyph for a WMO [code], drawn the same way as on Android: everything laid out on a unit square and
/// scaled to [size]. Decorative unless given a label.
struct WeatherIcon: View {
    let code: Int
    var night = false
    var palette: IconPalette = .card
    var size: CGFloat = 24

    var body: some View {
        Canvas { context, canvasSize in
            drawSky(Sky(code: code), night: night, palette: palette, s: min(canvasSize.width, canvasSize.height), in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The app's mark (the sun peeking over a cloud), as the launcher icon draws it.
struct BrandMark: View {
    var size: CGFloat = 96
    var palette: IconPalette = .card

    var body: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            sun(CGPoint(x: s * 0.62, y: s * 0.36), s * 0.17, palette.sun, in: &context)
            cloud(CGRect(x: s * 0.06, y: s * 0.44, width: s * 0.74, height: s * 0.44), palette.cloud, in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private func drawSky(_ sky: Sky, night: Bool, palette p: IconPalette, s: CGFloat, in c: inout GraphicsContext) {
    func rect(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) -> CGRect {
        CGRect(x: s * l, y: s * t, width: s * (r - l), height: s * (b - t))
    }
    switch sky {
    case .clear:
        if night { moon(CGPoint(x: s * 0.5, y: s * 0.5), s * 0.36, p.sun, in: &c) }
        else { sun(CGPoint(x: s * 0.5, y: s * 0.5), s * 0.24, p.sun, in: &c) }
    case .partlyCloudy:
        if night { moon(CGPoint(x: s * 0.64, y: s * 0.34), s * 0.24, p.sun, in: &c) }
        else { sun(CGPoint(x: s * 0.64, y: s * 0.34), s * 0.16, p.sun, in: &c) }
        cloud(rect(0.06, 0.42, 0.78, 0.86), p.cloud, in: &c)
    case .cloudy:
        cloud(rect(0.08, 0.24, 0.92, 0.78), p.cloud, in: &c)
    case .fog:
        cloud(rect(0.12, 0.14, 0.88, 0.6), p.cloud, in: &c)
        for (i, y) in [0.7, 0.86].enumerated() {
            let inset: CGFloat = i == 0 ? 0.14 : 0.24
            line(CGPoint(x: s * inset, y: s * y), CGPoint(x: s * (1 - inset), y: s * y), p.cloud, s * 0.075, in: &c)
        }
    case .drizzle:
        cloud(rect(0.08, 0.12, 0.92, 0.62), p.cloud, in: &c)
        drops(s, p.rain, length: 0.08, in: &c)
    case .rain:
        cloud(rect(0.08, 0.12, 0.92, 0.62), p.cloud, in: &c)
        drops(s, p.rain, length: 0.18, in: &c)
    case .snow:
        cloud(rect(0.08, 0.12, 0.92, 0.62), p.cloud, in: &c)
        for (i, x) in [0.28, 0.5, 0.72].enumerated() {
            flake(CGPoint(x: s * x, y: s * (i == 1 ? 0.86 : 0.78)), s * 0.07, p.rain, in: &c)
        }
    case .storm:
        cloud(rect(0.08, 0.1, 0.92, 0.6), p.cloud, in: &c)
        bolt(s, p.sun, in: &c)
    case .unknown:
        let r = s * 0.3
        c.stroke(Path(ellipseIn: CGRect(x: s * 0.5 - r, y: s * 0.5 - r, width: r * 2, height: r * 2)),
                 with: .color(p.cloud), lineWidth: s * 0.08)
    }
}

private func line(_ a: CGPoint, _ b: CGPoint, _ color: Color, _ width: CGFloat, in c: inout GraphicsContext) {
    var path = Path()
    path.move(to: a)
    path.addLine(to: b)
    c.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
}

private func sun(_ center: CGPoint, _ radius: CGFloat, _ color: Color, in c: inout GraphicsContext) {
    c.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
           with: .color(color))
    let inner = radius * 1.45, outer = radius * 1.95
    for i in 0..<8 {
        let a = Double(i) * .pi / 4
        let dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
        line(CGPoint(x: center.x + dx * inner, y: center.y + dy * inner),
             CGPoint(x: center.x + dx * outer, y: center.y + dy * outer), color, radius * 0.3, in: &c)
    }
}

private func moon(_ center: CGPoint, _ radius: CGFloat, _ color: Color, in c: inout GraphicsContext) {
    let disc = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    let bite = CGPoint(x: center.x + radius * 0.55, y: center.y - radius * 0.35)
    let biteRadius = radius * 0.8
    let cut = Path(ellipseIn: CGRect(x: bite.x - biteRadius, y: bite.y - biteRadius, width: biteRadius * 2, height: biteRadius * 2))
    c.fill(disc.subtracting(cut), with: .color(color))
}

/// A cloud that fills [box]: a flat-bottomed base with two bumps on top.
private func cloud(_ box: CGRect, _ color: Color, in c: inout GraphicsContext) {
    let h = box.height, w = box.width
    let baseTop = box.minY + h * 0.45
    let base = CGRect(x: box.minX, y: baseTop, width: w, height: box.maxY - baseTop)
    let bigR = h * 0.5
    let big = CGPoint(x: box.minX + w * 0.58, y: box.minY + bigR)
    let smallR = h * 0.36
    let small = CGPoint(x: box.minX + w * 0.3, y: box.minY + h * 0.3 + smallR * 0.35)
    // One shape, so the parts' overlaps never show (whatever the winding of each part).
    let shape = Path(roundedRect: base, cornerRadius: base.height / 2)
        .union(Path(ellipseIn: CGRect(x: big.x - bigR, y: big.y - bigR, width: bigR * 2, height: bigR * 2)))
        .union(Path(ellipseIn: CGRect(x: small.x - smallR, y: small.y - smallR, width: smallR * 2, height: smallR * 2)))
    c.fill(shape, with: .color(color))
}

private func drops(_ s: CGFloat, _ color: Color, length: CGFloat, in c: inout GraphicsContext) {
    for (i, x) in [0.3, 0.5, 0.7].enumerated() {
        let top = s * (i == 1 ? 0.74 : 0.68)
        line(CGPoint(x: s * x, y: top), CGPoint(x: s * (x - 0.04), y: top + s * length), color, s * 0.075, in: &c)
    }
}

private func flake(_ center: CGPoint, _ radius: CGFloat, _ color: Color, in c: inout GraphicsContext) {
    for i in 0..<3 {
        let a = Double(i) * .pi / 3
        let d = CGPoint(x: CGFloat(cos(a)) * radius, y: CGFloat(sin(a)) * radius)
        line(CGPoint(x: center.x - d.x, y: center.y - d.y), CGPoint(x: center.x + d.x, y: center.y + d.y), color,
             radius * 0.5, in: &c)
    }
}

private func bolt(_ s: CGFloat, _ color: Color, in c: inout GraphicsContext) {
    var path = Path()
    path.move(to: CGPoint(x: s * 0.54, y: s * 0.5))
    path.addLine(to: CGPoint(x: s * 0.38, y: s * 0.76))
    path.addLine(to: CGPoint(x: s * 0.5, y: s * 0.76))
    path.addLine(to: CGPoint(x: s * 0.44, y: s * 0.96))
    path.addLine(to: CGPoint(x: s * 0.64, y: s * 0.68))
    path.addLine(to: CGPoint(x: s * 0.52, y: s * 0.68))
    path.addLine(to: CGPoint(x: s * 0.6, y: s * 0.5))
    path.closeSubpath()
    c.fill(path, with: .color(color))
}
