import Foundation
import AppKit

struct Space: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorHex: String   // e.g. "#5B8AF6"
    var order: Int

    var color: NSColor {
        NSColor(hex: colorHex) ?? .systemBlue
    }

    // Preset accent colors cycled when creating spaces
    static let presetColors: [String] = [
        "#5B8AF6", "#FF6B6B", "#4CAF7D", "#F5A623",
        "#9B59B6", "#1ABC9C", "#E74C3C", "#3498DB"
    ]
}

// MARK: - NSColor hex init
extension NSColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex = String(hex.dropFirst()) }
        guard hex.count == 6, let value = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >>  8) & 0xFF) / 255
        let b = CGFloat((value      ) & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
