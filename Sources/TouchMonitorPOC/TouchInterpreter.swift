import Foundation

public final class TouchInterpreter {
    public typealias EventHandler = (TouchEvent) -> Void

    private let eventHandler: EventHandler
    private var devices: [UInt64: DeviceState] = [:]

    public init(eventHandler: @escaping EventHandler) {
        self.eventHandler = eventHandler
    }

    public func ingest(_ sample: HIDValueSample) {
        var deviceState = devices[sample.deviceID, default: DeviceState()]
        let cookie = sample.element.key.cookie

        if sample.element.key.usagePage == HIDUsagePage.digitizer.rawValue {
            switch sample.element.key.usage {
            case HIDDigitizerUsage.transducerIndex.rawValue:
                deviceState.currentTransducerIndex = sample.integerValue
            case HIDDigitizerUsage.contactIdentifier.rawValue:
                deviceState.currentContactIdentifier = sample.integerValue
            case HIDDigitizerUsage.x.rawValue:
                deviceState.currentContact.x = sample.integerValue
                deviceState.xAxis = sample.element
            case HIDDigitizerUsage.y.rawValue:
                deviceState.currentContact.y = sample.integerValue
                deviceState.yAxis = sample.element
            case HIDDigitizerUsage.tipSwitch.rawValue:
                deviceState.currentContact.tipSwitch = sample.integerValue != 0
            case HIDDigitizerUsage.inRange.rawValue:
                deviceState.currentContact.inRange = sample.integerValue != 0
            case HIDDigitizerUsage.touchValid.rawValue:
                deviceState.currentContact.touchValid = sample.integerValue != 0
            case HIDDigitizerUsage.contactCount.rawValue:
                deviceState.contactCount = sample.integerValue
            default:
                break
            }
        }

        deviceState.lastCookie = cookie
        finalizeCurrentContactIfNeeded(sample: sample, state: &deviceState)
        devices[sample.deviceID] = deviceState
    }

    private func finalizeCurrentContactIfNeeded(sample: HIDValueSample, state: inout DeviceState) {
        guard sample.element.key.usagePage == HIDUsagePage.digitizer.rawValue else { return }

        let shouldFlush = sample.element.key.usage == HIDDigitizerUsage.y.rawValue
            || sample.element.key.usage == HIDDigitizerUsage.tipSwitch.rawValue
            || sample.element.key.usage == HIDDigitizerUsage.contactCount.rawValue

        guard shouldFlush else { return }

        let contactID = resolvedContactID(state: state)
        var contact = state.contacts[contactID, default: ContactState()]

        if let x = state.currentContact.x {
            contact.x = x
        }
        if let y = state.currentContact.y {
            contact.y = y
        }
        contact.tipSwitch = state.currentContact.tipSwitch ?? contact.tipSwitch
        contact.inRange = state.currentContact.inRange ?? contact.inRange
        contact.touchValid = state.currentContact.touchValid ?? contact.touchValid

        let wasTouching = contact.wasReportedTouching
        let isTouching = contact.isTouching
        state.contacts[contactID] = contact

        if let normalized = normalize(contact: contact, state: state) {
            let phase: TouchPhase?
            if !wasTouching && isTouching {
                phase = .began
            } else if wasTouching && isTouching {
                phase = .moved
            } else if wasTouching && !isTouching {
                phase = .ended
            } else {
                phase = nil
            }

            if let phase {
                eventHandler(
                    TouchEvent(
                        deviceID: sample.deviceID,
                        contactID: contactID,
                        phase: phase,
                        normalizedX: normalized.x,
                        normalizedY: normalized.y,
                        activeContactCount: state.activeContactCount
                    )
                )
            }
        }

        state.contacts[contactID]?.wasReportedTouching = isTouching
        state.currentContact = PartialContactState()
    }

    private func resolvedContactID(state: DeviceState) -> Int {
        if let contactIdentifier = state.currentContactIdentifier {
            return contactIdentifier
        }
        if let transducerIndex = state.currentTransducerIndex {
            return transducerIndex
        }
        return 0
    }

    private func normalize(contact: ContactState, state: DeviceState) -> (x: Double, y: Double)? {
        guard
            let x = contact.x,
            let y = contact.y,
            let xAxis = state.xAxis,
            let yAxis = state.yAxis
        else {
            return nil
        }

        let xNorm = normalize(value: x, min: xAxis.logicalMin, max: xAxis.logicalMax)
        let yNorm = normalize(value: y, min: yAxis.logicalMin, max: yAxis.logicalMax)
        return (xNorm, yNorm)
    }

    private func normalize(value: Int, min: Int, max: Int) -> Double {
        guard max > min else { return 0 }
        let clamped = Swift.max(min, Swift.min(max, value))
        return Double(clamped - min) / Double(max - min)
    }
}

private struct DeviceState {
    var contacts: [Int: ContactState] = [:]
    var currentContact = PartialContactState()
    var currentContactIdentifier: Int?
    var currentTransducerIndex: Int?
    var contactCount = 0
    var lastCookie = 0
    var xAxis: HIDElementInfo?
    var yAxis: HIDElementInfo?

    var activeContactCount: Int {
        let count = contacts.values.filter(\.isTouching).count
        return max(count, contactCount)
    }
}

private struct PartialContactState {
    var x: Int?
    var y: Int?
    var tipSwitch: Bool?
    var inRange: Bool?
    var touchValid: Bool?
}

private struct ContactState {
    var x: Int?
    var y: Int?
    var tipSwitch = false
    var inRange = false
    var touchValid = false
    var wasReportedTouching = false

    var isTouching: Bool {
        tipSwitch || touchValid || inRange
    }
}
