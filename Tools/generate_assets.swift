import AppKit
import CoreText
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("AppIcon.iconset")

try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func bitmap(width: Int, height: Int, pointSize: CGFloat? = nil, draw: (CGFloat) -> Void) -> NSBitmapImageRep {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Failed to create bitmap")
    }

    let logicalSize = pointSize ?? CGFloat(width)
    rep.size = NSSize(width: logicalSize, height: logicalSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.shouldAntialias = true
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGFloat(width))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Failed to encode PNG")
    }
    try data.write(to: url)
}

func writeTIFF(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .tiff, properties: [:]) else {
        fatalError("Failed to encode TIFF")
    }
    try data.write(to: url)
}

func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func drawAppIcon(size: CGFloat) {
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    rect.fill()

    let inset = size * 0.078
    let body = rect.insetBy(dx: inset, dy: inset)
    let radius = size * 0.205

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = size * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.018)
    shadow.set()

    let bodyPath = roundedPath(body, radius: radius)
    NSGradient(
        starting: NSColor(calibratedRed: 0.10, green: 0.30, blue: 0.73, alpha: 1),
        ending: NSColor(calibratedRed: 0.18, green: 0.70, blue: 0.96, alpha: 1)
    )?.draw(in: bodyPath, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    let highlight = roundedPath(body.insetBy(dx: size * 0.018, dy: size * 0.018), radius: radius * 0.86)
    NSColor.white.withAlphaComponent(0.12).setStroke()
    highlight.lineWidth = max(1, size * 0.006)
    highlight.stroke()

    let keyRect = NSRect(
        x: size * 0.245,
        y: size * 0.270,
        width: size * 0.510,
        height: size * 0.500
    )
    let keyPath = roundedPath(keyRect, radius: size * 0.085)
    NSGraphicsContext.saveGraphicsState()
    let keyShadow = NSShadow()
    keyShadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
    keyShadow.shadowBlurRadius = size * 0.018
    keyShadow.shadowOffset = NSSize(width: 0, height: -size * 0.010)
    keyShadow.set()
    NSColor.white.withAlphaComponent(0.96).setFill()
    keyPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor(calibratedWhite: 0.94, alpha: 1).setStroke()
    keyPath.lineWidth = max(1, size * 0.004)
    keyPath.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let pFont = NSFont.systemFont(ofSize: size * 0.355, weight: .semibold)
    let pAttrs: [NSAttributedString.Key: Any] = [
        .font: pFont,
        .foregroundColor: NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.55, alpha: 1),
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    NSString(string: "P").draw(
        in: NSRect(x: keyRect.minX, y: keyRect.minY + size * 0.070, width: keyRect.width, height: keyRect.height * 0.80),
        withAttributes: pAttrs
    )

    if size >= 128 {
        let tagRect = NSRect(
            x: size * 0.570,
            y: size * 0.220,
            width: size * 0.205,
            height: size * 0.170
        )
        let tag = roundedPath(tagRect, radius: size * 0.045)
        NSColor(calibratedRed: 0.06, green: 0.18, blue: 0.42, alpha: 0.94).setFill()
        tag.fill()
        NSColor.white.withAlphaComponent(0.18).setStroke()
        tag.lineWidth = max(1, size * 0.003)
        tag.stroke()

        let hFont = NSFont(name: "AppleSDGothicNeo-Bold", size: size * 0.090)
            ?? NSFont.systemFont(ofSize: size * 0.090, weight: .bold)
        let hAttrs: [NSAttributedString.Key: Any] = [
            .font: hFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
            .kern: 0
        ]
        NSString(string: "한").draw(
            in: NSRect(x: tagRect.minX, y: tagRect.minY + size * 0.035, width: tagRect.width, height: tagRect.height * 0.62),
            withAttributes: hAttrs
        )
    }
}

func centeredTextOrigin(text: String, attributes: [NSAttributedString.Key: Any], canvasSize: CGFloat) -> NSPoint {
    let attributed = NSAttributedString(string: text, attributes: attributes)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
    let suggested = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: attributed.length),
        nil,
        CGSize(width: canvasSize * 2, height: canvasSize * 2),
        nil
    )
    return NSPoint(
        x: (canvasSize - suggested.width) * 0.5,
        y: (canvasSize - suggested.height) * 0.5
    )
}

func drawInputGlyphRep(
    _ glyph: String,
    fontName: String?,
    fontSize: CGFloat,
    canvasSize: CGFloat,
    pixels: Int,
    xOffset: CGFloat,
    yOffset: CGFloat
) -> NSBitmapImageRep {
    bitmap(width: pixels, height: pixels, pointSize: canvasSize) { _ in
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = fontName.flatMap { NSFont(name: $0, size: fontSize) }
            ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.02, alpha: 0.92),
            .paragraphStyle: paragraph,
            .kern: 0
        ]
        let origin = centeredTextOrigin(text: glyph, attributes: attrs, canvasSize: canvasSize)
        NSString(
            string: glyph
        ).draw(
            at: NSPoint(x: origin.x + xOffset, y: origin.y + yOffset),
            withAttributes: attrs
        )
    }
}

func drawGlyphPDF(
    _ glyph: String,
    fontName: String?,
    fontSize: CGFloat,
    canvasSize: CGFloat,
    xOffset: CGFloat = 0,
    yOffset: CGFloat = 0,
    to url: URL
) throws {
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
        fatalError("Failed to create PDF consumer")
    }

    var mediaBox = CGRect(x: 0, y: 0, width: canvasSize, height: canvasSize)
    guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create PDF context")
    }

    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let font = fontName.flatMap { NSFont(name: $0, size: fontSize) }
        ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.0, alpha: 1.0),
        .paragraphStyle: paragraph,
        .kern: 0
    ]
    let origin = centeredTextOrigin(text: glyph, attributes: attrs, canvasSize: canvasSize)
    NSString(string: glyph).draw(
        at: NSPoint(x: origin.x + xOffset, y: origin.y + yOffset),
        withAttributes: attrs
    )

    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    try (data as Data).write(to: url)
}

func drawInputGlyph(_ glyph: String, fontName: String?, fontSize: CGFloat, xOffset: CGFloat = 0, yOffset: CGFloat = 0) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16))
    image.addRepresentation(drawInputGlyphRep(glyph, fontName: fontName, fontSize: fontSize, canvasSize: 16, pixels: 16, xOffset: xOffset, yOffset: yOffset))
    image.addRepresentation(drawInputGlyphRep(glyph, fontName: fontName, fontSize: fontSize, canvasSize: 16, pixels: 32, xOffset: xOffset, yOffset: yOffset))
    return image
}

func drawPaletteGlyphRep(_ glyph: String, fontName: String?, fontSize: CGFloat, canvasSize: CGFloat, pixels: Int, xOffset: CGFloat, yOffset: CGFloat) -> NSBitmapImageRep {
    bitmap(width: pixels, height: pixels, pointSize: canvasSize) { _ in
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: canvasSize, height: canvasSize).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = fontName.flatMap { NSFont(name: $0, size: fontSize) }
            ?? NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedWhite: 0.02, alpha: 0.92),
            .paragraphStyle: paragraph,
            .kern: 0
        ]
        let origin = centeredTextOrigin(text: glyph, attributes: attrs, canvasSize: canvasSize)
        NSString(string: glyph).draw(
            at: NSPoint(x: origin.x + xOffset, y: origin.y + yOffset),
            withAttributes: attrs
        )
    }
}

func drawPaletteGlyph(_ glyph: String, fontName: String?, fontSize: CGFloat, xOffset: CGFloat = 0, yOffset: CGFloat = 0) -> NSImage {
    let image = NSImage(size: NSSize(width: 32, height: 32))
    image.addRepresentation(drawPaletteGlyphRep(glyph, fontName: fontName, fontSize: fontSize, canvasSize: 32, pixels: 32, xOffset: xOffset, yOffset: yOffset))
    image.addRepresentation(drawPaletteGlyphRep(glyph, fontName: fontName, fontSize: fontSize, canvasSize: 32, pixels: 64, xOffset: xOffset, yOffset: yOffset))
    image.addRepresentation(drawPaletteGlyphRep(glyph, fontName: fontName, fontSize: fontSize, canvasSize: 32, pixels: 128, xOffset: xOffset, yOffset: yOffset))
    return image
}

func writeTIFF(_ image: NSImage, to url: URL) throws {
    guard let data = image.tiffRepresentation else {
        fatalError("Failed to encode multi-representation TIFF")
    }
    try data.write(to: url)
}

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in iconFiles {
    let rep = bitmap(width: size, height: size) { drawAppIcon(size: $0) }
    try writePNG(rep, to: iconset.appendingPathComponent(name))
}

try writeTIFF(
    drawInputGlyph("한", fontName: "AppleSDGothicNeo-Bold", fontSize: 15.0, yOffset: -1.15),
    to: root.appendingPathComponent("input-ko.tiff")
)
try drawGlyphPDF("한", fontName: "AppleSDGothicNeo-Bold", fontSize: 15.0, canvasSize: 16, yOffset: -1.15, to: root.appendingPathComponent("input-ko.pdf"))
try writeTIFF(
    drawInputGlyph("A", fontName: nil, fontSize: 16.0, yOffset: -0.20),
    to: root.appendingPathComponent("input-en.tiff")
)
try drawGlyphPDF("A", fontName: nil, fontSize: 16.0, canvasSize: 16, yOffset: -0.20, to: root.appendingPathComponent("input-en.pdf"))
try writeTIFF(
    drawInputGlyph("P", fontName: nil, fontSize: 16.0, xOffset: -0.15, yOffset: -0.20),
    to: root.appendingPathComponent("input-pritype.tiff")
)
try drawGlyphPDF("P", fontName: nil, fontSize: 16.0, canvasSize: 16, xOffset: -0.15, yOffset: -0.20, to: root.appendingPathComponent("input-pritype.pdf"))
try writeTIFF(
    drawInputGlyph("P", fontName: nil, fontSize: 16.0, xOffset: -0.15, yOffset: -0.20),
    to: root.appendingPathComponent("icon.tiff")
)
try writeTIFF(
    drawPaletteGlyph("한", fontName: "AppleSDGothicNeo-Bold", fontSize: 23.0, yOffset: -2.0),
    to: root.appendingPathComponent("palette-ko.tiff")
)
try drawGlyphPDF("한", fontName: "AppleSDGothicNeo-Bold", fontSize: 23.0, canvasSize: 32, yOffset: -2.0, to: root.appendingPathComponent("palette-ko.pdf"))
try writeTIFF(
    drawPaletteGlyph("A", fontName: nil, fontSize: 24.0, xOffset: 0, yOffset: 0.5),
    to: root.appendingPathComponent("palette-en.tiff")
)
try drawGlyphPDF("A", fontName: nil, fontSize: 24.0, canvasSize: 32, xOffset: 0, yOffset: 0.5, to: root.appendingPathComponent("palette-en.pdf"))

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("AppIcon.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    fatalError("iconutil failed with status \(process.terminationStatus)")
}

try? FileManager.default.removeItem(at: iconset)
print("Generated AppIcon.icns and input source TIFF/PDF assets.")
