import AppKit

let pb = NSPasteboard.general
// check if we can read an image
let types = pb.types ?? []
print("Types:", types)
if let tiff = pb.data(forType: .tiff) {
    print("Got TIFF data, \(tiff.count) bytes")
}
if let png = pb.data(forType: .png) {
    print("Got PNG data, \(png.count) bytes")
}
if let img = NSImage(pasteboard: pb) {
    print("NSImage(pasteboard:) worked, size: \(img.size)")
}
