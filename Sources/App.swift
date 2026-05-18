import SwiftUI
import AppKit
import os
import UserNotifications
import ServiceManagement
import ApplicationServices

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
    var isPickingEmoji = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)
        self.globalStore = Storage()
        
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
            self?.globalStore.selectedFolderID = nil
            self?.togglePopover(nil)
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
        
        HotkeyManager.shared.start()
        
        let monitor = ClipboardMonitor(storage: self.globalStore)
        monitor.start()
        self.monitorRef = monitor
        
        UserDefaults.standard.register(defaults: [
            "enableNotifications": true,
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
        ])
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                self.requestNotificationPermission()
            }
        }
        setupNotificationDelegate()
        
        // Sync login item using correct API per OS version (fresh 2026 best practice)
        let wantsLogin = UserDefaults.standard.bool(forKey: "launchAtLoginEnabled")
        if #available(macOS 13.0, *) {
            if wantsLogin {
                try? SMAppService.mainApp.register()
            }
        } else {
            // Legacy path for older macOS (still works)
            if wantsLogin {
                SMLoginItemSetEnabled("com.sky.skypaste" as CFString, true)
            }
        }
        
        cleanOrphanedImages()
        
        if !UserDefaults.standard.bool(forKey: "hasSeenWelcome") {
            showWelcomeWindow()
        }
        
        Task {
            if UpdateChecker.shared.shouldAutoCheck() {
                await UpdateChecker.shared.checkForUpdates()
            }
        }
    }
    
    private func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
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
        menu.addItem(NSMenuItem(title: "Quit SkyPaste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        if let button = self.statusBarItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.frame.maxY), in: button)
        }
    }
    
    @MainActor @objc func statusItemPaste(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardItem else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        pasteFromClipboard(item: item, plainTextOnly: false, shouldPaste: true)
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard UserDefaults.standard.bool(forKey: "hasSeenWelcome") else {
            DispatchQueue.main.async { self.showWelcomeWindow() }
            return
        }
        if WindowManager.shared.isWindowVisible {
            WindowManager.shared.close()
        } else {
            self.previousApp = NSWorkspace.shared.frontmostApplication
            
            if popupHostingView == nil {
                let mainView = MainView(storage: self.globalStore)
                let hostingView = NSHostingView(rootView: mainView)
                hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
                self.popupHostingView = hostingView
            }
            
            let size = NSSize(width: 400, height: 600)
            let position = UserDefaults.standard.string(forKey: "popupPosition") ?? "cursor"
            
            let button = position == "statusItem" ? self.statusBarItem.button : nil
            if let view = self.popupHostingView {
                WindowManager.shared.show(contentView: view, size: size, at: position, button: button)
            }
            
            setupOutsideClickMonitor()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    private func setupOutsideClickMonitor() {
        removeOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            if self.isPickingEmoji {
                self.isPickingEmoji = false // Ignore this click (which closes character palette), but reset the flag
                return
            }
            WindowManager.shared.close()
            self.removeOutsideClickMonitor()
        }
    }
    
    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
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
    
    @MainActor func showWelcomeWindow() {
        if let window = welcomeWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let welcomeView = WelcomeView(onContinue: { [weak self] in
            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
                self?.welcomeWindow?.orderOut(nil)
                self?.welcomeWindow = nil
                self?.togglePopover(nil)
            }
        })
        
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 450, height: 450),
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
        // If app was moved to Trash, auto-run full uninstall cleanup
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.contains("/.Trash/") || bundlePath.contains("/Trash/") {
            let bundleID = "com.sky.skypaste"
            try? SMAppService.mainApp.unregister()
            let script = """
            sleep 5
            /usr/bin/tccutil reset All \(bundleID) 2>/dev/null || true
            /usr/bin/tccutil reset Accessibility \(bundleID) 2>/dev/null || true
            /usr/bin/tccutil reset Notifications \(bundleID) 2>/dev/null || true
            sqlite3 ~/Library/Application\\ Support/com.apple.TCC/TCC.db "DELETE FROM access WHERE client LIKE '%sky%' OR client LIKE '%skypaste%' OR client LIKE '%\(bundleID)%';" 2>/dev/null || true
            sqlite3 /Library/Application\\ Support/com.apple.TCC/TCC.db "DELETE FROM access WHERE client LIKE '%sky%' OR client LIKE '%skypaste%' OR client LIKE '%\(bundleID)%';" 2>/dev/null || true
            rm -f /Library/Application\\ Support/com.apple.TCC/AdhocSignatureCache/* 2>/dev/null || true
            rm -f ~/Library/Application\\ Support/com.apple.TCC/AdhocSignatureCache/* 2>/dev/null || true
            killall -HUP cfprefsd 2>/dev/null || true
            rm -rf ~/Library/Application\\ Support/SkyPaste ~/Library/Application\\ Support/com.sky* ~/Library/Caches/SkyPaste ~/Library/Caches/com.sky* ~/Library/Logs/SkyPaste ~/Library/Logs/com.sky* ~/.SkyPaste ~/Library/Preferences/com.sky* ~/Library/Preferences/com.sky.skypaste* ~/Library/Preferences/\(bundleID)* ~/Library/Containers/com.sky* ~/Library/Containers/\(bundleID)* 2>/dev/null || true
            /usr/bin/defaults delete \(bundleID) 2>/dev/null || true
            /usr/bin/defaults delete \(bundleID) hasSeenWelcome 2>/dev/null || true
            /usr/bin/defaults delete \(bundleID) hasRequestedNotifications 2>/dev/null || true
            /usr/bin/defaults delete \(bundleID) hasRequestedAccessibility 2>/dev/null || true
            /bin/launchctl remove \(bundleID) 2>/dev/null || true
            rm -f ~/Library/LaunchAgents/\(bundleID)*.plist /Library/LaunchAgents/\(bundleID)*.plist 2>/dev/null || true
            """
            let p = Process()
            p.launchPath = "/bin/bash"
            p.arguments = ["-c", script]
            try? p.run()
            p.waitUntilExit()
        }
        
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
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
