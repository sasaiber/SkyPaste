import SwiftUI
import ServiceManagement
import ApplicationServices
import UserNotifications

enum OnboardingStep {
    case welcome
    case shortcuts
}

struct WelcomeView: View {
    @State private var hasAccessibility = AXIsProcessTrusted()
    @State private var hasNotifications = false
    @State private var currentStep: OnboardingStep = .welcome
    @State private var accessibilityCheckTimer: Timer?
    let onContinue: () -> Void
    
    @AppStorage("hk1Key") private var hk1Key: String = "s"
    @AppStorage("hk1Modifiers") private var hk1Modifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hk2Key") private var hk2Key: String = "v"
    @AppStorage("hk2Modifiers") private var hk2Modifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue | NSEvent.ModifierFlags.option.rawValue)
    
    @AppStorage("hkPinKey") private var hkPinKey: String = "p"
    @AppStorage("hkPinModifiers") private var hkPinModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkDeleteKey") private var hkDeleteKey: String = "delete"
    @AppStorage("hkDeleteModifiers") private var hkDeleteModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFolderKey") private var hkFolderKey: String = "f"
    @AppStorage("hkFolderModifiers") private var hkFolderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFinderKey") private var hkFinderKey: String = "f"
    @AppStorage("hkFinderModifiers") private var hkFinderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue | NSEvent.ModifierFlags.shift.rawValue)
    
    @AppStorage("hkLibraryKey") private var hkLibraryKey: String = "a"
    @AppStorage("hkLibraryModifiers") private var hkLibraryModifiers: Int = Int(NSEvent.ModifierFlags.option.rawValue)
    @AppStorage("launchAtLoginEnabled") private var launchAtLogin: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if currentStep == .welcome {
                welcomeStep
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                shortcutsStep
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
        .frame(width: 500, height: 720)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .onAppear {
            if #available(macOS 13.0, *) {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
            checkNotificationStatus()
            checkAccessibilityStatus()
            startAccessibilityPolling()
            if !UserDefaults.standard.bool(forKey: "hasRequestedNotifications") {
                requestNotificationPermission()
                UserDefaults.standard.set(true, forKey: "hasRequestedNotifications")
            }
        }
        .onDisappear {
            accessibilityCheckTimer?.invalidate()
            accessibilityCheckTimer = nil
        }
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            if let appIcon = NSImage(named: NSImage.Name("AppIcon")) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 90, height: 90)
                    .padding(.top, 40)
            } else {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue.gradient)
                    .padding(.top, 40)
            }
            
            VStack(spacing: 8) {
                Text("Welcome to SkyPaste")
                    .font(.system(size: 28, weight: .bold))
                Text("Your clipboard history, always one shortcut away.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "arrow.right.doc.on.clipboard", color: .green, title: "Auto-Paste", desc: "Instantly paste history into the active window.")
                FeatureRow(icon: "bell.badge.fill", color: .red, title: "Notifications", desc: "Get alerts when items are copied to the clipboard.")
                
                Divider().padding(.vertical, 8)
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: hasAccessibility ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasAccessibility ? .green : .orange)
                        .font(.title2)
                        .symbolEffect(.bounce, value: hasAccessibility)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Permissions")
                            .fontWeight(.semibold)
                        Text("Required for the Auto-Paste feature (⌘V simulation).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: hasNotifications ? "checkmark.seal.fill" : "bell.fill")
                        .foregroundColor(hasNotifications ? .green : .blue)
                        .font(.title2)
                        .symbolEffect(.bounce, value: hasNotifications)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Notification Permissions")
                            .fontWeight(.semibold)
                        Text("Required to alert you when items are copied or pasted.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            if !hasAccessibility || !hasNotifications {
                VStack(spacing: 12) {
                    Button(action: requestPermissions) {
                        Text("Grant Permissions")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                    
                    Button("Continue Without Auto-Paste/Alerts") {
                        withAnimation(.spring()) { currentStep = .shortcuts }
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            } else {
                Button(action: {
                    withAnimation(.spring()) { currentStep = .shortcuts }
                }) {
                    Text("Continue")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
            }
        }
    }
    
    private var shortcutsStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 44))
                .foregroundStyle(.purple.gradient)
                .padding(.top, 24)
            
            VStack(spacing: 4) {
                Text("Your Keyboard Shortcuts")
                    .font(.system(size: 24, weight: .bold))
                Text("Click any shortcut to change it.")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    // Global shortcuts
                    Text("Global (works anywhere)").font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 40)
                    
                    shortcutRow(title: "Show SkyPaste", desc: "Open clipboard history", key: $hk1Key, mod: $hk1Modifiers)
                    shortcutRow(title: "Paste Plain Text", desc: "Paste without formatting", key: $hk2Key, mod: $hk2Modifiers)
                    
                    Divider().padding(.horizontal, 40)
                    
                    // In-app shortcuts
                    Text("In SkyPaste window").font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 40)
                    
                    shortcutRow(title: "Quick Pin", desc: "Pin/unpin hovered item", key: $hkPinKey, mod: $hkPinModifiers)
                    shortcutRow(title: "Quick Delete", desc: "Delete hovered item", key: $hkDeleteKey, mod: $hkDeleteModifiers)
                    shortcutRow(title: "Create Folder", desc: "Move item to new folder", key: $hkFolderKey, mod: $hkFolderModifiers)
                    shortcutRow(title: "View in Finder", desc: "Show file in Finder", key: $hkFinderKey, mod: $hkFinderModifiers)
                    shortcutRow(title: "Library", desc: "Browse all folders", key: $hkLibraryKey, mod: $hkLibraryModifiers)
                    
                    Divider().padding(.horizontal, 40)
                    
                    // Preview panel hints
                    Text("In Preview panel (hover to open)").font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 40)
                    
                    HStack(spacing: 8) {
                        Text("⇧+Click").font(.system(size: 11, weight: .medium, design: .monospaced)).padding(4).background(Color.secondary.opacity(0.15)).cornerRadius(4)
                        Text("Toggle select files").font(.caption).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 40)
                    
                    HStack(spacing: 8) {
                        Text("⌘+Click").font(.system(size: 11, weight: .medium, design: .monospaced)).padding(4).background(Color.secondary.opacity(0.15)).cornerRadius(4)
                        Text("Select single file").font(.caption).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 40)
                    
                    HStack(spacing: 8) {
                        Text("⌥+Click").font(.system(size: 11, weight: .medium, design: .monospaced)).padding(4).background(Color.secondary.opacity(0.15)).cornerRadius(4)
                        Text("Paste plain text").font(.caption).foregroundColor(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 40)
                }
                .padding(.vertical, 4)
            }
            
            Spacer()
            
            Toggle("Launch at Login", isOn: $launchAtLogin)
                .toggleStyle(SwitchToggleStyle(tint: .blue))
                .onChange(of: launchAtLogin) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "launchAtLoginEnabled")
                    if #available(macOS 13.0, *) {
                        if newValue {
                            SMAppService.mainApp.registerSafe()
                        } else {
                            SMAppService.mainApp.unregisterSafe()
                        }
                    } else {
                        SMLoginItemSetEnabled("com.sky.skypaste" as CFString, newValue)
                    }
                }
                .padding(.horizontal, 40)
            
            Button(action: {
                UserDefaults.standard.set(true, forKey: "hasDismissedWelcome")
                HotkeyManager.shared.start()
                onContinue()
            }) {
                Text("Start Using SkyPaste")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 24)
        }
    }
    
    private func shortcutRow(title: String, desc: String, key: Binding<String>, mod: Binding<Int>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.medium).font(.system(size: 13))
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            ShortcutRecorder(actionName: title, keyString: key, modifiers: mod, onValidate: { _,_,_ in nil })
                .scaleEffect(0.85)
        }
        .padding(.horizontal, 40)
    }
    
    private func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    self.requestNotificationPermission()
                case .denied, .provisional:
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                        NSWorkspace.shared.open(url)
                    }
                case .authorized:
                    self.hasNotifications = true
                @unknown default:
                    break
                }
            }
        }
    }
    
    private func checkAccessibilityStatus() {
        self.hasAccessibility = AXIsProcessTrusted()
    }
    
    private func startAccessibilityPolling() {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            let trusted = AXIsProcessTrusted()
            if trusted != self.hasAccessibility {
                DispatchQueue.main.async {
                    self.hasAccessibility = trusted
                }
            }
        }
    }
    
    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.hasNotifications = settings.authorizationStatus == .authorized
            }
        }
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.hasNotifications = granted
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Image(systemName: icon)
                .font(.title)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
