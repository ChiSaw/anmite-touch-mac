import AppKit
import SwiftUI

@main
struct TouchMonitorMenuBarApp: App {
    @StateObject private var model = MenuBarAppModel()

    var body: some Scene {
        MenuBarExtra {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.isRunning ? "Monitoring active" : "Monitoring stopped")
                    .font(.headline)
                Text(model.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Divider()

                Button(model.isRunning ? "Stop Monitoring" : "Start Monitoring") {
                    model.toggleMonitoring()
                }

                Button("Request Permissions") {
                    model.requestPermissions()
                }

                SettingsLink {
                    Text("Settings…")
                }

                Divider()

                Button("Quit") {
                    NSApp.terminate(nil)
                }
            }
            .padding(.vertical, 4)
            .frame(width: 240, alignment: .leading)
        } label: {
            Image(systemName: model.isRunning ? "hand.point.up.left.fill" : "hand.point.up.left")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
                .frame(minWidth: 620, minHeight: 560)
        }
    }
}
