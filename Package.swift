// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SkyPaste",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SkyPaste", targets: ["SkyPaste"])
    ],

    targets: [
        .executableTarget(
            name: "SkyPaste",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Combine"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
