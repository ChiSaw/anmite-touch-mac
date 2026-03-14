import ApplicationServices
import Foundation

public final class EventInjector {
    public init() {}

    public func warpCursor(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
    }

    public func moveCursor(to point: CGPoint) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }

    public func leftMouseDown(at point: CGPoint) {
        postMouse(type: .leftMouseDown, point: point, button: .left)
    }

    public func leftMouseDragged(at point: CGPoint) {
        postMouse(type: .leftMouseDragged, point: point, button: .left)
    }

    public func leftMouseUp(at point: CGPoint) {
        postMouse(type: .leftMouseUp, point: point, button: .left)
    }

    public func centerMouseDown(at point: CGPoint) {
        postMouse(type: .otherMouseDown, point: point, button: .center)
    }

    public func centerMouseDragged(at point: CGPoint) {
        postMouse(type: .otherMouseDragged, point: point, button: .center)
    }

    public func centerMouseUp(at point: CGPoint) {
        postMouse(type: .otherMouseUp, point: point, button: .center)
    }

    public func scroll(deltaX: Int32, deltaY: Int32, flags: CGEventFlags = []) {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: deltaY,
            wheel2: deltaX,
            wheel3: 0
        ) else {
            return
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }

    private func postMouse(type: CGEventType, point: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
            return
        }
        event.post(tap: .cghidEventTap)
    }
}
