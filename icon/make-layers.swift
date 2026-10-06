// Renders the Quassel glyph (ring + dot) as transparent white layers for Quassel.icon.
// Geometry follows src/pics/quassel-64.svg: ring outer r 27, inner r 20, dot r 5.5 offset (8.84, 8.84).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let outer = 330.0               // ring outer radius on the 1024 canvas
let unit = outer / 27.0
let center = CGPoint(x: size / 2, y: size / 2)

func render(_ name: String, _ draw: (CGContext) -> Void) {
    let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    draw(ctx)
    let url = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

render("ring.png") { ctx in
    ctx.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: 2 * outer, height: 2 * outer))
    let inner = 20 * unit
    ctx.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: 2 * inner, height: 2 * inner))
    ctx.fillPath(using: .evenOdd)
}

render("dot.png") { ctx in
    let r = 5.5 * unit
    // SVG y axis points down; CoreGraphics y points up
    let c = CGPoint(x: center.x + 8.84 * unit, y: center.y - 8.84 * unit)
    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
}
