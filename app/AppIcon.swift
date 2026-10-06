// Draws the neutral app icon (1024×1024 PNG).
// usage: swift app/AppIcon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let output = URL(fileURLWithPath: CommandLine.arguments[1])

guard let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { exit(1) }

// Base shape following the macOS icon grid: 824×824 with rounded corners
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape)
ctx.setFillColor(CGColor(gray: 0, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
    colors: [CGColor(srgbRed: 0.36, green: 0.30, blue: 0.95, alpha: 1),
             CGColor(srgbRed: 0.13, green: 0.12, blue: 0.35, alpha: 1)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
ctx.restoreGState()

// Play symbol
let play = CGMutablePath()
play.move(to: CGPoint(x: 432, y: 640))
play.addLine(to: CGPoint(x: 432, y: 400))
play.addLine(to: CGPoint(x: 640, y: 520))
play.closeSubpath()
ctx.addPath(play)
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.setLineJoin(.round)
ctx.setLineWidth(40)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
ctx.drawPath(using: .fillStroke)

// Title bars
ctx.addPath(CGPath(roundedRect: CGRect(x: 312, y: 250, width: 400, height: 44), cornerWidth: 22, cornerHeight: 22, transform: nil))
ctx.setFillColor(CGColor(gray: 1, alpha: 0.85))
ctx.fillPath()
ctx.addPath(CGPath(roundedRect: CGRect(x: 382, y: 190, width: 260, height: 32), cornerWidth: 16, cornerHeight: 16, transform: nil))
ctx.setFillColor(CGColor(gray: 1, alpha: 0.5))
ctx.fillPath()

guard let image = ctx.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)
else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
exit(CGImageDestinationFinalize(destination) ? 0 : 1)
