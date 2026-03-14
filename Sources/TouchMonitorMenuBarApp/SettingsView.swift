import SwiftUI
import TouchMonitorPOC

struct SettingsView: View {
    @ObservedObject var model: MenuBarAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Form {
                Section("Monitoring") {
                    Toggle("Enable injection", isOn: binding(\.enableInjection))
                    Toggle("Prompt for permissions on start", isOn: binding(\.promptForPermissionsOnStart))
                    Toggle("Start monitoring when the app launches", isOn: binding(\.startOnLaunch))
                }

                Section("Device Filters") {
                    TextField("Vendor ID (optional)", text: binding(\.vendorIDText))
                    TextField("Product ID (optional)", text: binding(\.productIDText))
                    TextField("Display ID (optional)", text: binding(\.displayIDText))
                }

                Section("Detected Displays") {
                    if model.displays.isEmpty {
                        Text("No displays detected.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.displays, id: \.id) { display in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(display.name)
                                    Text("id=\(display.id) bounds=\(display.bounds.debugDescription)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Use") {
                                    model.useDisplay(display)
                                }
                            }
                        }
                        Button("Use Automatic Display Selection") {
                            model.clearDisplaySelection()
                        }
                    }
                }

                Section("Permissions") {
                    Text(model.permissionSummary)
                        .font(.caption)
                    HStack {
                        Button("Request Permissions") {
                            model.requestPermissions()
                        }
                        Button("Refresh Environment") {
                            model.refreshEnvironment()
                        }
                    }
                }
            }

            HStack {
                Button(model.isRunning ? "Stop Monitoring" : "Start Monitoring") {
                    model.toggleMonitoring()
                }
                Text(model.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Logs")
                    .font(.headline)
                ScrollView {
                    Text(model.logs.isEmpty ? "No logs yet." : model.logs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(10)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(20)
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<MenuBarAppModel, Value>) -> Binding<Value> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { newValue in
                model[keyPath: keyPath] = newValue
                model.persistSettings()
            }
        )
    }
}
