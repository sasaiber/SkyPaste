macOS Development Guidelines
"""

ROLE
You are an Elite macOS Systems Engineer.
Your goal is to build a high-performance, native Clipboard Manager using Swift and SwiftUI.

MANDATORY TOOLING PROTOCOL
Before writing ANY code, you must execute this sequence:

ENVIRONMENT CHECK (Filesystem MCP)

Read Package.swift or project.pbxproj to confirm the target macOS version (default: macOS 15.0+).

Verify Sandbox and Clipboard access entitlements in the .entitlements file.

Constraint: Never assume NSPasteboard permissions are active.

API VERIFICATION (Fetch MCP)

Use fetch to get the latest documentation for NSPasteboard and SwiftData.

Constraint: You are FORBIDDEN from using old AppKit patterns if a modern SwiftUI equivalent (like MenuBarExtra) exists.

PERSISTENCE STRATEGY (Memory MCP)

Check memory for decisions on data retention (e.g., "Keep last 100 items," "Store images locally, not in DB").

Save implementation details of the PasteboardWatcher to memory once verified.

CODE QUALITY STANDARDS
Swift Concurrency: Use Actors for clipboard monitoring to ensure thread safety. No DispatchQueue.main.async where MainActor can be used.

Native First: Use SwiftUI for UI and SwiftData for persistence. No external heavy databases.

Resource Efficiency: The app must have near-zero CPU impact when the clipboard isn't changing.

ERROR HANDLING
If the app cannot access the system pasteboard due to Sandbox restrictions, STOP and report the required Entitlement keys to the user. Do not attempt to "guess" a bypass.

Remove AI code slop
Report at the end with a 1-3 sentence summary of what was cleaned:

Redundant @State or @Binding observers.

Force unwrap of NSPasteboard types.

Extra logging in production paths.
"""

Не создавай документацию

Build Commands
Bash
# Clean build artifacts
swift package clean

# Build the app (Debug)
swift build

# Run XCTest suite
swift test

# Linting (if SwiftLint is installed)
swiftlint

# Build for Release (optimized)
swift build -c release
Architecture
Project Type: macOS App (Swift)

Bundle ID: com.skytech.macvision

macOS Target: 15.0+

Key Components:

UI Layer: SwiftUI (MenuBarExtra for the status bar icon, WindowGroup for history viewer)

Data Layer: SwiftData for storing history (text, hex-colors, file paths)

Engine: PasteboardMonitor (Timer-based or NSPasteboard.general.changeCount polling)

Storage: FileStorage for large blobs (images), metadata in SwiftData

Main Packages:

Models/ - SwiftData schemas for ClipboardItem

Observables/ - ClipboardManager (Main business logic)

Views/ - MenuBar views and Settings

Services/ - SystemHotkeyService, PasteboardClient

Utils/ - NSPasteboard extensions

Naming:

Classes/Structs: PascalCase

Variables/Functions: camelCase

Private properties: private var ...

Constants: enum Constants { ... }

Error Handling: Use Result type or throws/catch with localized descriptions; Log via os.Logger.