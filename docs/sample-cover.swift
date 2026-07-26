// Draws the sample track's cover art: white text on black.
//
// Renders into an explicitly sized bitmap rather than NSImage.lockFocus,
// which would pick up the display's scale factor and quadruple the file.
import AppKit

let side = 600

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
) else {
    FileHandle.standardError.write(Data("could not allocate bitmap\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let size = CGFloat(side)
NSColor.black.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 64, weight: .medium),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
]

let text = "example cover" as NSString
let bounds = text.boundingRect(
    with: NSSize(width: size, height: size),
    options: [.usesLineFragmentOrigin],
    attributes: attributes
)
text.draw(
    in: NSRect(x: 0, y: (size - bounds.height) / 2, width: size, height: bounds.height),
    withAttributes: attributes
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("could not encode cover\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: sample-cover.swift <output.png>\n".utf8))
    exit(1)
}

try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
