// Copyright 2026 Stefan Radermacher
//
// NOT covered by the Apache License 2.0 that applies to the rest of Motiv.
// This file draws the app icon and the document icon, which are marks of
// Stefan Radermacher and are reserved. See TRADEMARKS.md.

import AppKit

// Draws the Motiv app icon into the asset catalog and the document icon into Resources.
// Usage (from the project folder): swift scripts/make_icon.swift
// All drawing is done on a 1024 × 1024 canvas and scaled for the smaller sizes.

// MARK: helpers
func c(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func rr(_ r: NSRect, _ radius: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius) }
var ctx: CGContext { NSGraphicsContext.current!.cgContext }
/// Output size relative to 1024; shadows are not affected by the scaled drawing, so they scale by hand.
var outputScale: CGFloat = 1
func shadow(_ blur: CGFloat, _ dy: CGFloat, _ alpha: CGFloat) {
    ctx.setShadow(offset: CGSize(width: 0, height: dy * outputScale), blur: blur * outputScale,
                  color: NSColor.black.withAlphaComponent(alpha).cgColor)
}
func noShadow() { ctx.setShadow(offset: .zero, blur: 0, color: nil) }

/// Colours of one photo: sky from top to horizon, sun, far and near hills.
struct Scene {
    var skyTop: NSColor, skyBottom: NSColor, sun: NSColor, far: NSColor, near: NSColor
}

let dusk = Scene(skyTop: c(0xF2B872), skyBottom: c(0xF7DDB0), sun: c(0xFFF6E0), far: c(0xC7775A), near: c(0x7E3F35))
let lake = Scene(skyTop: c(0x8CC4D6), skyBottom: c(0xD8EDF2), sun: c(0xFFFFFF, 0.9), far: c(0x6A9FA8), near: c(0x2F5F66))
/// The petrol of the app icon, for the document icon.
let petrol = Scene(skyTop: c(0x7DB6BD), skyBottom: c(0xD6ECEE), sun: c(0xFFFFFF, 0.92), far: c(0x3E8A92), near: c(0x1D5961))
let meadow = Scene(skyTop: c(0xA9CFE0), skyBottom: c(0xE6F1E4), sun: c(0xFFF8DC), far: c(0x8DB07A), near: c(0x4E7A44))

/// Squircle background on the macOS icon grid, deep petrol.
func background() {
    let path = rr(NSRect(x: 100, y: 100, width: 824, height: 824), 185)
    NSGradient(starting: c(0x2F7E86), ending: c(0x163F47))!.draw(in: path, angle: -90)
    ctx.saveGState(); path.addClip()
    NSGradient(starting: NSColor.white.withAlphaComponent(0.16), ending: NSColor.white.withAlphaComponent(0))!
        .draw(in: NSRect(x: 100, y: 600, width: 824, height: 324), angle: -90)
    ctx.restoreGState()
}

/// Landscape filling `r`: sky, sun, two ranges of hills.
func landscape(_ r: NSRect, _ s: Scene) {
    ctx.saveGState(); NSBezierPath(rect: r).addClip()
    NSGradient(starting: s.skyTop, ending: s.skyBottom)!.draw(in: r, angle: -90)
    let sun = r.width * 0.16
    s.sun.setFill()
    NSBezierPath(ovalIn: NSRect(x: r.minX + r.width * 0.64, y: r.minY + r.height * 0.56, width: sun, height: sun)).fill()
    let far = NSBezierPath(); far.move(to: NSPoint(x: r.minX - 10, y: r.minY))
    far.line(to: NSPoint(x: r.minX - 10, y: r.minY + r.height * 0.34))
    far.curve(to: NSPoint(x: r.minX + r.width * 0.42, y: r.minY + r.height * 0.52),
              controlPoint1: NSPoint(x: r.minX + r.width * 0.12, y: r.minY + r.height * 0.46),
              controlPoint2: NSPoint(x: r.minX + r.width * 0.28, y: r.minY + r.height * 0.56))
    far.curve(to: NSPoint(x: r.maxX + 10, y: r.minY + r.height * 0.30),
              controlPoint1: NSPoint(x: r.minX + r.width * 0.62, y: r.minY + r.height * 0.46),
              controlPoint2: NSPoint(x: r.minX + r.width * 0.82, y: r.minY + r.height * 0.26))
    far.line(to: NSPoint(x: r.maxX + 10, y: r.minY)); far.close()
    s.far.setFill(); far.fill()
    let near = NSBezierPath(); near.move(to: NSPoint(x: r.minX - 10, y: r.minY))
    near.line(to: NSPoint(x: r.minX - 10, y: r.minY + r.height * 0.14))
    near.curve(to: NSPoint(x: r.maxX + 10, y: r.minY + r.height * 0.28),
               controlPoint1: NSPoint(x: r.minX + r.width * 0.35, y: r.minY + r.height * 0.30),
               controlPoint2: NSPoint(x: r.minX + r.width * 0.6, y: r.minY + r.height * 0.08))
    near.line(to: NSPoint(x: r.maxX + 10, y: r.minY)); near.close()
    s.near.setFill(); near.fill()
    ctx.restoreGState()
}

/// A photo print with a white border, rotated by `tilt` degrees around its centre.
func print(center: NSPoint, size: NSSize, tilt: CGFloat, _ s: Scene) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y); ctx.rotate(by: tilt * .pi / 180)
    let paper = NSRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
    shadow(30, -14, 0.38)
    NSColor(white: 0.985, alpha: 1).setFill(); rr(paper, 10).fill()
    noShadow()
    let border = size.width * 0.06
    landscape(paper.insetBy(dx: border, dy: border), s)
    ctx.restoreGState()
}

/// Three prints fanned out, the front one straight: a collection, one picture in view.
func drawIcon() {
    background()
    let size = NSSize(width: 520, height: 400)
    print(center: NSPoint(x: 470, y: 560), size: size, tilt: 14, meadow)
    print(center: NSPoint(x: 548, y: 520), size: size, tilt: -9, lake)
    print(center: NSPoint(x: 512, y: 452), size: NSSize(width: 580, height: 440), tilt: 0, dusk)
}

/// The document icon: a page with a folded petrol corner, filled with a photo in the petrol of
/// the app icon, as the page of Leser's document icon is filled with text.
func drawDocumentIcon() {
    let r = NSRect(x: 142, y: 40, width: 740, height: 950)
    let fold = r.width * 0.27
    let page = NSBezierPath()
    page.move(to: NSPoint(x: r.minX, y: r.minY)); page.line(to: NSPoint(x: r.maxX, y: r.minY))
    page.line(to: NSPoint(x: r.maxX, y: r.maxY - fold)); page.line(to: NSPoint(x: r.maxX - fold, y: r.maxY))
    page.line(to: NSPoint(x: r.minX, y: r.maxY)); page.close()
    shadow(34, -14, 0.34); NSColor.white.setFill(); page.fill(); noShadow()

    // The photo fills the page below the folded corner, with a white margin like a print.
    let margin = r.width * 0.09
    let photo = NSRect(x: r.minX + margin, y: r.minY + margin,
                       width: r.width - 2 * margin, height: r.height - fold - margin * 1.6)
    ctx.saveGState(); page.addClip()
    ctx.saveGState(); rr(photo, 14).addClip(); landscape(photo, petrol); ctx.restoreGState()
    ctx.restoreGState()

    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: r.maxX - fold, y: r.maxY)); corner.line(to: NSPoint(x: r.maxX - fold, y: r.maxY - fold))
    corner.line(to: NSPoint(x: r.maxX, y: r.maxY - fold)); corner.close()
    shadow(12, -5, 0.22); c(0x2F7E86).setFill(); corner.fill(); noShadow()
}

let out = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ px: Int, _ draw: () -> Void = drawIcon) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    outputScale = CGFloat(px) / 1024
    ctx.scaleBy(x: outputScale, y: outputScale)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [String] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try! png(size * scale).write(to: out.appendingPathComponent(name))
        images.append("""
            { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(scale)x", "size" : "\(size)x\(size)" }
        """)
    }
}

// Document icon as .icns next to the app icon
let docSet = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DocumentIcon.iconset")
try? FileManager.default.removeItem(at: docSet)
try! FileManager.default.createDirectory(at: docSet, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! png(size, drawDocumentIcon).write(to: docSet.appendingPathComponent("icon_\(size)x\(size).png"))
    try! png(size * 2, drawDocumentIcon).write(to: docSet.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", docSet.path, "-o", "Resources/ImageDocument.icns"]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: docSet)

let contents = """
{
  "images" : [
\(images.joined(separator: ",\n"))
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}

"""
try! contents.write(to: out.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
