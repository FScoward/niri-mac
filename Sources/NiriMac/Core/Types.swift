import CoreGraphics
import Foundation

typealias WindowID = CGWindowID

struct WindowIDSet {
    private var set: Set<WindowID> = []

    mutating func insert(_ id: WindowID) { set.insert(id) }
    mutating func remove(_ id: WindowID) { set.remove(id) }
    func contains(_ id: WindowID) -> Bool { set.contains(id) }
}

enum Direction {
    case left, right, up, down
}
