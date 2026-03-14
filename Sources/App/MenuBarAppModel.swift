import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class MenuBarAppModel: ObservableObject {
    @Published var vendorIDText: String
    @Published var productIDText: String
    @Published var displayIDText: String
    @Published var enableInjection: Bool
    @Published var isRunning = false
    @Published var statusLine = "Touch display not connected"
    @Published var logs = ""
    @Published var permissions = TouchMonitorService.currentPermissionStatus()
    @Published var displays = TouchMonitorService.availableDisplays()

    private var service: TouchMonitorService?
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let didPresentInitialPermissionPrompts = "AnmiteTouchMac.didPresentInitialPermissionPrompts"
        static let vendorID = "TouchMonitor.vendorID"
        static let productID = "TouchMonitor.productID"
        static let displayID = "TouchMonitor.displayID"
        static let enableInjection = "TouchMonitor.enableInjection"
    }

    private enum Defaults {
        static let vendorID = "10176"
        static let productID = "2137"
    }

    init() {
        vendorIDText = defaults.string(forKey: Keys.vendorID) ?? Defaults.vendorID
        productIDText = defaults.string(forKey: Keys.productID) ?? Defaults.productID
        displayIDText = defaults.string(forKey: Keys.displayID) ?? ""
        if defaults.object(forKey: Keys.enableInjection) == nil {
            defaults.set(true, forKey: Keys.enableInjection)
        }
        enableInjection = defaults.bool(forKey: Keys.enableInjection)

        appendLog("Anmite Touch Mac initialized.")
        refreshEnvironment()
        requestInitialPermissionsIfNeeded()
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
            requestPermissions: false,
            verboseLogging: false
        )

        let service = TouchMonitorService(config: config) { [weak self] line in
            Task { @MainActor in
                self?.handleServiceLog(line)
            }
        }

        do {
            try service.start()
            self.service = service
            isRunning = true
            statusLine = "Searching for your touch display..."
        } catch {
            appendLog("Unable to start touch input: \(error.localizedDescription)")
            statusLine = "Unable to start touch input"
        }
    }

    func disconnect() {
        service?.stop()
        service = nil
        isRunning = false
        statusLine = "Touch input is turned off"
    }

    func requestPermissions() {
        permissions = TouchMonitorService.currentPermissionStatus(
            requestPrompt: true,
            enableInjection: enableInjection
        )
        appendLog("Opened macOS permission prompts.")
        updatePermissionStatusLine()
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
    }

    var permissionSummary: String {
        [
            permissions.inputMonitoringGranted ? "Input Monitoring enabled" : "Input Monitoring required",
            permissions.accessibilityGranted ? "Accessibility enabled" : "Accessibility required",
            permissions.postEventsGranted ? "Event posting enabled" : "Event posting required",
        ].joined(separator: " | ")
    }

    var menuTitle: String {
        isRunning ? "Anmite Touch Mac" : "Anmite Touch Mac"
    }

    var menuSubtitle: String {
        statusLine
    }

    var settingsFooter: String {
        "Created by Christian Hülsemeyer"
    }

    private func requestInitialPermissionsIfNeeded() {
        guard !defaults.bool(forKey: Keys.didPresentInitialPermissionPrompts) else { return }
        defaults.set(true, forKey: Keys.didPresentInitialPermissionPrompts)
        requestPermissions()
    }

    private func handleServiceLog(_ line: String) {
        appendLog(line)

        if line.contains("selected as active touch device") {
            statusLine = "Touch display connected"
            return
        }

        if line.contains("target touch device disconnected") {
            statusLine = "Touch display disconnected. Searching..."
            return
        }

        if line.contains("grant this app in System Settings") {
            updatePermissionStatusLine()
            return
        }
    }

    private func updatePermissionStatusLine() {
        if !permissions.inputMonitoringGranted || !permissions.accessibilityGranted {
            statusLine = "Finish macOS permissions in System Settings"
        }
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
