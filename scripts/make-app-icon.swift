#!/usr/bin/env swift
//
// Regenerates AppIcon.appiconset from code.
//
// This fork needs an icon that is obviously NOT upstream's at a glance: both
// builds carry the same name and the same bundle name in Finder, and telling
// them apart mattered while chasing which binary macOS was actually granting
// permission to. Drawing it here rather than committing a binary blob from a
// design tool means the shape and the palette are reviewable in a diff.
//
// Run: swift scripts/make-app-icon.swift
//
import AppKit

let outputDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("SquirrelTrap/Assets.xcassets/AppIcon.appiconset")

/// macOS icons are drawn inside a rounded "squircle" that does not fill the
/// canvas: roughly 80% of the tile, centred, with the rest left as breathing
/// room. Filling the full square is the single most common way a third-party
/// icon reads as wrong next to Apple's own.
let inset: CGFloat = 0.10
let cornerFraction: CGFloat = 0.225

/// The same Lucide squirrel the menu bar uses, so the app has one mark rather
/// than two. It lives here as a pre-rendered black-on-white raster because the
/// artwork is four stroked paths full of elliptical arcs: hand-writing an SVG
/// arc parser to place it would be far more surface area than an icon warrants.
/// Regenerate with:
///
///   qlmanage -t -s 1024 -o <dir> scripts/icon-source/squirrel-1024.svg
///
/// Its luminance is used as a mask below, so the white background disappears
/// and only the strokes are painted.
let glyphSource = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("icon-source/squirrel-1024.png")

/// Builds the grayscale mask for `CGContext.clip(to:mask:)`.
///
/// That API paints where the mask is HIGH and skips where it is low, so the
/// source (black strokes on a white ground) has to be inverted: the strokes
/// need to be the bright part. Verified the hard way by rendering it the other
/// way round first and getting a white square with an amber squirrel cut out of
/// it, which is precisely the inverse of the intent.
func invertedMask(from image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height)

    let drawn: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return false }
        // White ground first, so any transparent margin in the source ends up
        // as "do not paint" once inverted, rather than as a solid block.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    guard drawn else { return nil }

    // Deliberately NOT inverted. For a true CGImage image mask, 0 means PAINT
    // and 255 means leave alone, so the source's black strokes are already the
    // painted region and its white ground is already the hole.
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(
        maskWidth: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: width,
        provider: provider,
        decode: nil,
        shouldInterpolate: true
    )
}

/// A superellipse, not a rounded rectangle.
///
/// macOS app icons use a continuous curve where the straight edge eases into
/// the corner, rather than a circular arc grafted onto a straight line. The
/// difference is small in isolation and obvious in a Dock full of real icons:
/// a plain `CGPath(roundedRect:)` reads as slightly pinched at the corners next
/// to Apple's own. Sampling |x|^n + |y|^n = 1 at n = 5 gets very close.
func superellipse(in rect: CGRect, exponent: CGFloat = 5, samples: Int = 720) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2
    let b = rect.height / 2
    let centre = CGPoint(x: rect.midX, y: rect.midY)

    for step in 0...samples {
        let theta = (CGFloat(step) / CGFloat(samples)) * 2 * .pi
        let cosT = cos(theta)
        let sinT = sin(theta)
        // Raising the magnitude and re-applying the sign keeps all four
        // quadrants; pow() on a negative base would return NaN.
        let x = centre.x + a * copysign(pow(abs(cosT), 2 / exponent), cosT)
        let y = centre.y + b * copysign(pow(abs(sinT), 2 / exponent), sinT)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

/// Draws into an explicitly-sized bitmap, NOT via NSImage.lockFocus.
///
/// lockFocus draws into a backing store at the SCREEN's scale factor, so on a
/// Retina display every file came out exactly twice its intended pixel size.
/// actool then rejected the whole set ("icon_512.png is 1024x1024 but should be
/// 512x512") and emitted no icon at all, which let a stale AppIcon.icns from an
/// earlier build keep showing through. The PNGs looked perfectly correct when
/// opened; only their dimensions were wrong, so nothing about the artwork gave
/// it away.
///
/// Allocating the NSBitmapImageRep with explicit pixelsWide/pixelsHigh and a
/// matching point size pins one point to one pixel regardless of the display.
func drawIcon(pixels: Int) -> NSBitmapImageRep? {
    let size = CGFloat(pixels)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext

    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let tile = CGRect(
        x: size * inset,
        y: size * inset,
        width: size * (1 - inset * 2),
        height: size * (1 - inset * 2)
    )

    // Graphite, deliberately.
    //
    // Upstream's icon is an illustrated cartoon: a squirrel in a cage trap,
    // heavy outlines, orange on blue, sticker register. Competing with that on
    // illustration is a losing game and would misrepresent what this fork is.
    // The fork's whole argument is restraint, so its icon should be a mark
    // rather than a picture, in the register of the tools it sits beside.
    //
    // Near-black rather than the app's own accent blue: upstream's tile is
    // already blue, and a coloured tile would read as a variant of it rather
    // than as a different point of view.
    let top = CGColor(srgbRed: 0x3A / 255, green: 0x3D / 255, blue: 0x45 / 255, alpha: 1)
    let bottom = CGColor(srgbRed: 0x1C / 255, green: 0x1E / 255, blue: 0x24 / 255, alpha: 1)

    let squircle = superellipse(in: tile)

    // A soft shadow under the tile. Apple's own icons sit on the desktop with
    // a little weight rather than lying flat on it, and at 128pt and up its
    // absence is what makes a hand-made icon read as pasted on.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size * 0.012),
        blur: size * 0.03,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28)
    )
    context.addPath(squircle)
    context.setFillColor(bottom)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(squircle)
    context.clip()
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [top, bottom] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: tile.midX, y: tile.maxY),
            end: CGPoint(x: tile.midX, y: tile.minY),
            options: []
        )
    }

    // A highlight across the top third, fading out well before the middle. This
    // is what suggests a lit surface rather than a flat swatch; keep it weak
    // enough that it never reads as a separate band.
    if let sheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.26),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            sheen,
            start: CGPoint(x: tile.midX, y: tile.maxY),
            end: CGPoint(x: tile.midX, y: tile.midY),
            options: []
        )
    }
    context.restoreGState()

    // A hairline just inside the edge, darker at the bottom than the top, so
    // the tile has a defined boundary against a light desktop without a drawn
    // border.
    context.saveGState()
    context.addPath(squircle)
    context.setLineWidth(max(1, size * 0.004))
    context.setStrokeColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.12))
    context.strokePath()
    context.restoreGState()

    // The source render is black strokes on white. Inverting its luminance
    // turns it into an alpha mask, so clipping to that mask and filling paints
    // only the strokes and drops the background entirely.
    if let glyph = NSImage(contentsOf: glyphSource),
       let cgGlyph = glyph.cgImage(forProposedRect: nil, context: nil, hints: nil),
       let mask = invertedMask(from: cgGlyph) {
        // 0.54 of the tile, not 0.62. A mark that crowds its own edges reads as
        // cheap at large sizes; the margin is what makes it look placed rather
        // than stretched to fit.
        let side = tile.width * 0.54
        let glyphRect = CGRect(
            x: tile.midX - side / 2,
            y: tile.midY - side / 2,
            width: side,
            height: side
        )
        context.saveGState()
        context.clip(to: glyphRect, mask: mask)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(glyphRect)
        context.restoreGState()
    }

    return rep
}

/// Writes the rep and reports its ACTUAL pixel dimensions, not the ones that
/// were asked for. The previous version printed the requested size, which is
/// how a whole set of double-sized files passed as correct.
func write(_ rep: NSBitmapImageRep, to name: String) {
    guard let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: outputDirectory.appendingPathComponent(name))
    print("wrote \(name) at \(rep.pixelsWide)x\(rep.pixelsHigh)")
}

// (points, scale) pairs matching the Contents.json already in the asset catalog.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

for (points, scale) in variants {
    let pixels = points * scale
    guard let rep = drawIcon(pixels: pixels) else {
        print("FAILED to draw icon at \(pixels)px")
        continue
    }
    // Refuse to ship a file actool will reject. This exact mismatch went
    // unnoticed for a whole session because the artwork looked right.
    guard rep.pixelsWide == pixels, rep.pixelsHigh == pixels else {
        print("FAILED: drew \(rep.pixelsWide)x\(rep.pixelsHigh), expected \(pixels)x\(pixels)")
        continue
    }
    let name = scale == 1 ? "icon_\(points).png" : "icon_\(points)@2x.png"
    write(rep, to: name)
}
