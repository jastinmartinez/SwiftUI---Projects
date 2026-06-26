import SwiftUI

// MARK: - Hex

extension Color {
    /// Initialises a Color from a six-character hex string, e.g. "#FF3B30".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(hex, radix: 16) ?? 0
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Filer Palette

extension Color {
    static let filerGreen = Color(hex: "#34C759")
    static let filerPurple = Color(hex: "#AF52DE")
    static let filerGray = Color(hex: "#8E8E93")
    static let filerGroupedBackground = Color(hex: "#F2F2F7")
    static let filerIconTint = Color(hex: "#A8A8AE")
}
