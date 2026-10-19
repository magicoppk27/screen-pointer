// Renders the 1024×1024 app icon to the path given as the first argument.
// Usage: swift scripts/make-icon.swift Resources/AppIcon.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Top-left origin, y down.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// macOS icon grid: 824pt body inset 100pt, ~185pt corner radius.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 18), blur: 36, color: rgb(0x000000, 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(rgb(0x2A1B7A))
ctx.fillPath()
ctx.restoreGState()

// Body gradient.
ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x6366F1), rgb(0x4C1D95), rgb(0x1E1B4B)] as CFArray,
                    locations: [0, 0.6, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 824, y: 924), options: [])

// Soft spotlight glow behind the halo.
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFD60A, 0.45), rgb(0xFFD60A, 0)] as CFArray,
                      locations: [0, 1])!
let center = CGPoint(x: 505, y: 440)
ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 380, options: [])

// Annotation squiggle (draw mode), bottom left.
let swoosh = CGMutablePath()
swoosh.move(to: CGPoint(x: 215, y: 790))
swoosh.addCurve(to: CGPoint(x: 455, y: 800), control1: CGPoint(x: 290, y: 700), control2: CGPoint(x: 360, y: 900))
ctx.addPath(swoosh)
ctx.setStrokeColor(rgb(0xFF453A))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
ctx.strokePath()

// Top sheen.
let sheen = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray,
                       locations: [0, 1])!
ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 520), options: [])
ctx.restoreGState()

// Highlight halo.
let haloRadius: CGFloat = 175
let haloRect = CGRect(x: center.x - haloRadius, y: center.y - haloRadius, width: haloRadius * 2, height: haloRadius * 2)
ctx.setFillColor(rgb(0xFFD60A, 0.25))
ctx.fillEllipse(in: haloRect)
ctx.setStrokeColor(rgb(0xFFD60A))
ctx.setLineWidth(24)
ctx.strokeEllipse(in: haloRect.insetBy(dx: 12, dy: 12))

// Click ripple.
ctx.setStrokeColor(rgb(0xFFD60A, 0.35))
ctx.setLineWidth(10)
ctx.strokeEllipse(in: haloRect.insetBy(dx: -55, dy: -55))

// Cursor arrow with its tip at the halo center.
let units: [CGPoint] = [(0, 0), (0, 100), (24, 77), (40, 114), (55, 108), (39, 71), (71, 71)]
    .map { CGPoint(x: $0.0, y: $0.1) }
let scale: CGFloat = 3.25
let arrow = CGMutablePath()
arrow.addLines(between: units.map { CGPoint(x: center.x + $0.x * scale, y: center.y + $0.y * scale) })
arrow.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 24, color: rgb(0x000000, 0.45))
ctx.addPath(arrow)
ctx.setFillColor(rgb(0xFFFFFF))
ctx.fillPath()
ctx.restoreGState()

ctx.addPath(arrow)
ctx.setStrokeColor(rgb(0x111827))
ctx.setLineWidth(16)
ctx.setLineJoin(.round)
ctx.strokePath()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("Wrote \(out)")
