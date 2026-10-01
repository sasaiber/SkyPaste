import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StorageTabView: View {
    @ObservedObject var storage: Storage
    
    @AppStorage("cacheLimitMB") private var limitMB: Double = 999.0
    @AppStorage("retainDays") private var retainDays: Int = 30
    @AppStorage("neverDelete") private var neverDelete: Bool = false
    
    @State private var showFactoryResetConfirmation = false
    @State private var backupMessage: String? = nil
    @State private var showBackupResult = false
    
    var body: some View {
        VStack(spacing: 16) {
            Section("Storage") {
                VStack(alignment: .leading, spacing: 14) {
                    LabeledContent("Maximum Size:") {
                        HStack(spacing: 12) {
                            Slider(value: $limitMB, in: 10...9999, step: 10)
                                .tint(.accentColor)
                                .frame(minWidth: 180)
                            TextField("", value: $limitMB, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 60)
                                .multilineTextAlignment(.trailing)
                            Text("MB")
                                .foregroundColor(.secondary)
                                .fixedSize()
                        }
                    }
                    
                    Toggle("Never delete automatically", isOn: $neverDelete)
                        .toggleStyle(.switch)
                        .tint(.accentColor)
                    
                    if !neverDelete {
                        LabeledContent("Retain items for:") {
                            HStack(spacing: 12) {
                                Slider(value: Binding(get: { Double(retainDays) }, set: { retainDays = Int($0) }), in: 1...365, step: 1)
                                    .tint(.accentColor)
                                    .frame(minWidth: 180)
                                TextField("", value: $retainDays, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .multilineTextAlignment(.trailing)
                                Text("Days")
                                    .foregroundColor(.secondary)
                                    .fixedSize()
                            }
                        }
                        
                        Button(role: .destructive, action: {
                            storage.clearUnpinned()
                        }) {
                            Text("Clear All Unpinned History")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
            
            Section("Backup") {
                VStack(spacing: 8) {
                    Button(action: exportBackup) {
                        Text("Export Backup…")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Button(action: importBackup) {
                        Text("Import Backup…")
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    Text("Saves history, folders, pinned items, folder shortcuts and cached images into a single file. Import merges it into the current data without duplicates.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            Section("Advanced") {
                Button(role: .destructive, action: {
                    showFactoryResetConfirmation = true
                }) {
                    Text("Factory Reset (Clear All Data)")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .alert("Factory Reset", isPresented: $showFactoryResetConfirmation) {
            Button("Reset Everything", role: .destructive) {
                storage.factoryReset()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will delete all clipboard history, folders, custom shortcuts, and settings. The app will be returned to its initial state. This action cannot be undone.")
        }
        .alert("Backup", isPresented: $showBackupResult) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backupMessage ?? "")
        }
    }
    
    private func exportBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SkyPaste-Backup.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try storage.exportBackup(to: url)
            backupMessage = "Backup exported to \(url.lastPathComponent)."
        } catch {
            backupMessage = "Export failed: \(error.localizedDescription)"
        }
        showBackupResult = true
    }
    
    private func importBackup() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let result = try storage.importBackup(from: url)
            backupMessage = "Imported \(result.items) items and \(result.folders) folders."
        } catch {
            backupMessage = "Import failed: \(error.localizedDescription)"
        }
        showBackupResult = true
    }
}
