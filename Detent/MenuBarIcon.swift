import AppKit

extension NSImage {
    /// The menu bar version of the app icon: a dial with its indicator clicked into the top detent,
    /// drawn as a template so macOS tints it for light and dark menu bars.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setFill()

            // Detent pointer above the dial.
            let pointer = NSBezierPath()
            pointer.move(to: NSPoint(x: 9, y: 15))
            pointer.line(to: NSPoint(x: 12.2, y: 18))
            pointer.line(to: NSPoint(x: 5.8, y: 18))
            pointer.close()
            pointer.fill()

            // Knob with a knurled rim (16 notches clipped out of the edge) and the indicator cut out of its face.
            let c = NSPoint(x: 9, y: 7)
            let r: CGFloat = 7
            NSGraphicsContext.saveGraphicsState()
            let notches = NSBezierPath(rect: NSRect(x: 0, y: 0, width: 18, height: 18))
            for i in 0..<16 {
                let a = (CGFloat(i) + 0.5) / 16 * 2 * .pi
                let notch = NSBezierPath(rect: NSRect(x: -0.45, y: r - 1.1, width: 0.9, height: 2.1))
                var t = AffineTransform(translationByX: c.x, byY: c.y)
                t.rotate(byRadians: -a)
                notch.transform(using: t)
                notches.append(notch)
            }
            notches.windingRule = .evenOdd
            notches.addClip()
            let knob = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            knob.append(NSBezierPath(roundedRect: NSRect(x: c.x - 0.95, y: c.y + 0.4, width: 1.9, height: 4.2),
                                     xRadius: 0.95, yRadius: 0.95))
            knob.windingRule = .evenOdd
            knob.fill()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Detent"
        return image
    }()
}
