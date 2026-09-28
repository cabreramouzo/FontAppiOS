import SwiftUI
import UIKit

/// Bronze, silver and gold are recognised without reading the word. Two palettes, as on
/// the web: the bronze that works on paper falls below 4.5:1 on the dark background.
enum TierColor {
    static func color(_ tier: String?) -> Color? {
        guard let tier, let pair = palette[tier] else { return nil }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: pair.dark) : UIColor(hex: pair.light) })
    }

    private static let palette: [String: (light: UInt32, dark: UInt32)] = [
        "bronze": (0x8A5A38, 0xD6A175), "silver": (0x5E6B77, 0xB3BFCA),
        "gold": (0x8F6D10, 0xE3BE58), "unique": (0x3F6E5D, 0x84C4AC),
    ]
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// A badge family's drawing, the web's art bundled so it shows offline. The drawing is the
/// same in the three tiers; the tier is the ring around it. Not earned: grey and faded,
/// with a lock. A family without a drawing falls back to a symbol in a ring.
struct BadgeImage: View {
    let family: String
    var tier: String?
    var locked = false
    var size: CGFloat = 88

    var body: some View {
        let ring = locked || tier == "unique" || tier == "special" ? nil : TierColor.color(tier)
        ZStack(alignment: .bottomTrailing) {
            Group {
                if UIImage(named: "badge-\(family)") != nil {
                    Image("badge-\(family)").resizable().scaledToFit()
                } else {
                    Image(systemName: Self.symbol(family))
                        .font(.system(size: size * 0.42))
                        .foregroundStyle(ring ?? .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.tertiarySystemFill), in: Circle())
                }
            }
            .frame(width: size, height: size)
            .grayscale(locked ? 1 : 0)
            .opacity(locked ? 0.4 : 1)
            .padding(ring == nil ? 0 : 3)
            .overlay { if let ring { Circle().strokeBorder(ring, lineWidth: 2) } }
            if locked {
                Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityHidden(true)
    }

    static func symbol(_ family: String) -> String {
        switch family {
        case "discoverer": "mappin.and.ellipse"
        case "firstLight": "camera"
        case "sentinel": "eye"
        case "cartographer": "map"
        case "regions", "international": "globe.europe.africa"
        case "drySeason": "sun.max"
        case "fourSeasons": "calendar"
        case "pioneer": "safari"
        case "betatester": "flask"
        default: "rosette"
        }
    }
}

/// A level's drawing; the level's name alone when it has none.
struct LevelImage: View {
    let key: String
    var locked = false
    var size: CGFloat = 88

    var body: some View {
        Group {
            if UIImage(named: "level-\(key)") != nil {
                Image("level-\(key)").resizable().scaledToFit()
            } else {
                Image(systemName: "drop.fill").font(.system(size: size * 0.4)).foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
        .grayscale(locked ? 1 : 0)
        .opacity(locked ? 0.4 : 1)
        .accessibilityHidden(true)
    }
}
