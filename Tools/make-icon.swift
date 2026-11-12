import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 1024pt macOS icon: a sesame seed with a keyhole on a warm rounded square.
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, alpha,
    ])!
}

func gradient(_ top: UInt32, _ bottom: UInt32, from y1: CGFloat, to y0: CGFloat) {
    let g = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y1), end: CGPoint(x: 0, y: y0), options: [])
}

// Background plate, on Apple's macOS icon grid (824pt square, 100pt margin).
let plate = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                   cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.3))
ctx.addPath(plate)
ctx.setFillColor(color(0xE8962A))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(plate)
ctx.clip()
gradient(0xF9CB62, 0xDF8420, from: 924, to: 100)
ctx.restoreGState()

// Seed: pointed at the top, round at the bottom.
let seed = CGMutablePath()
let cx: CGFloat = 512, cy: CGFloat = 440, r: CGFloat = 200
seed.move(to: CGPoint(x: cx, y: 800))
seed.addCurve(to: CGPoint(x: cx + r, y: cy), control1: CGPoint(x: cx + 60, y: 700), control2: CGPoint(x: cx + r, y: 580))
seed.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi, clockwise: true)
seed.addCurve(to: CGPoint(x: cx, y: 800), control1: CGPoint(x: cx - r, y: 580), control2: CGPoint(x: cx - 60, y: 700))
seed.closeSubpath()

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x7A3E00, 0.35))
ctx.addPath(seed)
ctx.setFillColor(color(0xFFF6E0))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(seed)
ctx.clip()
gradient(0xFFFBF0, 0xF6E3BC, from: 800, to: 240)
ctx.restoreGState()

// Keyhole.
var hole = CGMutablePath()
hole.addEllipse(in: CGRect(x: cx - 58, y: 432, width: 116, height: 116))
ctx.addPath(hole)
ctx.setFillColor(color(0x8A4A0C))
ctx.fillPath()
hole = CGMutablePath()
hole.move(to: CGPoint(x: cx - 26, y: 470))
hole.addLine(to: CGPoint(x: cx + 26, y: 470))
hole.addLine(to: CGPoint(x: cx + 48, y: 318))
hole.addLine(to: CGPoint(x: cx - 48, y: 318))
hole.closeSubpath()
ctx.addPath(hole)
ctx.setFillColor(color(0x8A4A0C))
ctx.fillPath()

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
