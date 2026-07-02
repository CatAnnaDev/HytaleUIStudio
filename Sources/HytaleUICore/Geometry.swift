import Foundation

public struct UISize: Sendable, Equatable {
    public var width: Double
    public var height: Double
    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
    public static let zero = UISize(width: 0, height: 0)
}

public struct UIPoint: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
    public static let zero = UIPoint(x: 0, y: 0)
}

public struct UIRect: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
    public static let zero = UIRect(x: 0, y: 0, width: 0, height: 0)
    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public struct UIEdgeInsets: Sendable, Equatable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double
    public init(left: Double = 0, top: Double = 0, right: Double = 0, bottom: Double = 0) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }
    public static let zero = UIEdgeInsets()
    public var horizontal: Double { left + right }
    public var vertical: Double { top + bottom }
}

public enum UILayoutMode: String, Sendable, CaseIterable {
    case none
    case top = "Top"
    case left = "Left"
    case right = "Right"
    case middle = "Middle"
    case center = "Center"
    case full = "Full"
    case centerMiddle = "CenterMiddle"
    case middleCenter = "MiddleCenter"
    case topScrolling = "TopScrolling"
    case bottomScrolling = "BottomScrolling"
    case leftScrolling = "LeftScrolling"
    case leftCenterWrap = "LeftCenterWrap"

    public init(name: String) {
        self = UILayoutMode(rawValue: name) ?? .none
    }

    public var isVerticalStack: Bool {
        switch self {
        case .top, .topScrolling, .bottomScrolling, .middle, .center, .centerMiddle, .middleCenter, .leftCenterWrap:
            return true
        default:
            return false
        }
    }

    public var isHorizontalStack: Bool {
        switch self {
        case .left, .leftScrolling, .right:
            return true
        default:
            return false
        }
    }

    public var isScrolling: Bool {
        self == .topScrolling || self == .bottomScrolling || self == .leftScrolling
    }
}

public enum UIAxisAlignment: String, Sendable {
    case start = "Start"
    case center = "Center"
    case end = "End"
}
