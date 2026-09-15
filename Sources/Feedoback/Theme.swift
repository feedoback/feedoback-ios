import Foundation

#if canImport(UIKit)
import UIKit

/// The accent is the owner's, and can change without an app release.
/// Everything else is derived from it the way the web widget already derives
/// it, so the two cannot drift into different-looking products.
enum FeedobackPalette {
    static func accent(_ hex: String) -> UIColor {
        color(from: hex) ?? UIColor(red: 0.06, green: 0.43, blue: 0.34, alpha: 1)
    }

    /// White or ink, whichever can actually be read on the accent. Computed
    /// rather than picked once, so a pale brand colour does not ship white
    /// text on a pale button.
    static func onAccent(_ accent: UIColor) -> UIColor {
        luminance(of: accent) > 0.5 ? UIColor(white: 0.07, alpha: 1) : .white
    }

    static func color(from hex: String) -> UIColor? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((number & 0xFF0000) >> 16) / 255,
            green: CGFloat((number & 0x00FF00) >> 8) / 255,
            blue: CGFloat(number & 0x0000FF) / 255,
            alpha: 1)
    }

    /// Relative luminance, the same formula the contrast rules use.
    static func luminance(of color: UIColor) -> CGFloat {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func channel(_ value: CGFloat) -> CGFloat {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    static func contrast(_ a: UIColor, _ b: UIColor) -> CGFloat {
        let first = luminance(of: a)
        let second = luminance(of: b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }
}

extension FeedobackTheme {
    /// What UIKit should do with it. `.system` leaves the device in charge,
    /// which is what almost every app wants.
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}
#endif
