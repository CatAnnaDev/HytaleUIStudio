import SwiftUI
import HytaleUICore

extension UIColor {
    var swiftUIColor: Color {
        let c = components
        return Color(.sRGB, red: c.red, green: c.green, blue: c.blue, opacity: c.alpha)
    }
}

enum ValueReader {
    static func number(_ value: UIValue?) -> Double? {
        switch value {
        case .number(let n, _): return n
        case .grouping(let inner): return number(inner)
        case .unary(let op, let operand):
            guard let inner = number(operand) else { return nil }
            return op == .negate ? -inner : inner
        case .binary(let op, let lhs, let rhs):
            guard let l = number(lhs), let r = number(rhs) else { return nil }
            switch op {
            case .add: return l + r
            case .subtract: return l - r
            case .multiply: return l * r
            case .divide: return r == 0 ? nil : l / r
            }
        default: return nil
        }
    }

    static func bool(_ value: UIValue?) -> Bool {
        if case .boolean(let flag) = value { return flag }
        return false
    }
}
