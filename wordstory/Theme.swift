import SwiftUI

/// Shared color palette + spacing constants. The named accent color lives in
/// `Assets.xcassets/AccentColor.colorset` and is reachable via `Color.accentColor`.
enum Theme {

    // MARK: - Colors (cream / paper / ink / burgundy)
    static let background = Color(red: 0.96, green: 0.94, blue: 0.88)   // warm cream
    static let paper      = Color(red: 0.985, green: 0.965, blue: 0.91)  // slightly lighter card surface
    static let paperSoft  = Color(red: 0.94, green: 0.91, blue: 0.83)
    static let ink        = Color(red: 0.16, green: 0.145, blue: 0.125)
    static let inkSoft    = Color(red: 0.35, green: 0.31, blue: 0.27)
    static let inkQuiet   = Color(red: 0.48, green: 0.43, blue: 0.38)
    static let rule       = Color(red: 0.89, green: 0.85, blue: 0.77)
    static let accentBG   = Color(red: 0.62, green: 0.30, blue: 0.24).opacity(0.10)
    static let danger     = Color(red: 0.63, green: 0.27, blue: 0.27)

    // MARK: - Fonts
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension View {
    /// Cream-paper background applied to a view (often a scroll content area).
    func appBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
