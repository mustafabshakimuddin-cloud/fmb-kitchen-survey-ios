import SwiftUI

extension Color {
    static let slate50 = Color(hexString: "F8FAFC")
    static let slate100 = Color(hexString: "F1F5F9")
    static let slate200 = Color(hexString: "E2E8F0")
    static let slate300 = Color(hexString: "CBD5E1")
    static let slate400 = Color(hexString: "94A3B8")
    static let slate500 = Color(hexString: "64748B")
    static let slate600 = Color(hexString: "475569")
    static let slate700 = Color(hexString: "334155")
    static let slate800 = Color(hexString: "1E293B")
    static let slate900 = Color(hexString: "0F172A")
    
    init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

struct Theme {
    // Dynamic Colors
    static var background: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(Color.slate900) : UIColor(Color.slate50)
        })
    }
    
    static var secondaryBackground: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(Color.slate800) : UIColor.white
        })
    }
    
    static var card: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(Color.slate800) : UIColor.white
        })
    }
    
    static var cardSelected: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(Color.blue.opacity(0.15)) : UIColor(Color.blue.opacity(0.05))
        })
    }
    
    static var textPrimary: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor.white : UIColor(Color.slate900)
        })
    }
    
    static var textSecondary: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(Color.slate400) : UIColor(Color.slate600)
        })
    }
    
    static var textMuted: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(Color.slate600) : UIColor(Color.slate400)
        })
    }
    
    static var border: Color {
        Color(UIColor { traitCollection in
            return traitCollection.userInterfaceStyle == .dark ? UIColor(Color.slate700) : UIColor(Color.slate200)
        })
    }
    
    static var accent: Color = .blue
    static var success: Color = .green
    static var danger: Color = .red
    static var warning: Color = .orange
}
