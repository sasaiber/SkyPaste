import SwiftUI
import ApplicationServices

struct WelcomeView: View {
    @State private var hasAccessibility = AXIsProcessTrusted()
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue.gradient)
                .padding(.top, 40)
            
            VStack(spacing: 8) {
                Text("Welcome to SkyPaste")
                    .font(.system(size: 28, weight: .bold))
                Text("Your clipboard history, always one shortcut away.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            
            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "keyboard", color: .purple, title: "Global Hotkeys", desc: "Press ⌘⇧V to open from anywhere.")
                FeatureRow(icon: "arrow.right.doc.on.clipboard", color: .green, title: "Auto-Paste", desc: "Instantly paste history into the active window.")
                
                Divider().padding(.vertical, 8)
                
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: hasAccessibility ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(hasAccessibility ? .green : .orange)
                        .font(.title2)
                        .symbolEffect(.bounce, value: hasAccessibility)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Accessibility Permissions")
                            .fontWeight(.semibold)
                        Text("SkyPaste requires system permission to listen for your hotkeys and synthesize the copy/paste events securely.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 30)
            
            Spacer()
            
            if !hasAccessibility {
                VStack(spacing: 12) {
                    Button(action: requestPermissions) {
                        Text("Grant Permissions")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    .controlSize(.large)
                    
                    Button("Continue Without Hotkeys") {
                        UserDefaults.standard.set(true, forKey: "hasDismissedWelcome")
                        onContinue()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(.caption)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            } else {
                Button(action: onContinue) {
                    Text("Start Using SkyPaste")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .padding(.bottom, 30)
            }
        }
        .frame(width: 480, height: 500)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow).ignoresSafeArea())
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            withAnimation {
                let current = AXIsProcessTrusted()
                if current && !self.hasAccessibility {
                    UserDefaults.standard.set(true, forKey: "hasDismissedWelcome")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        onContinue()
                    }
                }
                self.hasAccessibility = current
            }
        }
    }
    
    private func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
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
    
    private func requestPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
