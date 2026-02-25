import SwiftUI

// MARK: - Journey Design System
// Calm, reflective, emotionally safe. Soft neutrals + pastel accents.

enum DS {

    // MARK: Colors
    enum Colors {
        // Backgrounds — warm neutral tones
        static let background       = Color(red: 0.98, green: 0.96, blue: 0.93)
        static let backgroundAlt    = Color(red: 0.95, green: 0.93, blue: 0.89)
        static let surface          = Color(red: 0.99, green: 0.98, blue: 0.96)
        static let surfaceElevated  = Color(red: 1.00, green: 0.99, blue: 0.97)

        // Pastel accents
        static let sage             = Color(red: 0.58, green: 0.76, blue: 0.64)   // muted sage green
        static let dustyBlue        = Color(red: 0.54, green: 0.68, blue: 0.82)   // dusty blue
        static let warmYellow       = Color(red: 0.97, green: 0.87, blue: 0.60)   // warm yellow
        static let softLavender     = Color(red: 0.76, green: 0.72, blue: 0.87)   // soft lavender
        static let blush            = Color(red: 0.93, green: 0.78, blue: 0.76)   // soft blush

        // Text — warm tones, never pure black
        static let primary          = Color(red: 0.18, green: 0.16, blue: 0.14)
        static let secondary        = Color(red: 0.50, green: 0.47, blue: 0.43)
        static let tertiary         = Color(red: 0.72, green: 0.69, blue: 0.65)
        static let onAccent         = Color.white

        // Chat bubbles
        static let userBubble       = dustyBlue
        static let assistantBubble  = backgroundAlt

        // Status / semantic
        static let error            = Color(red: 0.82, green: 0.42, blue: 0.38)
        static let success          = sage
    }

    // MARK: Radius
    enum Radius {
        static let xs:   CGFloat = 6
        static let sm:   CGFloat = 10
        static let md:   CGFloat = 16
        static let lg:   CGFloat = 22
        static let xl:   CGFloat = 30
        static let pill: CGFloat = 9999
    }

    // MARK: Spacing
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs:  CGFloat = 4
        static let sm:  CGFloat = 8
        static let md:  CGFloat = 16
        static let lg:  CGFloat = 24
        static let xl:  CGFloat = 32
        static let xxl: CGFloat = 48
    }

    // MARK: Shadow
    enum Shadow {
        static let color:  Color  = Color.black.opacity(0.06)
        static let radius: CGFloat = 10
        static let y:      CGFloat = 3
    }

    // MARK: Animation
    enum Anim {
        static let gentle = Animation.spring(response: 0.45, dampingFraction: 0.80)
        static let subtle = Animation.easeInOut(duration: 0.28)
        static let fade   = Animation.easeInOut(duration: 0.22)
    }

    // MARK: Typography — SF Pro Rounded
    static func font(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        Font.system(style, design: .rounded, weight: weight)
    }

    static func fontSize(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - View Modifiers

extension View {
    /// Soft card surface with rounded corners and gentle shadow
    func journeyCard(radius: CGFloat = DS.Radius.lg, padding: CGFloat = DS.Spacing.md) -> some View {
        self
            .padding(padding)
            .background(DS.Colors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: DS.Shadow.color, radius: DS.Shadow.radius, y: DS.Shadow.y)
    }
}

// MARK: - Journey Background

struct JourneyBackground: View {
    var body: some View {
        DS.Colors.background.ignoresSafeArea()
    }
}
