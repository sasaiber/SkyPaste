import Foundation
import AppKit

func isImageFile(_ url: URL?) -> Bool {
    guard let url = url else { return false }
    let ext = url.pathExtension.lowercased()
    return ["png", "jpg", "jpeg", "gif", "tiff", "heic", "webp"].contains(ext)
}

print(isImageFile(URL(string: "file:///test.png")))
