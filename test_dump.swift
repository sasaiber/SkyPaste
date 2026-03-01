import AppKit

let pb = NSPasteboard.general
if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let image = images.first {
    print("Found image!")
    let fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("SkyPaste/Images", isDirectory: true)
    
    do {
        try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
        let fullPath = fileURL.appendingPathComponent("test_dump.png")
        
        var pngData: Data? = nil
        if let tiffData = image.tiffRepresentation,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           let data = bitmapRep.representation(using: .png, properties: [:]) {
            pngData = data
            print("Converted using TIFF")
        } else if let rawPNG = pb.data(forType: .png) {
            pngData = rawPNG
            print("Converted using raw PNG")
        } else {
            let rect = NSRect(origin: .zero, size: image.size)
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(rect.width), pixelsHigh: Int(rect.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
            
            NSGraphicsContext.saveGraphicsState()
            if let r = rep, let ctx = NSGraphicsContext(bitmapImageRep: r) {
                NSGraphicsContext.current = ctx
                image.draw(in: rect)
                NSGraphicsContext.restoreGraphicsState()
                pngData = r.representation(using: .png, properties: [:])
                print("Converted using fallback Canvas")
            }
        }
        
        if let finalData = pngData {
            try finalData.write(to: fullPath)
            print("Wrote \(finalData.count) bytes to \(fullPath.path)")
        } else {
            print("Could not get PNG data")
        }
    } catch {
        print("Exception: \(error)")
    }
} else {
    print("No images found in pasteboard.")
    print("Available types: \(pb.types ?? [])")
}
