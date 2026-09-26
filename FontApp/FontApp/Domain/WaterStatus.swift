import SwiftUI

/// Water status as reported in reviews. The API sends a plain string; unknown values
/// are kept as `nil` status and drawn like "no status yet". Mirrors `web/src/lib/waterStatus.ts`.
nonisolated enum WaterStatus: String, Sendable, CaseIterable {
    case flowing, trickle, dry, broken, gone, unknown

    init?(_ raw: String?) {
        guard let raw, let status = WaterStatus(rawValue: raw) else { return nil }
        self = status
    }

    var labelKey: String { "status.\(rawValue)" }

    var emoji: String {
        switch self {
        case .flowing: "💧"
        case .trickle: "💦"
        case .dry: "🚱"
        case .broken: "🛠️"
        case .gone: "🪦"
        case .unknown: "❔"
        }
    }

    /// Same colours as the web pins, so people moving between the two read the map alike.
    var color: Color {
        switch self {
        case .flowing: Color(hex: 0x22C55E)
        case .trickle: Color(hex: 0xF59E0B)
        case .dry: Color(hex: 0xEF4444)
        case .broken: Color(hex: 0xA855F7)
        case .gone: Color(hex: 0x6B7280)
        case .unknown: Color(hex: 0x9CA3AF)
        }
    }

    /// Pin colour for a fountain nobody has reported on.
    static let noStatusColor = Color(hex: 0x3B82F6)

    static func color(for raw: String?) -> Color {
        WaterStatus(raw)?.color ?? noStatusColor
    }
}

extension Color {
    nonisolated init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
