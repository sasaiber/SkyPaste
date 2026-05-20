import SwiftUI
import AppKit
import os
import UserNotifications
import ServiceManagement
import ApplicationServices
import Sparkle

@main
struct SkyPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { Text("Settings") }
            .commands {
                CommandGroup(replacing: .saveItem) { }
                CommandGroup(replacing: .newItem) { }
                CommandGroup(replacing: .undoRedo) { }
            }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    static private(set) var shared: AppDelegate!
    var globalStore: Storage!
    var monitorRef: ClipboardMonitor?
    var previousApp: NSRunningApplication?
    
    var statusBarItem: NSStatusItem!
    var settingsWindow: NSWindow?
    var welcomeWindow: NSWindow?
    var popupHostingView: NSHostingView<MainView>?
    var outsideClickMonitor: Any?
    
    var updaterController: SPUStandardUpdaterController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Kill other running instances of the app to prevent ghost hotkeys/duplicate runs
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.skytech.macvision")
        for app in runningApps {
            if app != NSRunningApplication.current {
                app.terminate()
            }
        }
        
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        self.globalStore = Storage()
        
        UserDefaults.standard.register(defaults: [
            "SUEnableAutomaticChecks": true,
            "SUScheduledCheckInterval": 86400,
            "SUAutomaticallyUpdate": false
        ])
        
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = self.statusBarItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "SkyPaste")
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
        }
        
        if self.statusBarItem.button != nil {
            self.statusBarItem.menu = nil
        }
        
        HotkeyManager.shared.onToggleRequested = { [weak self] in
            guard let self = self else { return }
            if !WindowManager.shared.isWindowVisible {
                self.resolveFolderForActiveApp()
            }
            self.togglePopover(nil)
        }
        HotkeyManager.shared.onPastePlainRequested = { [weak self] in
            guard let self = self, let monitor = self.monitorRef else { return }
            let pb = NSPasteboard.general
            guard let string = pb.string(forType: .string) else { return }
            
            pb.clearContents()
            pb.setString(string, forType: .string)
            
            if WindowManager.shared.isWindowVisible {
                WindowManager.shared.close()
            }
            
            if let prevApp = self.previousApp {
                if #available(macOS 14.0, *) {
                    prevApp.activate(options: [])
                } else {
                    prevApp.activate(options: .activateIgnoringOtherApps)
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                monitor.triggerCmdV()
            }
        }
        HotkeyManager.shared.onFolderShortcutRequested = { [weak self] folderID in
            guard let self = self else { return }
            if self.globalStore.folders.contains(where: { $0.id == folderID }) {
                self.globalStore.selectedFolderID = folderID
                if !WindowManager.shared.isWindowVisible {
                    self.togglePopover(nil)
                }
            }
        }
        
        HotkeyManager.shared.onFolderMoveRequested = { [weak self] folderID in
            guard let self = self else { return }
            if self.globalStore.folders.contains(where: { $0.id == folderID }) {
                if WindowManager.shared.isWindowVisible, let hid = self.globalStore.hoveredItemID {
                    self.globalStore.assign(item: hid, to: folderID)
                }
            }
        }
        
        HotkeyManager.shared.onLibraryRequested = { [weak self] in
            guard let self = self else { return }
            let position = UserDefaults.standard.string(forKey: "popupPosition") ?? "cursor"
            LibraryWindowManager.shared.toggle(storage: self.globalStore, position: position)
        }
        
        HotkeyManager.shared.start()
        
        let monitor = ClipboardMonitor(storage: self.globalStore)
        monitor.start()
        self.monitorRef = monitor
        
        // Sync Launch at Login with real SMAppService status after update/rebuild
        // Prevents stale toggles and duplicate entries in System Settings > Login Items
        if #available(macOS 13.0, *) {
            let actuallyEnabled = SMAppService.mainApp.status == .enabled
            UserDefaults.standard.set(actuallyEnabled, forKey: "launchAtLoginEnabled")
        }
        
        UserDefaults.standard.register(defaults: [
            "enableNotifications": true,
            "bounceIconOnCopy": false,
            "hasRequestedAccessibility": false,
            "hk1Key": "s",
            "hk1Modifiers": Int(NSEvent.ModifierFlags.command.rawValue),
            "hk2Key": "v",
            "hk2Modifiers": Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue),
            "hkPinKey": "p",
            "hkPinModifiers": Int(NSEvent.ModifierFlags.command.rawValue),
            "hkDeleteKey": "delete",
            "hkDeleteModifiers": Int(NSEvent.ModifierFlags.command.rawValue),
            "hkFolderKey": "f",
            "hkFolderModifiers": Int(NSEvent.ModifierFlags.command.rawValue),
            "hkLibraryKey": "a",
            "hkLibraryModifiers": Int(NSEvent.ModifierFlags.option.rawValue),
        ])
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                Task { @MainActor in
                    self.requestNotificationPermission()
                }
            }
        }
        setupNotificationDelegate()
        
        // Login item is managed exclusively by the user toggle in Preferences.
        // Do NOT re-register here — with ad-hoc signing each build has a different
        // identity, so calling register() again creates a duplicate entry in
        // System Settings > Login Items.
        
        cleanOrphanedImages()
        
        // Fresh-install detection: use a marker file inside the app data directory.
        // When the user deletes ~/Library/Application Support/SkyPaste/ (e.g. via
        // AppCleaner, manual rm, or our cleanup script), the marker disappears and
        // the welcome screen shows again on next launch.
        if !FileManager.default.fileExists(atPath: Self.setupMarkerURL.path) {
            showWelcomeWindow()
        }
    }
    
    private func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }
    
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            _ = error // ignore notification error
        }
    }
    
    @MainActor @objc func statusItemClicked(_ sender: AnyObject?) {
        guard let event = NSApp.currentEvent else {
            self.globalStore.selectedFolderID = nil
            togglePopover(sender)
            return
        }
        
        if event.type == .rightMouseUp {
            showStatusItemMenu()
        } else {
            self.globalStore.selectedFolderID = nil
            togglePopover(sender)
        }
    }
    
    @MainActor private func showStatusItemMenu() {
        let menu = NSMenu()
        
        let recentItems = globalStore.items.prefix(5)
        if !recentItems.isEmpty {
            for item in recentItems {
                let title: String
                switch item.type {
                case .text, .link:
                    title = (item.textContent ?? "").components(separatedBy: .newlines).first ?? "Empty"
                case .image:
                    title = item.title ?? "Image"
                case .file:
                    title = item.title ?? item.fileURL?.lastPathComponent ?? "File"
                case .other:
                    title = "Unknown"
                }
                let menuItem = NSMenuItem(title: String(title.prefix(50)), action: #selector(statusItemPaste(_:)), keyEquivalent: "")
                menuItem.representedObject = item
                menu.addItem(menuItem)
            }
            menu.addItem(NSMenuItem.separator())
        }
        
        menu.addItem(NSMenuItem(title: "Open SkyPaste", action: #selector(togglePopover(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit SkyPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        if let button = self.statusBarItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.frame.maxY), in: button)
        }
    }
    
    @MainActor @objc func statusItemPaste(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardItem else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let defaultPlain = UserDefaults.standard.bool(forKey: "pastePlainActive")
        pasteFromClipboard(item: item, plainTextOnly: defaultPlain, shouldPaste: true)
    }
    
    @MainActor @objc func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard FileManager.default.fileExists(atPath: Self.setupMarkerURL.path) else {
            DispatchQueue.main.async { self.showWelcomeWindow() }
            return
        }
        if WindowManager.shared.isWindowVisible {
            WindowManager.shared.close()
        } else {
            self.previousApp = NSWorkspace.shared.frontmostApplication
            
            // If sender is present (e.g. status bar button click or menu click),
            // dynamically resolve folder based on active app before opening popover
            if sender != nil {
                if let bundleID = self.previousApp?.bundleIdentifier,
                   let matchingFolder = self.globalStore.folders.first(where: { $0.appBundleIDs.contains(bundleID) }) {
                    self.globalStore.selectedFolderID = matchingFolder.id
                } else {
                    self.globalStore.selectedFolderID = nil
                }
            }
            
            if popupHostingView == nil {
                let mainView = MainView(storage: self.globalStore)
                let hostingView = NSHostingView(rootView: mainView)
                self.popupHostingView = hostingView
            }
            
            let isMenuClick = sender != nil
            let position = isMenuClick ? "statusItem" : (UserDefaults.standard.string(forKey: "popupPosition") ?? "cursor")
            let button = (position == "statusItem" || isMenuClick) ? self.statusBarItem.button : nil
            
            if let view = self.popupHostingView {

                
                let size = NSSize(width: 400, height: 520)
                WindowManager.shared.show(contentView: view, size: size, at: position, button: button)
            }
            
            setupOutsideClickMonitor()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func setupOutsideClickMonitor() {
        removeOutsideClickMonitor()
        
        // 1. Local click monitor to close window when clicking on other parts of our app
        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            // Ignore cmd/shift clicks (used for selection in preview)
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
                return event
            }
            let clickPoint = NSEvent.mouseLocation
            
            // Allow clicks on NSColorPanel without closing the popover
            if let clickedWindow = event.window, clickedWindow is NSColorPanel {
                return event
            }
            
            if !WindowManager.shared.contains(clickPoint) {
                WindowManager.shared.close()
                self.removeOutsideClickMonitor()
            }
            return event
        }
        
        // 2. Observer for app resignation (clicks outside the app)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appResignedActive),
            name: NSApplication.didResignActiveNotification,
            object: nil
        )
    }
    
    @objc private func appResignedActive() {
        // System Character Palette (Emoji & Symbols) briefly steals
        // active-app status — don't close our panel while it's open.
        if let frontApp = NSWorkspace.shared.frontmostApplication,
           let bid = frontApp.bundleIdentifier,
           bid.contains("CharacterPalette") || bid.contains("Emoji") || bid.contains("InputManager") {
            return
        }

        // NSColorPanel also steals focus — keep panel open.
        if NSColorPanel.shared.isVisible {
            return
        }

        WindowManager.shared.close()
        removeOutsideClickMonitor()
    }
    
    @MainActor
    func bounceStatusItem() {
        guard UserDefaults.standard.bool(forKey: "bounceIconOnCopy") else { return }
        guard let button = self.statusBarItem.button else { return }

        button.wantsLayer = true
        guard let layer = button.layer else { return }

        // Cancel any in-progress animation
        layer.removeAllAnimations()

        // --- Scale animation: big pop then settle ---
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values   = [1.0,  1.5,  0.8,  1.2,  0.95, 1.0]
        scale.keyTimes = [0.0,  0.25, 0.5,  0.7,  0.88, 1.0]
        scale.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        scale.duration = 0.55
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = true

        // --- Opacity flash: bright then normal ---
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values   = [1.0,  0.25, 1.0,  0.6,  1.0]
        opacity.keyTimes = [0.0,  0.2,  0.45, 0.7,  1.0]
        opacity.duration = 0.55
        opacity.fillMode = .forwards
        opacity.isRemovedOnCompletion = true

        // Group both
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 0.55
        group.isRemovedOnCompletion = true

        layer.add(group, forKey: "copyFeedback")
    }
    
    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        NotificationCenter.default.removeObserver(self, name: NSApplication.didResignActiveNotification, object: nil)
    }
    
    /// Maccy-style paste: copy → close → activate target → wait → Cmd+V
    func pasteFromClipboard(item: ClipboardItem? = nil, plainTextOnly: Bool? = nil, shouldPaste: Bool = true) {
        if let item = item, let monitor = monitorRef {
            monitor.copyToPasteboard(item: item, plainTextOnly: plainTextOnly ?? false)
        }
        
        WindowManager.shared.close()
        removeOutsideClickMonitor()
        
        // Hide SkyPaste so macOS natively restores focus to the previously active application
        NSApp.hide(nil)
        
        guard shouldPaste else { return }
        
        if !AXIsProcessTrusted() {
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
            return
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.monitorRef?.triggerCmdV()
        }
    }
    
    @MainActor @objc func openSettings() {
        if WindowManager.shared.isWindowVisible {
            WindowManager.shared.close()
            removeOutsideClickMonitor()
        }
        
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let preferencesView = PreferencesView(storage: self.globalStore)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
                              styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.center()
        window.title = "SkyPaste Settings"
        window.contentViewController = NSHostingController(rootView: preferencesView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.settingsWindow = window
    }
    
    /// Marker file URL: exists only after the user completes the welcome screen.
    /// Deleting ~/Library/Application Support/SkyPaste/ removes it → fresh install.
    static var setupMarkerURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SkyPaste/.setup_complete")
    }
    
    @MainActor func showWelcomeWindow() {
        if let window = welcomeWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let welcomeView = WelcomeView(onContinue: { [weak self] in
            DispatchQueue.main.async {
                // Create the marker file so we know setup is complete
                FileManager.default.createFile(atPath: Self.setupMarkerURL.path, contents: nil)
                self?.welcomeWindow?.orderOut(nil)
                self?.welcomeWindow = nil
                self?.togglePopover(nil)
            }
        })
        
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 720),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.center()
        window.titlebarAppearsTransparent = true
        window.title = ""
        window.contentViewController = NSHostingController(rootView: welcomeView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.welcomeWindow = window
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        monitorRef?.stop()
        HotkeyManager.shared.stop()
        ImageCache.shared.clear()
        WindowManager.shared.close()
        settingsWindow = nil
        welcomeWindow = nil
    }
    
    @MainActor
    private func cleanOrphanedImages() {
        let imagesDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SkyPaste/Images")
        
        guard let currentItems = globalStore?.items else { return }
        let referencedURLs = Set(currentItems.compactMap { $0.fileURL?.lastPathComponent })
        
        do {
            let files = try FileManager.default.contentsOfDirectory(at: imagesDir, includingPropertiesForKeys: nil)
            for file in files {
                if !referencedURLs.contains(file.lastPathComponent) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        } catch {}
    }
    
    private func resolveFolderForActiveApp() {
        let activeApp = NSWorkspace.shared.frontmostApplication
        if let bundleID = activeApp?.bundleIdentifier {
            if let matchingFolder = self.globalStore.folders.first(where: { $0.appBundleIDs.contains(bundleID) }) {
                self.globalStore.selectedFolderID = matchingFolder.id
                return
            }
        }
        self.globalStore.selectedFolderID = nil
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
