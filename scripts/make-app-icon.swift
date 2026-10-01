// Draws Daybreak's app icon (the sun peeking over a cloud on the deep-blue sky, as on Android) at 1024 px, in a
// light and a dark version, into the asset catalog. Run on a Mac from the repo root:
//
//   swift scripts/make-app-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func icon(top: UInt32, bottom: UInt32, sun: UInt32, cloud: UInt32) -> CGImage {
    let s: CGFloat = 1024
    let ctx = CGContext(data: nil, width: Int(s), height: Int(s), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    // Flip so y runs down, as the app's drawing code does.
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)
    let gradient = CGGradient(colorsSpace: nil, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: s), options: [])
    // The mark, inset a little within the icon's safe area.
    let m: CGFloat = s * 0.72, o = (s - m) / 2
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: o + m * x, y: o + m * y) }
    // Sun: a disc and eight rays.
    let c = p(0.62, 0.36), r = m * 0.17
    ctx.setFillColor(rgb(sun))
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    ctx.setStrokeColor(rgb(sun))
    ctx.setLineWidth(r * 0.3)
    ctx.setLineCap(.round)
    for i in 0..<8 {
        let a = Double(i) * .pi / 4
        let (dx, dy) = (CGFloat(cos(a)), CGFloat(sin(a)))
        ctx.move(to: CGPoint(x: c.x + dx * r * 1.45, y: c.y + dy * r * 1.45))
        ctx.addLine(to: CGPoint(x: c.x + dx * r * 1.95, y: c.y + dy * r * 1.95))
    }
    ctx.strokePath()
    // Cloud: a rounded base and two bumps.
    let box = CGRect(origin: p(0.06, 0.44), size: CGSize(width: m * 0.74, height: m * 0.44))
    let h = box.height, w = box.width
    let baseTop = box.minY + h * 0.45
    ctx.setFillColor(rgb(cloud))
    ctx.addPath(CGPath(roundedRect: CGRect(x: box.minX, y: baseTop, width: w, height: box.maxY - baseTop),
                       cornerWidth: (box.maxY - baseTop) / 2, cornerHeight: (box.maxY - baseTop) / 2, transform: nil))
    let big = h * 0.5, small = h * 0.36
    ctx.addEllipse(in: CGRect(x: box.minX + w * 0.58 - big, y: box.minY, width: 2 * big, height: 2 * big))
    let sy = box.minY + h * 0.3 + small * 0.35
    ctx.addEllipse(in: CGRect(x: box.minX + w * 0.3 - small, y: sy - small, width: 2 * small, height: 2 * small))
    ctx.fillPath()
    return ctx.makeImage()!
}

func write(_ image: CGImage, _ path: String) {
    let url = URL(fileURLWithPath: path)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "Couldn't write \(path)")
    print("Wrote \(path)")
}

let dir = "Daybreak/Assets.xcassets/AppIcon.appiconset"
write(icon(top: 0x0D47A1, bottom: 0x1976D2, sun: 0xFFB74D, cloud: 0xFFFFFF), "\(dir)/AppIcon.png")
write(icon(top: 0x0B1B3A, bottom: 0x233A6A, sun: 0xFFB74D, cloud: 0xE4ECF5), "\(dir)/AppIcon-Dark.png")
