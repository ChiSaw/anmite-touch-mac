import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: MenuBarAppModel

    var body: some View {
        Group {
            if model.isShowingPermissionGuide {
                PermissionGuideView(model: model)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Form {
                        Section("Touch Input") {
                            Toggle("Enable pointer and scrolling injection", isOn: binding(\.enableInjection))
                            Text("Use the Anmite touch display to move the pointer, click, drag, and scroll on macOS.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Section("Device Defaults") {
                            TextField("Vendor ID", text: binding(\.vendorIDText))
                            TextField("Product ID", text: binding(\.productIDText))
                            TextField("Display ID (optional)", text: binding(\.displayIDText))
                            Text("The default USB identifiers are pre-filled for the supported Anmite touch display.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Section("Detected Displays") {
                            if model.displays.isEmpty {
                                Text("No displays are currently available.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(model.displays, id: \.id) { display in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(display.name)
                                            Text("Display ID \(display.id) • \(display.bounds.debugDescription)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Button("Use Display") {
                                            model.useDisplay(display)
                                        }
                                    }
                                }
                                Button("Use Automatic Selection") {
                                    model.clearDisplaySelection()
                                }
                            }
                        }

                        Section("Permissions") {
                            Text(model.permissionSummary)
                                .font(.caption)
                            HStack {
                                Button("Open Permission Guide") {
                                    model.reviewPermissions()
                                }
                                Button("Refresh Status") {
                                    model.refreshEnvironment()
                                }
                            }
                            Text("Grant Input Monitoring and Accessibility so the app can read touch input and send pointer events.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Section("About") {
                            Text("Anmite Touch Mac")
                            Text("Touch input bridge for macOS")
                                .foregroundStyle(.secondary)
                            Text(model.settingsFooter)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    HStack {
                        Button(model.isRunning ? "Disconnect" : "Connect") {
                            model.toggleConnection()
                        }
                        Text(model.statusLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Diagnostics")
                            .font(.headline)
                        ScrollView {
                            Text(model.logs.isEmpty ? "No diagnostic messages yet." : model.logs)
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
        }
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

private struct PermissionGuideView: View {
    @ObservedObject var model: MenuBarAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.permissionGuideStepLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text(model.permissionGuideTitle)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                Text(model.permissionGuideMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Current status")
                    .font(.headline)
                Text(model.permissionSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            HStack(spacing: 12) {
                Button(model.permissionGuidePrimaryButtonTitle) {
                    model.performPermissionGuidePrimaryAction()
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh Status") {
                    model.refreshPermissionGuideStatus()
                }
                .buttonStyle(.bordered)
            }

            Text("After granting access in System Settings, return to Anmite Touch Mac. The guide will move to the next step automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
