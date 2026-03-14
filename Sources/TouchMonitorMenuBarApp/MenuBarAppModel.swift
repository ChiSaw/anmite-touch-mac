import CoreGraphics
import Foundation
import SwiftUI
import TouchMonitorPOC

@MainActor
final class MenuBarAppModel: ObservableObject {
    @Published var vendorIDText: String
    @Published var productIDText: String
    @Published var displayIDText: String
    @Published var enableInjection: Bool
    @Published var promptForPermissionsOnStart: Bool
    @Published var startOnLaunch: Bool
    @Published var isRunning = false
    @Published var statusLine = "Idle"
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
        static let startOnLaunch = "TouchMonitor.startOnLaunch"
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
        if defaults.object(forKey: Keys.startOnLaunch) == nil {
            defaults.set(true, forKey: Keys.startOnLaunch)
        }
        startOnLaunch = defaults.bool(forKey: Keys.startOnLaunch)

        appendLog("Anmite Touch Mac app initialized.")
        refreshEnvironment()

        if startOnLaunch {
            startMonitoring()
        }
    }

    func toggleMonitoring() {
        isRunning ? stopMonitoring() : startMonitoring()
    }

    func startMonitoring() {
        stopMonitoring()
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
            statusLine = "Monitoring active"
        } catch {
            appendLog("Failed to start: \(error.localizedDescription)")
            statusLine = "Start failed"
        }
    }

    func stopMonitoring() {
        service?.stop()
        service = nil
        isRunning = false
        statusLine = "Monitoring stopped"
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
        defaults.set(startOnLaunch, forKey: Keys.startOnLaunch)
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
