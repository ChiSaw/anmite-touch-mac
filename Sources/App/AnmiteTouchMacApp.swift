import AppKit
import SwiftUI

@main
struct AnmiteTouchMacApp: App {
    @StateObject private var model = MenuBarAppModel()

    var body: some Scene {
        MenuBarExtra {
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

                SettingsLink {
                    Text("Open Settings…")
                }

                Divider()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 240, alignment: .leading)
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 620, minHeight: 560)
        }
    }
}
