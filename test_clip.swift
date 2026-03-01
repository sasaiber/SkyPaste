import AppKit
let pb = NSPasteboard.general
if let image = NSImage(pasteboard: pb) {
    if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
        if let data = rep.representation(using: .png, properties: [:]) {
            print("Successfully extracted image using TIFF rep, \(data.count) bytes")
        }
    } else {
        let rect = NSRect(origin: .zero, size: image.size)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
        NSGraphicsContext.saveGraphicsState()
        if let r = rep, let ctx = NSGraphicsContext(bitmapImageRep: r) {
            NSGraphicsContext.current = ctx
            image.draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            if let data = r.representation(using: .png, properties: [:]) {
                print("Successfully extracted image using fallback Canvas context, \(data.count) bytes")
            } else {
                print("Canvas fallback failed bounds export")
            }
        } else {
            print("Failed to initialize canvas context")
        }
    }
} else {
    print("Could not load NSImage from Pasteboard")
}
