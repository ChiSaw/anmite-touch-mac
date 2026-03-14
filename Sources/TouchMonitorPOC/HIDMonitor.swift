import Foundation
import IOKit.hid

public final class HIDMonitor {
    public typealias DeviceHandler = (HIDDeviceDescriptor) -> Void
    public typealias ValueHandler = (HIDValueSample) -> Void
    public typealias ReportHandler = (HIDReportSample) -> Void
    public typealias OpenPredicate = (HIDDeviceDescriptor) -> Bool

    private let manager: IOHIDManager
    private let deviceHandler: DeviceHandler
    private let valueHandler: ValueHandler
    private let reportHandler: ReportHandler
    private let shouldOpenDevice: OpenPredicate
    private let openStatusHandler: ((HIDDeviceDescriptor, String, IOReturn) -> Void)?

    private var devicesByID: [UInt64: IOHIDDevice] = [:]
    private var elementInfoByDevice: [UInt64: [Int: HIDElementInfo]] = [:]
    private var knownDevices: Set<UInt64> = []
    private var openedDeviceIDs: Set<UInt64> = []
    private var reportBuffers: [UInt64: UnsafeMutablePointer<UInt8>] = [:]
    public private(set) var hasLiveAccess = false

    public init(
        deviceHandler: @escaping DeviceHandler,
        valueHandler: @escaping ValueHandler,
        reportHandler: @escaping ReportHandler = { _ in },
        shouldOpenDevice: @escaping OpenPredicate = { $0.isTouchCandidate },
        openStatusHandler: ((HIDDeviceDescriptor, String, IOReturn) -> Void)? = nil
    ) {
        self.manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.deviceHandler = deviceHandler
        self.valueHandler = valueHandler
        self.reportHandler = reportHandler
        self.shouldOpenDevice = shouldOpenDevice
        self.openStatusHandler = openStatusHandler
    }

    deinit {
        for (_, buffer) in reportBuffers {
            buffer.deallocate()
        }
        stop()
    }

    public func start() throws {
        let matching: [[String: Int]] = [
            [
                kIOHIDDeviceUsagePageKey: HIDUsagePage.digitizer.rawValue,
                kIOHIDDeviceUsageKey: HIDDigitizerUsage.touchScreen.rawValue,
            ],
            [
                kIOHIDDeviceUsagePageKey: HIDUsagePage.digitizer.rawValue,
                kIOHIDDeviceUsageKey: HIDDigitizerUsage.touchPad.rawValue,
            ],
            [
                kIOHIDDeviceUsagePageKey: HIDUsagePage.genericDesktop.rawValue,
                kIOHIDDeviceUsageKey: HIDGenericDesktopUsage.mouse.rawValue,
            ],
            [
                kIOHIDDeviceUsagePageKey: HIDUsagePage.genericDesktop.rawValue,
                kIOHIDDeviceUsageKey: HIDGenericDesktopUsage.pointer.rawValue,
            ],
            [
                kIOHIDDeviceUsagePageKey: HIDUsagePage.vendorDefinedTouch.rawValue,
                kIOHIDDeviceUsageKey: 0xFF,
            ],
        ]

        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, _, _, device in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.handleDevice(device)
        }, context)
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.handleValue(value)
        }, context)

        let managerOpenResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        let managerResultText = managerOpenResult == kIOReturnSuccess ? "success" : String(managerOpenResult)
        print("open manager mode=shared result=\(managerResultText)")
        guard managerOpenResult == kIOReturnSuccess else {
            throw HIDMonitorError.openFailed(code: managerOpenResult)
        }

        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices {
                handleDevice(device)
            }
        }
    }

    public func stop() {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    private func handleDevice(_ device: IOHIDDevice) {
        let descriptor = makeDescriptor(for: device)
        guard !knownDevices.contains(descriptor.id) else { return }
        knownDevices.insert(descriptor.id)
        devicesByID[descriptor.id] = device
        elementInfoByDevice[descriptor.id] = buildElementMap(for: device)
        deviceHandler(descriptor)
        if shouldOpenDevice(descriptor) {
            attemptOpen(device, descriptor: descriptor)
        }
    }

    private func handleValue(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let device = IOHIDElementGetDevice(element)
        let descriptor = makeDescriptor(for: device)
        if !knownDevices.contains(descriptor.id) {
            handleDevice(device)
        }

        let cookie = Int(IOHIDElementGetCookie(element))
        guard let elementInfo = elementInfoByDevice[descriptor.id]?[cookie] else {
            return
        }

        let sample = HIDValueSample(
            deviceID: descriptor.id,
            timestamp: IOHIDValueGetTimeStamp(value),
            element: elementInfo,
            integerValue: IOHIDValueGetIntegerValue(value)
        )
        valueHandler(sample)
    }

    private func buildElementMap(for device: IOHIDDevice) -> [Int: HIDElementInfo] {
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] else {
            return [:]
        }

        var map: [Int: HIDElementInfo] = [:]
        for element in elements {
            let cookie = Int(IOHIDElementGetCookie(element))
            let usagePage = Int(IOHIDElementGetUsagePage(element))
            let usage = Int(IOHIDElementGetUsage(element))
            let info = HIDElementInfo(
                key: HIDElementKey(cookie: cookie, usagePage: usagePage, usage: usage),
                logicalMin: Int(IOHIDElementGetLogicalMin(element)),
                logicalMax: Int(IOHIDElementGetLogicalMax(element)),
                reportID: Int(IOHIDElementGetReportID(element)),
                name: describeElement(usagePage: usagePage, usage: usage)
            )
            map[cookie] = info
        }
        return map
    }

    private func makeDescriptor(for device: IOHIDDevice) -> HIDDeviceDescriptor {
        let rawID = UInt(bitPattern: Unmanaged.passUnretained(device).toOpaque())
        return HIDDeviceDescriptor(
            id: UInt64(rawID),
            product: hidString(IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString)),
            manufacturer: hidString(IOHIDDeviceGetProperty(device, kIOHIDManufacturerKey as CFString)),
            vendorID: hidInt(IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString)),
            productID: hidInt(IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString)),
            primaryUsagePage: hidInt(IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString)),
            primaryUsage: hidInt(IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString)),
            transport: hidString(IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString)),
            builtIn: hidInt(IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString)) != 0,
            maxInputReportSize: hidInt(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString)),
            maxOutputReportSize: hidInt(IOHIDDeviceGetProperty(device, kIOHIDMaxOutputReportSizeKey as CFString)),
            maxFeatureReportSize: hidInt(IOHIDDeviceGetProperty(device, kIOHIDMaxFeatureReportSizeKey as CFString))
        )
    }

    private func attemptOpen(_ device: IOHIDDevice, descriptor: HIDDeviceDescriptor) {
        guard !openedDeviceIDs.contains(descriptor.id) else { return }
        openedDeviceIDs.insert(descriptor.id)

        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceRegisterInputValueCallback(device, { context, _, _, value in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            monitor.handleValue(value)
        }, context)
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        let reportBufferSize = max(hidInt(IOHIDDeviceGetProperty(device, kIOHIDMaxInputReportSizeKey as CFString)), 64)
        let reportBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: reportBufferSize)
        reportBuffer.initialize(repeating: 0, count: reportBufferSize)
        reportBuffers[descriptor.id] = reportBuffer
        IOHIDDeviceRegisterInputReportCallback(device, reportBuffer, reportBufferSize, { context, _, sender, reportType, reportID, report, reportLength in
            let monitor = Unmanaged<HIDMonitor>.fromOpaque(context!).takeUnretainedValue()
            let device = unsafeBitCast(sender, to: IOHIDDevice.self)
            monitor.handleReport(
                device: device,
                reportType: reportType,
                reportID: reportID,
                report: report,
                reportLength: reportLength
            )
        }, context)

        let openAttempts: [(String, IOOptionBits)] = [
            ("seized", IOOptionBits(kIOHIDOptionsTypeSeizeDevice)),
            ("shared", IOOptionBits(kIOHIDOptionsTypeNone)),
        ]

        var finalResult = kIOReturnError
        for (label, options) in openAttempts {
            let result = IOHIDDeviceOpen(device, options)
            openStatusHandler?(descriptor, label, result)
            if result == kIOReturnSuccess {
                finalResult = result
                break
            }
        }

        if finalResult == kIOReturnSuccess {
            hasLiveAccess = true
        }
    }

    private func handleReport(
        device: IOHIDDevice,
        reportType: IOHIDReportType,
        reportID: UInt32,
        report: UnsafeMutablePointer<UInt8>?,
        reportLength: CFIndex
    ) {
        guard reportType == kIOHIDReportTypeInput else { return }
        guard let report, reportLength > 0 else { return }

        let descriptor = makeDescriptor(for: device)
        let bytes = Array(UnsafeBufferPointer(start: report, count: reportLength))
        reportHandler(
            HIDReportSample(
                deviceID: descriptor.id,
                reportID: reportID,
                timestamp: DispatchTime.now().uptimeNanoseconds,
                bytes: bytes
            )
        )
    }

    public func probeReport(deviceID: UInt64, reportType: IOHIDReportType, reportID: Int, bufferSize: Int? = nil) -> HIDProbeResult? {
        guard let device = devicesByID[deviceID] else { return nil }
        let descriptor = makeDescriptor(for: device)

        let size: Int
        switch reportType {
        case kIOHIDReportTypeInput:
            size = max(bufferSize ?? descriptor.maxInputReportSize, 64)
        case kIOHIDReportTypeOutput:
            size = max(bufferSize ?? descriptor.maxOutputReportSize, 64)
        case kIOHIDReportTypeFeature:
            size = max(bufferSize ?? descriptor.maxFeatureReportSize, 64)
        default:
            size = max(bufferSize ?? descriptor.maxInputReportSize, 64)
        }

        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        buffer.initialize(repeating: 0, count: size)
        defer { buffer.deallocate() }

        var reportLength = CFIndex(size)
        let result = IOHIDDeviceGetReport(device, reportType, reportID, buffer, &reportLength)
        let bytes = result == kIOReturnSuccess ? Array(UnsafeBufferPointer(start: buffer, count: reportLength)) : []

        return HIDProbeResult(
            deviceID: deviceID,
            reportType: reportType,
            reportID: reportID,
            resultCode: result,
            bytes: bytes
        )
    }

    public func sendReport(deviceID: UInt64, reportType: IOHIDReportType, reportID: Int, bytes: [UInt8]) -> IOReturn? {
        guard let device = devicesByID[deviceID] else { return nil }
        return bytes.withUnsafeBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else { return kIOReturnBadArgument }
            return IOHIDDeviceSetReport(device, reportType, reportID, baseAddress, buffer.count)
        }
    }
}

public enum HIDMonitorError: Error, LocalizedError {
    case openFailed(code: IOReturn)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let code):
            return "Failed to open IOHIDManager: \(code)"
        }
    }
}

private func describeElement(usagePage: Int, usage: Int) -> String {
    switch (usagePage, usage) {
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.touchScreen.rawValue):
        return "digitizer.touchScreen"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.touchPad.rawValue):
        return "digitizer.touchPad"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.finger.rawValue):
        return "digitizer.finger"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.x.rawValue):
        return "digitizer.x"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.y.rawValue):
        return "digitizer.y"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.tipSwitch.rawValue):
        return "digitizer.tipSwitch"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.inRange.rawValue):
        return "digitizer.inRange"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.touchValid.rawValue):
        return "digitizer.touchValid"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.contactIdentifier.rawValue):
        return "digitizer.contactIdentifier"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.contactCount.rawValue):
        return "digitizer.contactCount"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.contactCountMaximum.rawValue):
        return "digitizer.contactCountMaximum"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.scanTime.rawValue):
        return "digitizer.scanTime"
    case (HIDUsagePage.digitizer.rawValue, HIDDigitizerUsage.transducerIndex.rawValue):
        return "digitizer.transducerIndex"
    case (HIDUsagePage.vendorDefinedTouch.rawValue, 0xFF):
        return "vendor.touchBlob"
    default:
        return String(format: "usagePage=0x%02X usage=0x%02X", usagePage, usage)
    }
}
