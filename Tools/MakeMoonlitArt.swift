// SPDX-License-Identifier: GPL-3.0-or-later

// Draws this fork's own artwork (the Moonlit planet, ring and moon from
// docs/assets/readme/moonlit.svg) into the paths the build reads:
//   Resources/Brand/logo.png            single-colour mark, tinted and trimmed at build time
//   Resources/Brand/AppIcon-Default.png full-colour 1024 app icon
// Run: swift Tools/MakeMoonlitArt.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let S: CGFloat = 1024

func render(_ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    draw(ctx.cgContext)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func save(_ rep: NSBitmapImageRep, _ path: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(path))
}

func color(_ hex: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: a)
}

/// Planet with a ring that passes behind its upper half and in front of its lower half, then the moon.
/// `paintGap` repaints the backdrop inside the gap between planet and front ring; nil clears to transparent.
func drawScene(_ c: CGContext, center: CGPoint, r: CGFloat, planet: CGColor, ring: CGColor, moon: CGColor,
               crater: CGColor?, gap: CGFloat, paintGap: ((CGContext) -> Void)? = nil) {
    let tilt = -18 * CGFloat.pi / 180
    let rx = r * 2.1, ry = r * 0.56, w = r * 0.11
    func ringPath(_ from: CGFloat, _ to: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let steps = 160
        for i in 0...steps {
            let t = from + (to - from) * CGFloat(i) / CGFloat(steps)
            let x = rx * cos(t), y = ry * sin(t)
            let pt = CGPoint(x: center.x + x * cos(tilt) - y * sin(tilt), y: center.y + x * sin(tilt) + y * cos(tilt))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        return p
    }
    let disk = CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r)
    c.setLineCap(.butt)
    c.setStrokeColor(ring); c.setLineWidth(w)
    c.addPath(ringPath(0, 2 * .pi)); c.strokePath()                    // whole ring, the planet hides the back half
    c.setFillColor(planet); c.fillEllipse(in: disk)
    c.saveGState()                                                      // gap inside the planet, around the front half
    c.addEllipse(in: disk); c.clip()
    c.addPath(ringPath(.pi, 2 * .pi)); c.setLineWidth(w + gap * 2)
    c.replacePathWithStrokedPath(); c.clip()
    if let paintGap { paintGap(c) } else { c.setBlendMode(.clear); c.fill(CGRect(x: 0, y: 0, width: S, height: S)) }
    c.restoreGState()
    c.setStrokeColor(ring); c.setLineWidth(w)
    c.addPath(ringPath(.pi, 2 * .pi)); c.strokePath()
    let m = CGPoint(x: center.x + r * 1.55, y: center.y + r * 1.15), mr = r * 0.42
    c.setFillColor(moon)
    c.fillEllipse(in: CGRect(x: m.x - mr, y: m.y - mr, width: 2 * mr, height: 2 * mr))
    if let crater {
        c.setFillColor(crater)
        for (dx, dy, k) in [(-0.3, 0.25, 0.2), (0.3, -0.25, 0.15), (0.18, 0.4, 0.1)] as [(CGFloat, CGFloat, CGFloat)] {
            c.fillEllipse(in: CGRect(x: m.x + dx * mr - k * mr, y: m.y + dy * mr - k * mr, width: 2 * k * mr, height: 2 * k * mr))
        }
    }
}

// Single-colour mark: alpha is what matters, the build tints it.
save(render { c in
    drawScene(c, center: CGPoint(x: 470, y: 460), r: 215, planet: color(0x0A1020), ring: color(0x0A1020),
              moon: color(0x0A1020), crater: nil, gap: 20)
}, "Resources/Brand/logo.png")

// App icon: macOS grid (824pt squircle on a 1024 canvas) with a night-sky gradient.
save(render { c in
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    c.saveGState(); c.addPath(path); c.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [color(0x1B2A4E), color(0x0B1226)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    c.setFillColor(color(0xFFFFFF, 0.8))
    for (x, y, d) in [(230, 760, 7), (330, 840, 5), (760, 700, 6), (180, 400, 5), (840, 330, 6)] as [(CGFloat, CGFloat, CGFloat)] {
        c.fillEllipse(in: CGRect(x: x - d / 2, y: y - d / 2, width: d, height: d))
    }
    drawScene(c, center: CGPoint(x: 480, y: 480), r: 170, planet: color(0x4C8DFF), ring: color(0x8A93A6),
              moon: color(0xF5C542), crater: color(0xD9A521), gap: 14,
              paintGap: { c in c.drawLinearGradient(g, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: []) })
    c.restoreGState()
}, "Resources/Brand/AppIcon-Default.png")
print("wrote Resources/Brand/logo.png and AppIcon-Default.png")
