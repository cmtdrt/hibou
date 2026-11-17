// Usage: swift scripts/make-icon.swift <logo.svg> <out.iconset>
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let logo = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write("usage: make-icon.swift <logo.svg> <out.iconset>\n".data(using: .utf8)!)
    exit(1)
}
let outDir = URL(fileURLWithPath: args[2])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.1
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225).fill()
    // The logo only covers about x 80–172 / y 63–138 of its 251×201 viewBox: zoom in on it.
    let zoom = (rect.width * 0.62) / (92 / 251 * logo.size.width) * logo.size.width
    let w = zoom, h = zoom * logo.size.height / logo.size.width
    let cx = 126.0 / 251 * w, cy = (201 - 100.5) / 201 * h
    logo.draw(in: NSRect(x: rect.midX - cx, y: rect.midY - cy, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: outDir.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: outDir.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
