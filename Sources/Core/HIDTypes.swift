import Foundation
import IOKit.hid

public enum HIDUsagePage: Int {
    case genericDesktop = 0x01
    case digitizer = 0x0D
    case button = 0x09
    case vendorDefinedTouch = 0xFF0A
}

public enum HIDGenericDesktopUsage: Int {
    case mouse = 0x02
    case pointer = 0x01
}

public enum HIDDigitizerUsage: Int {
    case digitizer = 0x01
    case pen = 0x02
    case lightPen = 0x03
    case touchScreen = 0x04
    case touchPad = 0x05
    case stylus = 0x20
    case finger = 0x22
    case tipSwitch = 0x42
    case inRange = 0x32
    case touchValid = 0x47
    case contactIdentifier = 0x51
    case contactCount = 0x54
    case contactCountMaximum = 0x55
    case scanTime = 0x56
    case transducerIndex = 0x38
    case x = 0x30
    case y = 0x31
    case width = 0x48
    case height = 0x49
}

public struct HIDElementKey: Hashable, Sendable {
    public let cookie: Int
    public let usagePage: Int
    public let usage: Int

    public init(cookie: Int, usagePage: Int, usage: Int) {
        self.cookie = cookie
        self.usagePage = usagePage
        self.usage = usage
    }
}

public struct HIDElementInfo: Sendable {
    public let key: HIDElementKey
    public let logicalMin: Int
    public let logicalMax: Int
    public let reportID: Int
    public let name: String
}

public struct HIDDeviceDescriptor: Sendable {
    public let id: UInt64
    public let product: String
    public let manufacturer: String
    public let vendorID: Int
    public let productID: Int
    public let primaryUsagePage: Int
    public let primaryUsage: Int
    public let transport: String
    public let builtIn: Bool
    public let maxInputReportSize: Int
    public let maxOutputReportSize: Int
    public let maxFeatureReportSize: Int

    public var isTouchCandidate: Bool {
        primaryUsagePage == HIDUsagePage.digitizer.rawValue
            || primaryUsage == HIDDigitizerUsage.touchScreen.rawValue
            || primaryUsage == HIDDigitizerUsage.touchPad.rawValue
    }
}

public struct HIDValueSample: Sendable {
    public let deviceID: UInt64
    public let timestamp: UInt64
    public let element: HIDElementInfo
    public let integerValue: Int
}

public struct HIDReportSample: Sendable {
    public let deviceID: UInt64
    public let reportID: UInt32
    public let timestamp: UInt64
    public let bytes: [UInt8]
}

public struct HIDProbeResult: Sendable {
    public let deviceID: UInt64
    public let reportType: IOHIDReportType
    public let reportID: Int
    public let resultCode: IOReturn
    public let bytes: [UInt8]
}

public struct ContactSnapshot: Sendable {
    public let id: Int
    public let xRaw: Int?
    public let yRaw: Int?
    public let isTouching: Bool
    public let isInRange: Bool
}

public enum TouchPhase: Sendable {
    case began
    case moved
    case ended
}

public struct TouchEvent: Sendable {
    public let deviceID: UInt64
    public let contactID: Int
    public let phase: TouchPhase
    public let normalizedX: Double
    public let normalizedY: Double
    public let activeContactCount: Int
}

func hidString(_ value: Any?) -> String {
    guard let value else { return "" }
    if CFGetTypeID(value as CFTypeRef) == CFStringGetTypeID() {
        return value as? String ?? ""
    }
    return ""
}

func hidInt(_ value: Any?) -> Int {
    guard let value else { return 0 }
    if CFGetTypeID(value as CFTypeRef) == CFNumberGetTypeID() {
        var number = 0
        CFNumberGetValue((value as! CFNumber), .intType, &number)
        return number
    }
    return 0
}
