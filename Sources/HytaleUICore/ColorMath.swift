import Foundation

public extension UIColor {
    var components: (red: Double, green: Double, blue: Double, alpha: Double) {
        var hex = self.hex
        var embeddedAlpha: Double? = nil
        func channel(_ characters: [Character]) -> Double {
            Double(Int(String(characters), radix: 16) ?? 0) / 255.0
        }
        let chars = Array(hex)
        switch hex.count {
        case 3:
            return (channel([chars[0], chars[0]]), channel([chars[1], chars[1]]), channel([chars[2], chars[2]]), alpha ?? 1)
        case 4:
            return (channel([chars[0], chars[0]]), channel([chars[1], chars[1]]), channel([chars[2], chars[2]]), alpha ?? channel([chars[3], chars[3]]))
        case 8:
            embeddedAlpha = channel([chars[6], chars[7]])
            hex = String(hex.prefix(6))
        default:
            break
        }
        let padded = Array((hex.count >= 6 ? String(hex.prefix(6)) : hex.padding(toLength: 6, withPad: "0", startingAt: 0)))
        return (channel([padded[0], padded[1]]), channel([padded[2], padded[3]]), channel([padded[4], padded[5]]), alpha ?? embeddedAlpha ?? 1)
    }
}
