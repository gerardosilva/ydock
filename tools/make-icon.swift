// Draws the yDock app icon (dark "magnify" dock) at every size macOS needs, with a transparent background.
// Usage: swift tools/make-icon.swift <output-dir>      (then: iconutil -c icns <output-dir>/AppIcon.iconset)
import AppKit

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, a])!
}
func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: cs, colors: stops.map { $0.0 } as CFArray, locations: stops.map { $0.1 })!
}

/// Draws the icon in a 1024×1024 space with the origin at the top-left (same as the SVG design).
func drawIcon(_ ctx: CGContext) {
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Soft drop shadow under the whole icon (offset is in device space, so "down" is negative here).
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 44, color: rgb(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x14161B)); ctx.fillPath()
    ctx.restoreGState()

    // Everything else is clipped to the rounded body.
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()

    ctx.drawLinearGradient(gradient([(rgb(0x2E3446), 0), (rgb(0x0D1017), 1)]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    ctx.drawLinearGradient(gradient([(rgb(0xFFFFFF, 0.22), 0), (rgb(0xFFFFFF, 0), 1)]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 512), options: [])

    // Dock plate.
    let plate = CGPath(roundedRect: CGRect(x: 140, y: 400, width: 744, height: 224), cornerWidth: 112, cornerHeight: 112, transform: nil)
    ctx.addPath(plate); ctx.setFillColor(rgb(0xFFFFFF, 0.07)); ctx.fillPath()
    ctx.addPath(plate); ctx.setStrokeColor(rgb(0xFFFFFF, 0.12)); ctx.setLineWidth(3); ctx.strokePath()

    // Colored dots, magnified toward the center, each with a glow and a specular highlight.
    let dots: [(x: CGFloat, r: CGFloat, color: UInt32)] = [
        (207, 45, 0xFF5E57), (332, 70, 0xFFB020), (512, 100, 0x34C759), (692, 70, 0x0A84FF), (817, 45, 0xAF52DE),
    ]
    for d in dots {
        let glowR = d.r + 26 + 34
        let glow = gradient([(rgb(d.color, 0.42), 0), (rgb(d.color, 0.30), (d.r + 8) / glowR), (rgb(d.color, 0), 1)])
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: d.x, y: 512), startRadius: 0,
                               endCenter: CGPoint(x: d.x, y: 512), endRadius: glowR, options: [])
    }
    for d in dots {
        ctx.setFillColor(rgb(d.color))
        ctx.fillEllipse(in: CGRect(x: d.x - d.r, y: 512 - d.r, width: d.r * 2, height: d.r * 2))
        let h = d.r * 0.22
        ctx.setFillColor(rgb(0xFFFFFF, 0.45))
        ctx.fillEllipse(in: CGRect(x: d.x - d.r * 0.32 - h, y: 512 - d.r * 0.34 - h, width: h * 2, height: h * 2))
    }

    // Floor shadow under the dock.
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 706); ctx.scaleBy(x: 250, y: 18)
    ctx.drawRadialGradient(gradient([(rgb(0x000000, 0.40), 0), (rgb(0x000000, 0.25), 0.6), (rgb(0x000000, 0), 1)]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 1, options: [])
    ctx.restoreGState()

    ctx.restoreGState()
}

func png(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let g = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    let ctx = g.cgContext
    ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(ctx)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon-out")
let set = out.appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
let files: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in files { try png(size: px).write(to: set.appendingPathComponent(name + ".png")) }
try png(size: 1024).write(to: out.appendingPathComponent("AppIcon-1024.png"))
print("wrote \(files.count) sizes to \(set.path)")
