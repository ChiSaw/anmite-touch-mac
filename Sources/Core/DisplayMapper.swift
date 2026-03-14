import CoreGraphics
import Foundation

public struct DisplayTarget: Sendable {
    public let id: CGDirectDisplayID
    public let bounds: CGRect
    public let name: String
}

public final class DisplayMapper {
    public init() {}

    public func displays() -> [DisplayTarget] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success else {
            return []
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            return []
        }

        return ids.compactMap { id in
            let bounds = CGDisplayBounds(id)
            let name = "Display \(id)"
            return DisplayTarget(id: id, bounds: bounds, name: name)
        }
    }

    public func map(
        normalizedX: Double,
        normalizedY: Double,
        to displayID: CGDirectDisplayID,
        invertY: Bool = true
    ) -> CGPoint? {
        let bounds = CGDisplayBounds(displayID)
        guard !bounds.isEmpty else { return nil }

        let x = bounds.minX + CGFloat(normalizedX) * bounds.width
        let mappedY = invertY ? (1.0 - normalizedY) : normalizedY
        let y = bounds.minY + CGFloat(mappedY) * bounds.height
        return CGPoint(x: x, y: y)
    }
}
