// make-icon.swift -- draw the app icon as an .iconset folder.
//
//   swift scripts/make-icon.swift build/AppIcon.iconset
//   iconutil -c icns build/AppIcon.iconset -o AppIcon.icns
//
// Drawn in code so the repository holds no binary artwork. Scouts BSA olive
// with a tan border and a white monogram -- the same palette as the sign-in
// pages, and no red, which must never touch olive.

import AppKit

let outputFolder = URL(filePath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

let olive = NSColor(srgbRed: 0x24 / 255, green: 0x3E / 255, blue: 0x2C / 255, alpha: 1)
let tan = NSColor(srgbRed: 0xD6 / 255, green: 0xCE / 255, blue: 0xBD / 255, alpha: 1)

func drawIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    // macOS icon grid: the tile is inset about 10% and has ~22% corner radius.
    let tile = NSRect(x: size * 0.1, y: size * 0.1, width: size * 0.8, height: size * 0.8)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: size * 0.18, yRadius: size * 0.18)
    olive.setFill()
    tilePath.fill()
    tan.setStroke()
    tilePath.lineWidth = max(1, size * 0.02)
    let border = NSBezierPath(roundedRect: tile.insetBy(dx: size * 0.035, dy: size * 0.035), xRadius: size * 0.15, yRadius: size * 0.15)
    border.lineWidth = max(1, size * 0.012)
    border.stroke()

    let font = NSFont.systemFont(ofSize: size * 0.34, weight: .heavy)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let monogram = NSAttributedString(string: "EB", attributes: [
        .font: font, .foregroundColor: NSColor.white, .paragraphStyle: paragraph, .kern: -size * 0.01,
    ])
    let textHeight = monogram.size().height
    monogram.draw(in: NSRect(x: tile.minX, y: tile.midY - textHeight / 2 + size * 0.02, width: tile.width, height: textHeight))

    // Three small stars along the bottom, for the three-member board.
    let starY = tile.minY + size * 0.14
    for (index, offset) in [-0.14, 0.0, 0.14].enumerated() {
        let centre = CGPoint(x: tile.midX + size * offset, y: starY + (index == 1 ? size * 0.015 : 0))
        star(at: centre, radius: size * 0.035).fill(with: tan)
    }

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

func star(at centre: CGPoint, radius: CGFloat) -> NSBezierPath {
    let path = NSBezierPath()
    for point in 0..<10 {
        let angle = CGFloat(point) * .pi / 5 + .pi / 2
        let length = point.isMultiple(of: 2) ? radius : radius * 0.45
        let vertex = CGPoint(x: centre.x + cos(angle) * length, y: centre.y + sin(angle) * length)
        point == 0 ? path.move(to: vertex) : path.line(to: vertex)
    }
    path.close()
    return path
}

extension NSBezierPath {
    func fill(with color: NSColor) {
        color.setFill()
        fill()
    }
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
        try drawIcon(pixels: points * scale).write(to: outputFolder.appending(path: name))
    }
}
