import AppKit

/// Native macOS confirmation dialog (`NSAlert`), shown above the floating panel.
@MainActor
enum ConfirmationAlert {
    struct Result {
        let confirmed: Bool
        let suppress: Bool
    }

    @discardableResult
    static func run(
        title: String,
        message: String,
        confirmTitle: String,
        destructive: Bool = true,
        suppressionTitle: String? = nil
    ) -> Result {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message

        let confirmButton = alert.addButton(withTitle: confirmTitle)
        confirmButton.hasDestructiveAction = destructive
        alert.addButton(withTitle: "Cancel")

        if let suppressionTitle {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = suppressionTitle
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        WindowManager.shared.panel?.makeKey()

        let confirmed = response == .alertFirstButtonReturn
        let suppress = alert.suppressionButton?.state == .on
        return Result(confirmed: confirmed, suppress: confirmed && suppress)
    }
}
