import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class MenuBarAppModel: ObservableObject {
    enum PermissionGuideStep: Equatable {
        case welcome
        case inputMonitoring
        case accessibility
        case eventPosting
        case complete
    }

    @Published var vendorIDText: String
    @Published var productIDText: String
    @Published var displayIDText: String
    @Published var enableInjection: Bool
    @Published var isRunning = false
    @Published var statusLine = "Touch display not connected"
    @Published var logs = ""
    @Published var permissions = TouchMonitorService.currentPermissionStatus()
    @Published var displays = TouchMonitorService.availableDisplays()
    @Published var isShowingPermissionGuide = false
    @Published var permissionGuideStep: PermissionGuideStep = .welcome
    @Published var settingsOpenRequestID = 0

    private var service: TouchMonitorService?
    private var permissionRefreshTimer: Timer?
    private var appActivationObserver: NSObjectProtocol?
    private var runtimeStatusLine = "Touch display not connected"
    private var permissionGuideStarted = false
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let didCompletePermissionGuide = "AnmiteTouchMac.didCompletePermissionGuide"
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
        vendorIDText = Self.sanitizedDefaultString(defaults.string(forKey: Keys.vendorID), fallback: Defaults.vendorID)
        productIDText = Self.sanitizedDefaultString(defaults.string(forKey: Keys.productID), fallback: Defaults.productID)
        displayIDText = Self.sanitizedDefaultString(defaults.string(forKey: Keys.displayID), fallback: "")
        if defaults.object(forKey: Keys.enableInjection) == nil {
            defaults.set(true, forKey: Keys.enableInjection)
        }
        enableInjection = defaults.bool(forKey: Keys.enableInjection)
        persistSettings()

        appendLog("Anmite Touch Mac initialized.")
        appActivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshEnvironment()
            }
        }
        refreshEnvironment()
        requestInitialPermissionsIfNeeded()
        connect()
    }

    deinit {
        permissionRefreshTimer?.invalidate()
        if let appActivationObserver {
            NotificationCenter.default.removeObserver(appActivationObserver)
        }
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
            setRuntimeStatus("Searching for your touch display...")
        } catch {
            appendLog("Unable to start touch input: \(error.localizedDescription)")
            setRuntimeStatus("Unable to start touch input")
        }
    }

    func disconnect() {
        service?.stop()
        service = nil
        isRunning = false
        setRuntimeStatus("Touch input is turned off")
    }

    func requestPermissions() {
        reviewPermissions()
    }

    func refreshEnvironment() {
        displays = TouchMonitorService.availableDisplays()
        permissions = TouchMonitorService.currentPermissionStatus(enableInjection: enableInjection)
        updatePermissionGuideIfNeeded()
        syncStatusLine()
    }

    func openSettingsWindow() {
        settingsOpenRequestID &+= 1
    }

    func reviewPermissions() {
        refreshEnvironment()
        if allRequiredPermissionsGranted {
            isShowingPermissionGuide = false
        } else {
            isShowingPermissionGuide = true
            permissionGuideStarted = true
            permissionGuideStep = nextRequiredPermissionStep()
        }
        openSettingsWindow()
    }

    func performPermissionGuidePrimaryAction() {
        switch permissionGuideStep {
        case .welcome:
            permissionGuideStarted = true
            permissionGuideStep = nextRequiredPermissionStep()
            openSettingsWindow()
        case .inputMonitoring:
            _ = TouchMonitorService.requestInputMonitoringPermission()
            openPrivacyPane(anchor: "Privacy_ListenEvent")
            appendLog("Requested Input Monitoring permission.")
            startPermissionRefreshPolling()
        case .accessibility:
            _ = TouchMonitorService.requestAccessibilityPermission()
            openPrivacyPane(anchor: "Privacy_Accessibility")
            appendLog("Requested Accessibility permission.")
            startPermissionRefreshPolling()
        case .eventPosting:
            _ = TouchMonitorService.requestPostEventPermission()
            openPrivacyPane(anchor: "Privacy_Accessibility")
            appendLog("Requested synthetic event permission.")
            startPermissionRefreshPolling()
        case .complete:
            finishPermissionGuide()
        }
    }

    func refreshPermissionGuideStatus() {
        refreshEnvironment()
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
            accessibilityControlSummary,
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

    var permissionGuideTitle: String {
        switch permissionGuideStep {
        case .welcome:
            return "Welcome to Anmite Touch Mac"
        case .inputMonitoring:
            return "Allow Input Monitoring"
        case .accessibility:
            return "Allow Accessibility"
        case .eventPosting:
            return "Finish Accessibility Setup"
        case .complete:
            return "All Permissions Ready"
        }
    }

    var permissionGuideMessage: String {
        switch permissionGuideStep {
        case .welcome:
            return "Anmite Touch Mac needs a few macOS permissions to read touch input and translate it into pointer, drag, and momentum scrolling. This guide will walk you through them one at a time."
        case .inputMonitoring:
            return "Grant Input Monitoring so the app can listen to the touchscreen's HID input stream. After enabling it in System Settings, return to the app and this guide will continue automatically."
        case .accessibility:
            return "Grant Accessibility so the app can move the pointer, click, drag, and control scrolling on your Mac. Return to the app after enabling access."
        case .eventPosting:
            return "macOS uses the same Accessibility permission for synthetic pointer and scroll control. If Anmite Touch Mac is already enabled there, refresh this guide or relaunch the app so the permission becomes active."
        case .complete:
            return "Everything required for touch input is now enabled. You can continue to the main settings and start using the monitor."
        }
    }

    var permissionGuidePrimaryButtonTitle: String {
        switch permissionGuideStep {
        case .welcome:
            return "Start Setup"
        case .inputMonitoring:
            return "Request Input Monitoring"
        case .accessibility:
            return "Request Accessibility"
        case .eventPosting:
            return "Open Accessibility Again"
        case .complete:
            return "Continue"
        }
    }

    var permissionGuideStepLabel: String {
        "Step \(permissionGuideStepIndex) of \(permissionGuideTotalSteps)"
    }

    private func requestInitialPermissionsIfNeeded() {
        guard !defaults.bool(forKey: Keys.didCompletePermissionGuide) else { return }
        refreshEnvironment()
        guard !allRequiredPermissionsGranted else {
            defaults.set(true, forKey: Keys.didCompletePermissionGuide)
            return
        }

        isShowingPermissionGuide = true
        permissionGuideStarted = false
        permissionGuideStep = .welcome

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            Task { @MainActor in
                self?.openSettingsWindow()
            }
        }
    }

    private func handleServiceLog(_ line: String) {
        appendLog(line)

        if line.contains("selected as active touch device") {
            setRuntimeStatus("Touch display connected")
            return
        }

        if line.contains("target touch device disconnected") {
            setRuntimeStatus("Touch display disconnected. Searching...")
            return
        }

        if line.contains("grant this app in System Settings") {
            syncStatusLine()
            return
        }
    }

    private func setRuntimeStatus(_ line: String) {
        runtimeStatusLine = line
        syncStatusLine()
    }

    private func syncStatusLine() {
        if !allRequiredPermissionsGranted {
            statusLine = "Finish macOS permissions in System Settings"
        } else {
            statusLine = runtimeStatusLine
        }
    }

    private var allRequiredPermissionsGranted: Bool {
        permissions.inputMonitoringGranted &&
        permissions.accessibilityGranted &&
        (!enableInjection || permissions.postEventsGranted)
    }

    private var permissionGuideTotalSteps: Int {
        let requiredPermissionSteps = 2 + (enableInjection ? 1 : 0)
        return requiredPermissionSteps + 2
    }

    private var permissionGuideStepIndex: Int {
        switch permissionGuideStep {
        case .welcome:
            return 1
        case .inputMonitoring:
            return 2
        case .accessibility:
            return 3
        case .eventPosting:
            return enableInjection ? 4 : 3
        case .complete:
            return permissionGuideTotalSteps
        }
    }

    private func nextRequiredPermissionStep() -> PermissionGuideStep {
        if !permissions.inputMonitoringGranted {
            return .inputMonitoring
        }
        if !permissions.accessibilityGranted {
            return .accessibility
        }
        if enableInjection && !permissions.postEventsGranted {
            return .eventPosting
        }
        return .complete
    }

    private func updatePermissionGuideIfNeeded() {
        guard isShowingPermissionGuide else { return }

        if !permissionGuideStarted {
            if allRequiredPermissionsGranted {
                permissionGuideStep = .complete
            }
            return
        }

        let nextStep = nextRequiredPermissionStep()
        if permissionGuideStep != nextStep {
            permissionGuideStep = nextStep
        }
    }

    private func finishPermissionGuide() {
        defaults.set(true, forKey: Keys.didCompletePermissionGuide)
        permissionGuideStarted = false
        isShowingPermissionGuide = false
        syncStatusLine()
    }

    private var accessibilityControlSummary: String {
        if permissions.accessibilityGranted && permissions.postEventsGranted {
            return "Accessibility and touch control enabled"
        }
        if permissions.accessibilityGranted && !permissions.postEventsGranted {
            return "Accessibility enabled, app control still pending"
        }
        return "Accessibility required"
    }

    private func openPrivacyPane(anchor: String) {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)"),
            URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)"),
        ].compactMap { $0 }

        for url in urls where NSWorkspace.shared.open(url) {
            return
        }

        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/System Settings.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    private func startPermissionRefreshPolling() {
        permissionRefreshTimer?.invalidate()

        var remainingPolls = 15
        permissionRefreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self else {
                    timer.invalidate()
                    return
                }

                self.refreshEnvironment()
                remainingPolls -= 1

                let permissionsSatisfied = self.allRequiredPermissionsGranted
                if permissionsSatisfied || remainingPolls <= 0 {
                    timer.invalidate()
                    self.permissionRefreshTimer = nil
                }
            }
        }
    }

    private static func sanitizedDefaultString(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
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
