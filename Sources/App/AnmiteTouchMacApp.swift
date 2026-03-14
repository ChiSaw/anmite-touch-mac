import AppKit
import SwiftUI

@main
struct AnmiteTouchMacApp: App {
    @StateObject private var model = MenuBarAppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            MenuBarLabelView(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 620, minHeight: 560)
        }
    }
}

private struct MenuBarContentView: View {
    @ObservedObject var model: MenuBarAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(model.menuTitle)
                .font(.headline)
            Text(model.menuSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            Button(model.isRunning ? "Disconnect" : "Connect") {
                model.toggleConnection()
            }

            Button("Review Permissions") {
                model.reviewPermissions()
            }

            Button("Open Settings…") {
                model.openSettingsWindow()
            }

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 240, alignment: .leading)
    }
}

private struct MenuBarLabelView: View {
    @ObservedObject var model: MenuBarAppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .frame(width: 18, height: 18)
            .onChange(of: model.settingsOpenRequestID) { _, _ in
                NSApp.activate(ignoringOtherApps: true)
                openSettings()

                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows
                        .first(where: { $0.title == "Settings" })?
                        .makeKeyAndOrderFront(nil)
                }
            }
    }
}
