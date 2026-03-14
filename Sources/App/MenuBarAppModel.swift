import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class MenuBarAppModel: ObservableObject {
    @Published var vendorIDText: String
    @Published var productIDText: String
    @Published var displayIDText: String
    @Published var enableInjection: Bool
    @Published var promptForPermissionsOnStart: Bool
    @Published var isRunning = false
    @Published var statusLine = "Disconnected"
    @Published var logs = ""
    @Published var permissions = TouchMonitorService.currentPermissionStatus()
    @Published var displays = TouchMonitorService.availableDisplays()

    private var service: TouchMonitorService?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let vendorID = "TouchMonitor.vendorID"
        static let productID = "TouchMonitor.productID"
        static let displayID = "TouchMonitor.displayID"
        static let enableInjection = "TouchMonitor.enableInjection"
        static let promptForPermissionsOnStart = "TouchMonitor.promptForPermissionsOnStart"
    }

    init() {
        vendorIDText = defaults.string(forKey: Keys.vendorID) ?? ""
        productIDText = defaults.string(forKey: Keys.productID) ?? ""
        displayIDText = defaults.string(forKey: Keys.displayID) ?? ""
        if defaults.object(forKey: Keys.enableInjection) == nil {
            defaults.set(true, forKey: Keys.enableInjection)
        }
        enableInjection = defaults.bool(forKey: Keys.enableInjection)
        promptForPermissionsOnStart = defaults.bool(forKey: Keys.promptForPermissionsOnStart)

        appendLog("Anmite Touch Mac app initialized.")
        refreshEnvironment()
        connect()
    }

    func toggleConnection() {
        isRunning ? disconnect() : connect()
    }

    func connect() {
        disconnect()
        persistSettings()
        refreshEnvironment()

        let config = TouchMonitorConfiguration(
            targetVendorID: Int(vendorIDText),
            targetProductID: Int(productIDText),
            targetDisplayID: UInt32(displayIDText),
            enableInjection: enableInjection,
            requestPermissions: promptForPermissionsOnStart,
            verboseLogging: false
        )

        let service = TouchMonitorService(config: config) { [weak self] line in
            Task { @MainActor in
                self?.appendLog(line)
                self?.statusLine = line
            }
        }

        do {
            try service.start()
            self.service = service
            isRunning = true
            statusLine = "Connected"
        } catch {
            appendLog("Failed to connect: \(error.localizedDescription)")
            statusLine = "Connect failed"
        }
    }

    func disconnect() {
        service?.stop()
        service = nil
        isRunning = false
        statusLine = "Disconnected"
    }

    func requestPermissions() {
        permissions = TouchMonitorService.currentPermissionStatus(
            requestPrompt: true,
            enableInjection: enableInjection
        )
        appendLog("Requested permission prompts.")
    }

    func refreshEnvironment() {
        displays = TouchMonitorService.availableDisplays()
        permissions = TouchMonitorService.currentPermissionStatus(enableInjection: enableInjection)
    }

    func useDisplay(_ display: DisplayTarget) {
        displayIDText = String(display.id)
        persistSettings()
    }

    func clearDisplaySelection() {
        displayIDText = ""
        persistSettings()
    }

    func persistSettings() {
        defaults.set(vendorIDText, forKey: Keys.vendorID)
        defaults.set(productIDText, forKey: Keys.productID)
        defaults.set(displayIDText, forKey: Keys.displayID)
        defaults.set(enableInjection, forKey: Keys.enableInjection)
        defaults.set(promptForPermissionsOnStart, forKey: Keys.promptForPermissionsOnStart)
    }

    var permissionSummary: String {
        [
            permissions.inputMonitoringGranted ? "Input Monitoring: yes" : "Input Monitoring: no",
            permissions.accessibilityGranted ? "Accessibility: yes" : "Accessibility: no",
            permissions.postEventsGranted ? "Post Events: yes" : "Post Events: no",
        ].joined(separator: " | ")
    }

    private func appendLog(_ line: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let newEntry = "[\(timestamp)] \(line)"
        let updated = logs.isEmpty ? newEntry : "\(logs)\n\(newEntry)"
        let maxLines = 250
        let lines = updated.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.count > maxLines {
            logs = lines.suffix(maxLines).joined(separator: "\n")
        } else {
            logs = updated
        }
    }
}
