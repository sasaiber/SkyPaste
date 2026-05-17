import SwiftUI

struct StorageTabView: View {
    @ObservedObject var storage: Storage
    
    @AppStorage("cacheLimitMB") private var limitMB: Double = 999.0
    @AppStorage("retainDays") private var retainDays: Int = 30
    @AppStorage("neverDelete") private var neverDelete: Bool = false
    
    @State private var showFactoryResetConfirmation = false
    
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
    }
}
