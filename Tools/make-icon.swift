import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// 1024pt macOS icon: a knurled dial clicked into its top detent, ringed by 30 ticks
// (one per second of a code's life) on a deep slate rounded square.
let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 0xff) / 255, CGFloat((hex >> 8) & 0xff) / 255, CGFloat(hex & 0xff) / 255, alpha,
    ])!
}

func linear(_ top: UInt32, _ bottom: UInt32, from y1: CGFloat, to y0: CGFloat) {
    let g = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y1), end: CGPoint(x: 0, y: y0), options: [])
}

func circle(_ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
}

// Point at radius r, angle measured clockwise from 12 o'clock.
func polar(_ r: CGFloat, _ a: CGFloat) -> CGPoint {
    CGPoint(x: c.x + r * sin(a), y: c.y + r * cos(a))
}

let c = CGPoint(x: 512, y: 500)
let accent: UInt32 = 0xFFB23E

// Background plate, on Apple's macOS icon grid (824pt square, 100pt margin).
let plate = CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824),
                   cornerWidth: 186, cornerHeight: 186, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.3))
ctx.addPath(plate)
ctx.setFillColor(color(0x1C2638))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(plate)
ctx.clip()
linear(0x33435F, 0x121928, from: 924, to: 100)
ctx.restoreGState()

// Tick ring: 30 ticks, every fifth one longer. The top position is the detent pointer.
ctx.setLineCap(.round)
for i in 1..<30 {
    let a = CGFloat(i) / 30 * 2 * .pi
    let major = i % 5 == 0
    ctx.move(to: polar(major ? 318 : 334, a))
    ctx.addLine(to: polar(360, a))
    ctx.setLineWidth(major ? 18 : 12)
    ctx.setStrokeColor(color(0xDCE4F2, major ? 0.85 : 0.45))
    ctx.strokePath()
}
let pointer = CGMutablePath()
pointer.move(to: polar(312, 0))
pointer.addLine(to: CGPoint(x: c.x + 34, y: c.y + 372))
pointer.addLine(to: CGPoint(x: c.x - 34, y: c.y + 372))
pointer.closeSubpath()
ctx.addPath(pointer)
ctx.setLineJoin(.round)
ctx.setLineWidth(14)
ctx.setStrokeColor(color(accent))
ctx.setFillColor(color(accent))
ctx.drawPath(using: .fillStroke)

// Knob body with drop shadow.
let knobR: CGFloat = 268
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -16), blur: 36, color: color(0x000000, 0.55))
ctx.addPath(circle(knobR))
ctx.setFillColor(color(0x9AA3B2))
ctx.fillPath()
ctx.restoreGState()

// Knurled rim: brushed-metal sweep, then grooves.
ctx.saveGState()
ctx.addPath(circle(knobR))
ctx.clip()
// Conic sweep drawn as thin wedges: bright at 10:30 and 4:30, dark at 1:30 and 7:30.
let wedges = 360
for i in 0..<wedges {
    let a0 = CGFloat(i) / CGFloat(wedges) * 2 * .pi
    let a1 = CGFloat(i + 1) / CGFloat(wedges) * 2 * .pi + 0.01
    let t = (cos(2 * (a0 + .pi / 4)) + 1) / 2
    let v = 0x80 + Int(t * CGFloat(0xF4 - 0x80))
    ctx.move(to: c)
    ctx.addLine(to: polar(knobR + 4, a0))
    ctx.addLine(to: polar(knobR + 4, a1))
    ctx.closePath()
    ctx.setFillColor(color(UInt32(v - 8) << 16 | UInt32(v - 2) << 8 | UInt32(v + 6 > 255 ? 255 : v + 6)))
    ctx.fillPath()
}
for i in 0..<90 {
    let a = CGFloat(i) / 90 * 2 * .pi
    ctx.move(to: polar(knobR - 30, a))
    ctx.addLine(to: polar(knobR + 2, a))
}
ctx.setLineWidth(5)
ctx.setStrokeColor(color(0x2A3242, 0.45))
ctx.strokePath()
ctx.restoreGState()

// Knob face, slightly domed.
let faceR: CGFloat = 222
ctx.saveGState()
ctx.addPath(circle(faceR + 6))
ctx.setFillColor(color(0x5D6778))
ctx.fillPath()
ctx.addPath(circle(faceR))
ctx.clip()
linear(0xEEF1F6, 0xB4BCC9, from: c.y + faceR, to: c.y - faceR)
let glow = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.55), color(0xFFFFFF, 0)] as CFArray,
                      locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: c.x - 60, y: c.y + 90), startRadius: 0,
                       endCenter: CGPoint(x: c.x - 60, y: c.y + 90), endRadius: 260, options: [])
ctx.restoreGState()

// Indicator groove on the face, lined up with the pointer.
let groove = CGRect(x: c.x - 20, y: c.y + 70, width: 40, height: 128)
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: groove.insetBy(dx: -5, dy: -5), cornerWidth: 25, cornerHeight: 25, transform: nil))
ctx.setFillColor(color(0x4A5466, 0.5))
ctx.fillPath()
ctx.addPath(CGPath(roundedRect: groove, cornerWidth: 20, cornerHeight: 20, transform: nil))
ctx.clip()
linear(0xFFC861, 0xE88A12, from: groove.maxY, to: groove.minY)
ctx.restoreGState()

let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
