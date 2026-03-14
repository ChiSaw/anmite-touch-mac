import ApplicationServices
import CoreGraphics
import Foundation

public struct TouchMonitorConfiguration: Sendable {
    public var listOnly = false
    public var dumpRaw = false
    public var probeVendor = false
    public var activateVendor = false
    public var targetVendorID: Int?
    public var targetProductID: Int?
    public var targetDisplayID: CGDirectDisplayID?
    public var enableInjection = false
    public var requestPermissions = false
    public var verboseLogging = true

    public init(
        listOnly: Bool = false,
        dumpRaw: Bool = false,
        probeVendor: Bool = false,
        activateVendor: Bool = false,
        targetVendorID: Int? = nil,
        targetProductID: Int? = nil,
        targetDisplayID: CGDirectDisplayID? = nil,
        enableInjection: Bool = false,
        requestPermissions: Bool = false,
        verboseLogging: Bool = true
    ) {
        self.listOnly = listOnly
        self.dumpRaw = dumpRaw
        self.probeVendor = probeVendor
        self.activateVendor = activateVendor
        self.targetVendorID = targetVendorID
        self.targetProductID = targetProductID
        self.targetDisplayID = targetDisplayID
        self.enableInjection = enableInjection
        self.requestPermissions = requestPermissions
        self.verboseLogging = verboseLogging
    }
}

public struct TouchMonitorPermissionStatus: Sendable {
    public let inputMonitoringGranted: Bool
    public let accessibilityGranted: Bool
    public let postEventsGranted: Bool
}

private enum AbsoluteInteractionMode: String {
    case pointer
    case pendingPointer
    case drag
    case scroll
}

public final class TouchMonitorService {
    private let config: TouchMonitorConfiguration
    private let logHandler: (String) -> Void
    private let displayMapper = DisplayMapper()
    private let eventInjector = EventInjector()
    private var selectedDisplayID: CGDirectDisplayID?
    private var selectedDeviceID: UInt64?
    private var selectedDeviceRank = Int.min
    private var matchingDeviceIDs: Set<UInt64> = []
    private var matchingDescriptors: [UInt64: HIDDeviceDescriptor] = [:]
    private var lastRawReports: [String: [UInt8]] = [:]
    private var lastProbeSummaries: [String: String] = [:]
    private var vendorActivationStep = 0
    private var lastPrimaryPoint: CGPoint?
    private var isPrimaryDown = false
    private var lastTwoFingerPoint: CGPoint?
    private var absolutePointerState = AbsolutePointerState()
    private var scrollMomentumTimer: Timer?
    private var vendorProbeTimer: Timer?
    private var scrollMomentum = ScrollMomentumState()
    private var started = false
    private let scrollSpeedMultiplier = 1.5
    private let normalizedScrollActivationDistance: CGFloat = 0.003
    private let scrollDominanceRatio: CGFloat = 1.1
    private let dragActivationDistance: CGFloat = 12
    private let tapMaxDistance: CGFloat = 10
    private let tapMaxDuration: TimeInterval = 0.5
    private let scrollMomentumDecay: CGFloat = 0.90
    private let scrollMomentumThreshold: CGFloat = 80
    private let scrollMomentumFrameRate: TimeInterval = 1.0 / 60.0

    private lazy var touchInterpreter = TouchInterpreter { [weak self] event in
        self?.handleTouchEvent(event)
    }

    private lazy var monitor = HIDMonitor(deviceHandler: { [weak self] descriptor in
        self?.handleDevice(descriptor)
    }, valueHandler: { [weak self] sample in
        self?.handleValueSample(sample)
    }, reportHandler: { [weak self] report in
        self?.handleReportSample(report)
    }, shouldOpenDevice: { [weak self] descriptor in
        self?.matchesConfiguredDevice(descriptor) ?? false
    }, openStatusHandler: { [weak self] descriptor, mode, result in
        let resultText = result == kIOReturnSuccess ? "success" : String(result)
        self?.log("open device id=\(descriptor.id) mode=\(mode) result=\(resultText)")
    })

    public init(config: TouchMonitorConfiguration, logHandler: @escaping (String) -> Void = { _ in }) {
        self.config = config
        self.logHandler = logHandler
        self.selectedDisplayID = config.targetDisplayID ?? displayMapper.displays().last?.id
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard !started else { return }
        started = true

        log("Displays:")
        for display in displayMapper.displays() {
            log("  id=\(display.id) bounds=\(display.bounds.debugDescription) name=\(display.name)")
        }

        log("")
        logPermissions(prompt: config.requestPermissions)

        try monitor.start()

        if !monitor.hasLiveAccess {
            log("")
            log("Live HID capture is not permitted in the current launch context.")
            log("Static device discovery still works; active input logging may require a signed app bundle with additional macOS permissions.")
        }

        log("")
        if config.listOnly {
            log("Listing HID devices only. Press Ctrl+C to stop.")
        } else {
            log("Monitoring HID input. Press Ctrl+C to stop.")
            log("Use --vendor-id/--product-id to lock onto the touch device and --inject to enable pointer events.")
        }

        if config.probeVendor {
            scheduleVendorProbe()
        }
    }

    public func stop() {
        guard started else { return }
        started = false
        vendorProbeTimer?.invalidate()
        vendorProbeTimer = nil
        stopScrollMomentum()
        monitor.stop()
    }

    public static func availableDisplays() -> [DisplayTarget] {
        DisplayMapper().displays()
    }

    @discardableResult
    public static func currentPermissionStatus(
        requestPrompt: Bool = false,
        enableInjection: Bool = false
    ) -> TouchMonitorPermissionStatus {
        if requestPrompt {
            let axOptions = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(axOptions)
            _ = CGRequestListenEventAccess()
            if enableInjection {
                _ = CGRequestPostEventAccess()
            }
        }

        return TouchMonitorPermissionStatus(
            inputMonitoringGranted: CGPreflightListenEventAccess(),
            accessibilityGranted: AXIsProcessTrusted(),
            postEventsGranted: CGPreflightPostEventAccess()
        )
    }

    private func logPermissions(prompt: Bool) {
        let status = Self.currentPermissionStatus(requestPrompt: prompt, enableInjection: config.enableInjection)
        log("Permissions:")
        log("  input monitoring / listen events: \(status.inputMonitoringGranted)")
        log("  accessibility / trusted process: \(status.accessibilityGranted)")
        log("  post synthetic events: \(status.postEventsGranted)")
        if !status.inputMonitoringGranted {
            log("  -> grant this app in System Settings > Privacy & Security > Input Monitoring")
        }
        if config.enableInjection && !status.postEventsGranted {
            log("  -> grant this app in System Settings > Privacy & Security > Accessibility")
        }
    }

    private func handleDevice(_ descriptor: HIDDeviceDescriptor) {
        let summary = "device id=\(descriptor.id) vid=0x\(String(descriptor.vendorID, radix: 16)) pid=0x\(String(descriptor.productID, radix: 16)) usagePage=0x\(String(descriptor.primaryUsagePage, radix: 16)) usage=0x\(String(descriptor.primaryUsage, radix: 16)) transport=\(descriptor.transport) product='\(descriptor.product)' manufacturer='\(descriptor.manufacturer)' in=\(descriptor.maxInputReportSize) out=\(descriptor.maxOutputReportSize) feat=\(descriptor.maxFeatureReportSize) touchCandidate=\(descriptor.isTouchCandidate)"
        log(summary)

        if matchesConfiguredDevice(descriptor) {
            matchingDeviceIDs.insert(descriptor.id)
            matchingDescriptors[descriptor.id] = descriptor
            let rank = deviceRank(descriptor)
            if rank > selectedDeviceRank {
                selectedDeviceID = descriptor.id
                selectedDeviceRank = rank
                log("  -> selected as active touch device")
            }
        }
    }

    private func handleValueSample(_ sample: HIDValueSample) {
        if config.listOnly {
            if sample.element.key.usagePage == HIDUsagePage.digitizer.rawValue || sample.element.key.usagePage == HIDUsagePage.genericDesktop.rawValue || sample.element.key.usagePage == HIDUsagePage.button.rawValue {
                logVerbose("[device \(sample.deviceID)] \(sample.element.name)=\(sample.integerValue)")
            }
            return
        }

        let shouldInspect = selectedDeviceID == nil || selectedDeviceID == sample.deviceID
        guard shouldInspect else { return }

        if selectedDeviceID == nil {
            selectedDeviceID = sample.deviceID
        }

        if sample.element.key.usagePage == HIDUsagePage.digitizer.rawValue || sample.element.key.usagePage == HIDUsagePage.genericDesktop.rawValue || sample.element.key.usagePage == HIDUsagePage.button.rawValue {
            logVerbose("[device \(sample.deviceID)] \(sample.element.name)=\(sample.integerValue)")
        }

        if sample.element.key.usagePage == HIDUsagePage.digitizer.rawValue {
            touchInterpreter.ingest(sample)
        }
    }

    private func handleReportSample(_ sample: HIDReportSample) {
        let isMatchingDevice = matchingDeviceIDs.isEmpty || matchingDeviceIDs.contains(sample.deviceID)
        guard isMatchingDevice else { return }

        if config.listOnly {
            log("[device \(sample.deviceID)] report id=\(sample.reportID) bytes=\(hexString(sample.bytes))")
            return
        }

        if config.dumpRaw {
            logChangedRawReportIfNeeded(sample)
        }

        if sample.deviceID == selectedDeviceID && (sample.reportID == 7 || (sample.bytes.first == 0x07 && sample.bytes.count >= 7)) {
            handleAbsolutePointerReport(sample)
        }
    }

    private func handleAbsolutePointerReport(_ sample: HIDReportSample) {
        guard sample.bytes.count >= 7 else {
            log("[device \(sample.deviceID)] short absolute pointer report bytes=\(hexString(sample.bytes))")
            return
        }

        let bytes = sample.bytes
        let buttons = bytes[1]
        let xRaw = Int(UInt16(bytes[2]) | (UInt16(bytes[3]) << 8))
        let yRaw = Int(UInt16(bytes[4]) | (UInt16(bytes[5]) << 8))
        let wheel = Int(Int8(bitPattern: bytes[6]))

        let xNorm = Double(xRaw) / 16383.0
        let yNorm = Double(yRaw) / 9599.0

        logVerbose("[device \(sample.deviceID)] absolute buttons=0x\(String(buttons, radix: 16)) x=\(xRaw) y=\(yRaw) wheel=\(wheel) norm=(\(String(format: "%.4f", xNorm)), \(String(format: "%.4f", yNorm)))")

        guard let displayID = selectedDisplayID else { return }
        guard let point = displayMapper.map(normalizedX: xNorm, normalizedY: yNorm, to: displayID, invertY: false) else {
            return
        }

        let isPressed = (buttons & 0x01) != 0
        if config.enableInjection {
            if wheel != 0 {
                eventInjector.scroll(deltaX: 0, deltaY: Int32(wheel * 20))
            }

            handleAbsoluteInteraction(
                isPressed: isPressed,
                point: point,
                normalizedX: xNorm,
                normalizedY: yNorm
            )
        }

        absolutePointerState.isPressed = isPressed
        absolutePointerState.lastPoint = point
    }

    private func handleAbsoluteInteraction(
        isPressed: Bool,
        point: CGPoint,
        normalizedX: Double,
        normalizedY: Double
    ) {
        if isPressed && !absolutePointerState.isPressed {
            stopScrollMomentum()
        }

        if isPressed && !absolutePointerState.isPressed {
            absolutePointerState.mode = .pendingPointer
            absolutePointerState.lastPoint = point
            absolutePointerState.interactionStartPoint = point
            absolutePointerState.interactionStartNormalized = CGPoint(x: normalizedX, y: normalizedY)
            absolutePointerState.interactionStartTime = Date().timeIntervalSinceReferenceDate
            absolutePointerState.frozenCursorPoint = currentCursorLocation()
            log("mode=\(absolutePointerState.mode.rawValue)")

            if let anchor = absolutePointerState.frozenCursorPoint {
                eventInjector.warpCursor(to: anchor)
                eventInjector.leftMouseUp(at: anchor)
            } else {
                eventInjector.leftMouseUp(at: point)
            }
            return
        }

        if isPressed && absolutePointerState.isPressed {
            let previous = absolutePointerState.lastPoint ?? point
            switch absolutePointerState.mode {
            case .pointer, .pendingPointer:
                if let anchor = absolutePointerState.frozenCursorPoint {
                    eventInjector.warpCursor(to: anchor)
                    eventInjector.leftMouseUp(at: anchor)
                }

                let start = absolutePointerState.interactionStartPoint ?? point
                let dx = point.x - start.x
                let dy = point.y - start.y
                let distance = hypot(dx, dy)
                let startNormalized = absolutePointerState.interactionStartNormalized ?? CGPoint(x: normalizedX, y: normalizedY)
                let normalizedDX = normalizedX - startNormalized.x
                let normalizedDY = normalizedY - startNormalized.y

                if shouldStartScroll(normalizedDX: normalizedDX, normalizedDY: normalizedDY) {
                    absolutePointerState.mode = .scroll
                    log("mode=scroll ndx=\(String(format: "%.4f", normalizedDX)) ndy=\(String(format: "%.4f", normalizedDY))")
                    let anchor = absolutePointerState.frozenCursorPoint ?? currentCursorLocation()
                    absolutePointerState.frozenCursorPoint = anchor
                    eventInjector.warpCursor(to: anchor)
                    eventInjector.leftMouseUp(at: anchor)
                    let deltaX = Int32((point.x - previous.x) * scrollSpeedMultiplier)
                    let deltaY = Int32((point.y - previous.y) * scrollSpeedMultiplier)
                    eventInjector.scroll(deltaX: deltaX, deltaY: deltaY)
                    recordScrollMomentum(deltaX: CGFloat(deltaX), deltaY: CGFloat(deltaY))
                } else if distance >= dragActivationDistance {
                    absolutePointerState.mode = .drag
                    absolutePointerState.frozenCursorPoint = nil
                    eventInjector.warpCursor(to: point)
                    eventInjector.leftMouseDown(at: point)
                    eventInjector.leftMouseDragged(at: point)
                }
            case .drag:
                eventInjector.warpCursor(to: point)
                eventInjector.leftMouseDragged(at: point)
            case .scroll:
                if let anchor = absolutePointerState.frozenCursorPoint {
                    eventInjector.warpCursor(to: anchor)
                    eventInjector.leftMouseUp(at: anchor)
                }
                let deltaX = Int32((point.x - previous.x) * scrollSpeedMultiplier)
                let deltaY = Int32((point.y - previous.y) * scrollSpeedMultiplier)
                eventInjector.scroll(deltaX: deltaX, deltaY: deltaY)
                recordScrollMomentum(deltaX: CGFloat(deltaX), deltaY: CGFloat(deltaY))
            }
            absolutePointerState.lastPoint = point
            return
        }

        if !isPressed && absolutePointerState.isPressed {
            switch absolutePointerState.mode {
            case .pointer, .pendingPointer:
                let start = absolutePointerState.interactionStartPoint ?? point
                let elapsed = Date().timeIntervalSinceReferenceDate - (absolutePointerState.interactionStartTime ?? 0)
                let distance = hypot(point.x - start.x, point.y - start.y)
                absolutePointerState.frozenCursorPoint = nil

                if elapsed <= tapMaxDuration && distance <= tapMaxDistance {
                    eventInjector.warpCursor(to: point)
                    eventInjector.leftMouseDown(at: point)
                    eventInjector.leftMouseUp(at: point)
                }
            case .drag:
                eventInjector.warpCursor(to: point)
                eventInjector.leftMouseUp(at: point)
            case .scroll:
                if let anchor = absolutePointerState.frozenCursorPoint {
                    eventInjector.warpCursor(to: anchor)
                    eventInjector.leftMouseUp(at: anchor)
                }
                absolutePointerState.frozenCursorPoint = nil
                startScrollMomentumIfNeeded()
            }
            absolutePointerState.mode = .pointer
            absolutePointerState.lastPoint = nil
            absolutePointerState.interactionStartPoint = nil
            absolutePointerState.interactionStartNormalized = nil
            absolutePointerState.interactionStartTime = nil
            return
        }

        if absolutePointerState.mode == .pointer {
            eventInjector.warpCursor(to: point)
            eventInjector.moveCursor(to: point)
        } else if absolutePointerState.mode == .pendingPointer {
            if let anchor = absolutePointerState.frozenCursorPoint {
                eventInjector.warpCursor(to: anchor)
                eventInjector.leftMouseUp(at: anchor)
            }
        } else if absolutePointerState.mode == .drag {
            eventInjector.warpCursor(to: point)
        } else if let anchor = absolutePointerState.frozenCursorPoint {
            eventInjector.warpCursor(to: anchor)
        }
        absolutePointerState.lastPoint = point
    }

    private func handleTouchEvent(_ event: TouchEvent) {
        guard selectedDeviceID == event.deviceID else { return }
        guard let displayID = selectedDisplayID else { return }
        guard let point = displayMapper.map(normalizedX: event.normalizedX, normalizedY: event.normalizedY, to: displayID) else {
            return
        }

        switch event.activeContactCount {
        case 1:
            handleSingleFinger(event: event, point: point)
        case 2...:
            handleTwoFinger(event: event, point: point)
        default:
            break
        }
    }

    private func handleSingleFinger(event: TouchEvent, point: CGPoint) {
        logVerbose("touch contact=\(event.contactID) phase=\(event.phase) x=\(String(format: "%.4f", event.normalizedX)) y=\(String(format: "%.4f", event.normalizedY))")

        guard config.enableInjection else { return }

        switch event.phase {
        case .began:
            eventInjector.warpCursor(to: point)
            eventInjector.leftMouseDown(at: point)
            isPrimaryDown = true
            lastPrimaryPoint = point
        case .moved:
            if isPrimaryDown {
                eventInjector.warpCursor(to: point)
                eventInjector.leftMouseDragged(at: point)
            } else {
                eventInjector.warpCursor(to: point)
                eventInjector.moveCursor(to: point)
            }
            lastPrimaryPoint = point
        case .ended:
            eventInjector.warpCursor(to: point)
            eventInjector.leftMouseUp(at: point)
            isPrimaryDown = false
            lastPrimaryPoint = nil
            lastTwoFingerPoint = nil
        }
    }

    private func handleTwoFinger(event: TouchEvent, point: CGPoint) {
        logVerbose("two-finger contact=\(event.contactID) phase=\(event.phase) x=\(String(format: "%.4f", event.normalizedX)) y=\(String(format: "%.4f", event.normalizedY))")

        guard config.enableInjection else { return }

        if let previous = lastTwoFingerPoint, event.phase != .ended {
            let deltaX = Int32((point.x - previous.x) * -1.0)
            let deltaY = Int32(point.y - previous.y)
            eventInjector.scroll(deltaX: deltaX, deltaY: deltaY)
        }

        if event.phase == .ended {
            lastTwoFingerPoint = nil
        } else {
            lastTwoFingerPoint = point
        }

        if isPrimaryDown {
            if let releasePoint = lastPrimaryPoint {
                eventInjector.leftMouseUp(at: releasePoint)
            }
            isPrimaryDown = false
            lastPrimaryPoint = nil
        }
    }

    private func matchesConfiguredDevice(_ descriptor: HIDDeviceDescriptor) -> Bool {
        if let vendorID = config.targetVendorID, vendorID != descriptor.vendorID {
            return false
        }
        if let productID = config.targetProductID, productID != descriptor.productID {
            return false
        }
        if config.targetVendorID != nil || config.targetProductID != nil {
            return true
        }
        return descriptor.isTouchCandidate
    }

    private func deviceRank(_ descriptor: HIDDeviceDescriptor) -> Int {
        if descriptor.transport == "USB"
            && descriptor.primaryUsagePage == HIDUsagePage.genericDesktop.rawValue
            && descriptor.primaryUsage == HIDGenericDesktopUsage.mouse.rawValue {
            return 30
        }
        if descriptor.transport == "USB" && descriptor.isTouchCandidate {
            return 20
        }
        if descriptor.transport == "USB" {
            return 10
        }
        return 0
    }

    private func shouldStartScroll(normalizedDX: CGFloat, normalizedDY: CGFloat) -> Bool {
        let absDX = abs(normalizedDX)
        let absDY = abs(normalizedDY)
        return absDY >= normalizedScrollActivationDistance
            && absDY >= max(absDX * scrollDominanceRatio, 0.0008)
    }

    private func recordScrollMomentum(deltaX: CGFloat, deltaY: CGFloat) {
        let now = Date().timeIntervalSinceReferenceDate
        if let previousTime = scrollMomentum.lastTimestamp {
            let dt = max(now - previousTime, 1.0 / 240.0)
            let vx = deltaX / CGFloat(dt)
            let vy = deltaY / CGFloat(dt)
            let smoothing: CGFloat = 0.35
            scrollMomentum.velocity.dx = scrollMomentum.velocity.dx * (1 - smoothing) + vx * smoothing
            scrollMomentum.velocity.dy = scrollMomentum.velocity.dy * (1 - smoothing) + vy * smoothing
        }
        scrollMomentum.lastTimestamp = now
    }

    private func startScrollMomentumIfNeeded() {
        scrollMomentumTimer?.invalidate()
        scrollMomentumTimer = nil

        let speed = hypot(scrollMomentum.velocity.dx, scrollMomentum.velocity.dy)
        guard speed >= scrollMomentumThreshold else {
            scrollMomentum = ScrollMomentumState()
            return
        }

        scrollMomentumTimer = Timer.scheduledTimer(withTimeInterval: scrollMomentumFrameRate, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            self.scrollMomentum.velocity.dx *= self.scrollMomentumDecay
            self.scrollMomentum.velocity.dy *= self.scrollMomentumDecay

            let frameDeltaX = self.scrollMomentum.velocity.dx * CGFloat(self.scrollMomentumFrameRate)
            let frameDeltaY = self.scrollMomentum.velocity.dy * CGFloat(self.scrollMomentumFrameRate)
            let frameSpeed = hypot(self.scrollMomentum.velocity.dx, self.scrollMomentum.velocity.dy)

            if frameSpeed < self.scrollMomentumThreshold || (abs(frameDeltaX) < 0.5 && abs(frameDeltaY) < 0.5) {
                self.stopScrollMomentum()
                return
            }

            self.eventInjector.scroll(
                deltaX: Int32(frameDeltaX.rounded()),
                deltaY: Int32(frameDeltaY.rounded())
            )
        }
    }

    private func stopScrollMomentum() {
        scrollMomentumTimer?.invalidate()
        scrollMomentumTimer = nil
        scrollMomentum = ScrollMomentumState()
    }

    private func logChangedRawReportIfNeeded(_ sample: HIDReportSample) {
        if sample.reportID == 7 && sample.bytes.count == 7 {
            return
        }

        let key = "\(sample.deviceID):\(sample.reportID)"
        if let previous = lastRawReports[key], previous == sample.bytes {
            return
        }
        lastRawReports[key] = sample.bytes

        log("[raw device \(sample.deviceID)] report id=\(sample.reportID) len=\(sample.bytes.count) bytes=\(hexString(sample.bytes))")
    }

    private func scheduleVendorProbe() {
        let summary = config.activateVendor
            ? "Vendor probe enabled: polling matching 0xff0a interfaces once per second and trying activation patterns."
            : "Vendor probe enabled: polling matching 0xff0a interfaces once per second."
        log(summary)
        vendorProbeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.runVendorProbe()
        }
        runVendorProbe()
    }

    private func runVendorProbe() {
        let vendorDevices = matchingDescriptors.values
            .filter { $0.primaryUsagePage == HIDUsagePage.vendorDefinedTouch.rawValue }

        for descriptor in vendorDevices {
            logProbeResult(
                label: "get input 0x50",
                result: monitor.probeReport(
                    deviceID: descriptor.id,
                    reportType: kIOHIDReportTypeInput,
                    reportID: 0x50,
                    bufferSize: max(descriptor.maxInputReportSize, 64)
                )
            )

            logProbeResult(
                label: "get feature 0x50",
                result: monitor.probeReport(
                    deviceID: descriptor.id,
                    reportType: kIOHIDReportTypeFeature,
                    reportID: 0x50,
                    bufferSize: max(descriptor.maxFeatureReportSize, 64)
                )
            )

            logProbeResult(
                label: "get feature 0x51",
                result: monitor.probeReport(
                    deviceID: descriptor.id,
                    reportType: kIOHIDReportTypeFeature,
                    reportID: 0x51,
                    bufferSize: max(descriptor.maxFeatureReportSize, 64)
                )
            )

            for candidate in vendorActivationCandidates(outputLength: max(descriptor.maxOutputReportSize, 64)) {
                if !config.activateVendor && candidate.name != "zeros" {
                    continue
                }

                if let setResult = monitor.sendReport(
                    deviceID: descriptor.id,
                    reportType: kIOHIDReportTypeOutput,
                    reportID: 0x51,
                    bytes: candidate.bytes
                ) {
                    logProbeSummary(
                        key: "\(descriptor.id):set:\(candidate.name):\(vendorActivationStep)",
                        summary: "[probe device \(descriptor.id)] set output 0x51/\(candidate.name) result=\(formatIOReturn(setResult)) bytes=\(hexString(prefix(candidate.bytes, count: 8)))"
                    )
                }
            }
        }

        if config.activateVendor {
            vendorActivationStep += 1
        }
    }

    private func logProbeResult(label: String, result: HIDProbeResult?) {
        guard let result else { return }
        let summary: String
        if result.resultCode == kIOReturnSuccess {
            summary = "[probe device \(result.deviceID)] \(label) result=\(formatIOReturn(result.resultCode)) len=\(result.bytes.count) bytes=\(hexString(result.bytes))"
        } else {
            summary = "[probe device \(result.deviceID)] \(label) result=\(formatIOReturn(result.resultCode))"
        }
        logProbeSummary(key: "\(result.deviceID):\(label)", summary: summary)
    }

    private func logProbeSummary(key: String, summary: String) {
        if lastProbeSummaries[key] == summary {
            return
        }
        lastProbeSummaries[key] = summary
        log(summary)
    }

    private func vendorActivationCandidates(outputLength: Int) -> [(name: String, bytes: [UInt8])] {
        let step = vendorActivationStep % 6

        func payload(_ byte1: UInt8, _ byte2: UInt8 = 0, _ byte3: UInt8 = 0, _ byte4: UInt8 = 0) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: outputLength)
            if outputLength > 0 { bytes[0] = 0x51 }
            if outputLength > 1 { bytes[1] = byte1 }
            if outputLength > 2 { bytes[2] = byte2 }
            if outputLength > 3 { bytes[3] = byte3 }
            if outputLength > 4 { bytes[4] = byte4 }
            return bytes
        }

        let sequences: [[(name: String, bytes: [UInt8])]] = [
            [("zeros", [UInt8](repeating: 0, count: outputLength))],
            [("report-id-only", payload(0x00))],
            [("enable-01", payload(0x01))],
            [("enable-02", payload(0x02))],
            [("enable-01-01", payload(0x01, 0x01))],
            [("enable-10-01", payload(0x10, 0x01))],
        ]

        return sequences[step]
    }

    private func log(_ message: String) {
        logHandler(message)
    }

    private func logVerbose(_ message: String) {
        guard config.verboseLogging else { return }
        logHandler(message)
    }
}

private struct AbsolutePointerState {
    var isPressed = false
    var lastPoint: CGPoint?
    var interactionStartPoint: CGPoint?
    var interactionStartNormalized: CGPoint?
    var interactionStartTime: TimeInterval?
    var mode: AbsoluteInteractionMode = .pointer
    var frozenCursorPoint: CGPoint?
}

private struct ScrollMomentumState {
    var velocity: CGVector = .zero
    var lastTimestamp: TimeInterval?
}

private func hexString(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

private func currentCursorLocation() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

private func prefix(_ bytes: [UInt8], count: Int) -> [UInt8] {
    Array(bytes.prefix(count))
}

private func formatIOReturn(_ value: IOReturn) -> String {
    if value == kIOReturnSuccess {
        return "success"
    }
    return String(format: "0x%08x", value)
}
