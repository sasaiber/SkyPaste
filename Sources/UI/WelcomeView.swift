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
    
    @AppStorage("hkDeleteKey") private var hkDeleteKey: String = "delete"
    @AppStorage("hkDeleteModifiers") private var hkDeleteModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
    
    @AppStorage("hkFolderKey") private var hkFolderKey: String = "f"
    @AppStorage("hkFolderModifiers") private var hkFolderModifiers: Int = Int(NSEvent.ModifierFlags.command.rawValue)
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
        .frame(width: 500, height: 550)
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
        VStack(spacing: 20) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 50))
                .foregroundStyle(.purple.gradient)
                .padding(.top, 30)
            
            VStack(spacing: 6) {
                Text("Configure Your Workflow")
                    .font(.system(size: 26, weight: .bold))
                Text("Customize your shortcuts and launch behavior.")
                    .font(.body)
                    .foregroundColor(.secondary)
                Text("Click any shortcut below to change it.")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show SkyPaste").fontWeight(.medium)
                        Text("Open clipboard history anytime.").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(actionName: "Show SkyPaste", keyString: $hk1Key, modifiers: $hk1Modifiers, onValidate: { _,_,_ in nil })
                        .scaleEffect(0.9)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Quick Delete").fontWeight(.medium)
                        Text("Delete the currently hovered item.").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(actionName: "Quick Delete", keyString: $hkDeleteKey, modifiers: $hkDeleteModifiers, onValidate: { _,_,_ in nil })
                        .scaleEffect(0.9)
                }
                
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create Folder").fontWeight(.medium)
                        Text("Move the hovered item to a new folder.").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    ShortcutRecorder(actionName: "Create Folder", keyString: $hkFolderKey, modifiers: $hkFolderModifiers, onValidate: { _,_,_ in nil })
                        .scaleEffect(0.9)
                }
                
                Divider()
                
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    .onChange(of: launchAtLogin) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "launchAtLoginEnabled")
                        if #available(macOS 13.0, *) {
                            if newValue { try? SMAppService.mainApp.register() }
                            else { try? SMAppService.mainApp.unregister() }
                        } else {
                            SMLoginItemSetEnabled("com.sky.skypaste" as CFString, newValue)
                        }
                    }
            }
            .padding(.horizontal, 40)
            
            Spacer()
            
            Button(action: {
                UserDefaults.standard.set(true, forKey: "hasDismissedWelcome")
                HotkeyManager.shared.start() // Register new shortcuts
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
            .padding(.bottom, 30)
        }
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
