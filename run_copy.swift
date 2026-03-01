import AppKit

let pb = NSPasteboard.general
pb.clearContents()

let imagePath = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/UserIcon.icns"
if let image = NSImage(contentsOfFile: imagePath) {
    pb.writeObjects([image])
    print("Copied an image to pasteboard.")
} else {
    print("Failed to load image.")
}
