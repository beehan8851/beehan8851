#!/usr/bin/env swift
// Renders the Dawnwick app icon PNGs from Embi's shape (D3, docs/18).
//
// Companion to tools/make_app_icon.py — same geometry, drawn with CoreGraphics so
// the asset catalogue gets exact 1024 px images without an SVG rasteriser:
//
//   MorningCompanion/Assets.xcassets/AppIcon.appiconset/
//     icon-light.png   opaque, night plate            (the default icon)
//     icon-dark.png    transparent plate              (iOS paints the dark one)
//     icon-tinted.png  grayscale, transparent plate   (iOS tints by luminance)
//   design/ember-sky/icon/preview.png   the three side by side at home-screen size
//
// Run from the repo root:  swift tools/render_app_icon.swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Geometry (mirrors EmbiShape.draw and make_app_icon.py)

let canvas: CGFloat = 1024
let scale: CGFloat = 6
let center = CGPoint(x: 512, y: 554)
let coreScale: CGFloat = 0.62
let coreDY: CGFloat = 8
let eyeDX: CGFloat = 10, eyeDY: CGFloat = 8, eyeSize: CGFloat = 5
let eyeOpenness: CGFloat = 1.0

/// EmbiShape.drop, verbatim.
func drop() -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: 0, y: -60))
    p.addCurve(to: CGPoint(x: 38, y: 12), control1: CGPoint(x: 14, y: -36), control2: CGPoint(x: 38, y: -14))
    p.addCurve(to: CGPoint(x: 0, y: 46), control1: CGPoint(x: 38, y: 32), control2: CGPoint(x: 22, y: 46))
    p.addCurve(to: CGPoint(x: -38, y: 12), control1: CGPoint(x: -22, y: 46), control2: CGPoint(x: -38, y: 32))
    p.addCurve(to: CGPoint(x: 0, y: -60), control1: CGPoint(x: -38, y: -14), control2: CGPoint(x: -14, y: -36))
    p.closeSubpath()
    return p
}

// MARK: - Colours

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

struct Palette {
    var plate: CGColor?
    var rim: CGColor
    var core: CGColor
    var ink: CGColor
    var highlight: CGColor?
}

let light = Palette(plate: rgb(0x14162B), rim: rgb(0xF26B1D), core: rgb(0xF5B62B), ink: rgb(0x1F1A17), highlight: rgb(0xFFFFFF))
let dark = Palette(plate: nil, rim: rgb(0xF26B1D), core: rgb(0xF5B62B), ink: rgb(0x1F1A17), highlight: rgb(0xFFFFFF))
let tinted = Palette(plate: nil, rim: rgb(0xD2D2D2), core: rgb(0xFAFAFA), ink: rgb(0x262626), highlight: nil)

// MARK: - Drawing

/// Draws Embi into `g`, whose coordinate space is the 1024 canvas with y down.
func drawEmbi(_ g: CGContext, _ p: Palette) {
    if let plate = p.plate {
        g.setFillColor(plate)
        g.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    }
    let shape = drop()

    var t = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: scale, y: scale)
    g.addPath(shape.copy(using: &t)!)
    g.setFillColor(p.rim)
    g.fillPath()

    var c = CGAffineTransform(translationX: center.x, y: center.y + coreDY * scale).scaledBy(x: scale * coreScale, y: scale * coreScale)
    g.addPath(shape.copy(using: &c)!)
    g.setFillColor(p.core)
    g.fillPath()

    let y = center.y + eyeDY * scale
    let size = eyeSize * scale
    let ry = size * 1.2 * eyeOpenness
    for x in [center.x - eyeDX * scale, center.x + eyeDX * scale] {
        g.setFillColor(p.ink)
        g.fillEllipse(in: CGRect(x: x - size, y: y - ry, width: size * 2, height: ry * 2))
        if let highlight = p.highlight, eyeOpenness > 0.5 {
            g.setFillColor(highlight)
            g.fillEllipse(in: CGRect(x: x + size * 0.1, y: y - ry * 0.4, width: size * 0.64, height: size * 0.64))
        }
    }
}

/// `opaque` drops the alpha channel: App Store validation rejects a default icon
/// that carries one, even when every pixel is solid.
func makeContext(_ w: Int, _ h: Int, opaque: Bool = false) -> CGContext {
    let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
    let g = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: alpha.rawValue)!
    // Flip to y-down so the geometry reads like the SwiftUI Canvas.
    g.translateBy(x: 0, y: CGFloat(h))
    g.scaleBy(x: 1, y: -1)
    g.setAllowsAntialiasing(true)
    g.setShouldAntialias(true)
    return g
}

func render(_ p: Palette) -> CGImage {
    let g = makeContext(Int(canvas), Int(canvas), opaque: p.plate != nil)
    drawEmbi(g, p)
    return g.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("could not write \(url.path)") }
    print("  wrote \(url.path)")
}

// MARK: - Preview: three icons on a light, a dark and a tinted home screen

func preview(_ images: [(image: CGImage, ground: CGColor, plate: Bool, tint: CGColor?)]) -> CGImage {
    let tile: CGFloat = 180, pad: CGFloat = 40
    let w = Int(pad + CGFloat(images.count) * (tile + pad)), h = Int(tile + 2 * pad)
    let g = makeContext(w, h)
    for (i, entry) in images.enumerated() {
        let x = pad + CGFloat(i) * (tile + pad)
        g.setFillColor(entry.ground)
        g.fill(CGRect(x: x - pad / 2, y: pad / 2, width: tile + pad, height: tile + pad))
        let rect = CGRect(x: x, y: pad, width: tile, height: tile)
        g.saveGState()
        // iOS icon corner: ~22.4 % of the side.
        g.addPath(CGPath(roundedRect: rect, cornerWidth: tile * 0.224, cornerHeight: tile * 0.224, transform: nil))
        g.clip()
        if entry.plate {
            // What iOS paints behind a transparent dark or tinted icon.
            g.setFillColor(rgb(0x1C1C1E)); g.fill(rect)
        }
        g.saveGState()
        g.translateBy(x: rect.minX, y: rect.maxY); g.scaleBy(x: 1, y: -1)
        let local = CGRect(origin: .zero, size: rect.size)
        if let tint = entry.tint {
            // Tinted appearance, approximately: the grayscale image masks the tint colour.
            g.clip(to: local, mask: entry.image)
            g.setFillColor(tint); g.fill(local)
        } else {
            g.draw(entry.image, in: local)
        }
        g.restoreGState()
        g.restoreGState()
    }
    return g.makeImage()!
}

// MARK: - Main

let repo = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let appiconset = repo.appendingPathComponent("MorningCompanion/Assets.xcassets/AppIcon.appiconset")
let designIcon = repo.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("design/ember-sky/icon")

let lightImage = render(light), darkImage = render(dark), tintedImage = render(tinted)
writePNG(lightImage, to: appiconset.appendingPathComponent("icon-light.png"))
writePNG(darkImage, to: appiconset.appendingPathComponent("icon-dark.png"))
writePNG(tintedImage, to: appiconset.appendingPathComponent("icon-tinted.png"))
writePNG(preview([
    (lightImage, rgb(0xF6F0E6), false, nil),
    (darkImage, rgb(0x0F1024), true, nil),
    (tintedImage, rgb(0x0F1024), true, rgb(0xE9B76A)),
]), to: designIcon.appendingPathComponent("preview.png"))
