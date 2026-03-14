import AppKit
import SwiftUI

@main
struct AnmiteTouchMacApp: App {
    @StateObject private var model = MenuBarAppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(model: model)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.menu)

        Window("Settings", id: "settings") {
            SettingsView(model: model)
                .frame(minWidth: 620, minHeight: 560)
        }
    }
}

private struct MenuBarContentView: View {
    @ObservedObject var model: MenuBarAppModel
    @Environment(\.openWindow) private var openWindow

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
                model.requestPermissions()
            }

            Button("Open Settings…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")

                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows
                        .first(where: { $0.title == "Settings" })?
                        .makeKeyAndOrderFront(nil)
                }
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
