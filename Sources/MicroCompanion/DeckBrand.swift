import SwiftUI

enum DeckBrand {
    static let name = "Keyberth"
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark ? NSColor(srgbRed: 0.69, green: 0.74, blue: 1, alpha: 1)
                    : NSColor(srgbRed: 0.30, green: 0.33, blue: 0.72, alpha: 1)
    })
}

/// A key stem, rotary dial and slanted keycap form the letter K.
struct DeckMark: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 64
            context.scaleBy(x: scale, y: scale)
            let ink = Color(red: 0.14, green: 0.16, blue: 0.30)
            let pearl = Color(red: 0.96, green: 0.97, blue: 1)
            let lilac = Color(red: 0.72, green: 0.77, blue: 1)
            context.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 64, height: 64), cornerRadius: 15), with: .color(ink))
            context.fill(Path(roundedRect: CGRect(x: 13, y: 12, width: 13, height: 40), cornerRadius: 5), with: .color(pearl))
            let dial = CGRect(x: 32, y: 10, width: 22, height: 22)
            context.fill(Path(ellipseIn: dial), with: .color(lilac))
            var tick = Path()
            tick.move(to: CGPoint(x: 43, y: 20))
            tick.addLine(to: CGPoint(x: 47, y: 15))
            context.stroke(tick, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            var key = Path()
            key.move(to: CGPoint(x: 26, y: 37))
            key.addLine(to: CGPoint(x: 35, y: 30))
            key.addLine(to: CGPoint(x: 52, y: 47))
            key.addQuadCurve(to: CGPoint(x: 49, y: 52), control: CGPoint(x: 55, y: 52))
            key.addLine(to: CGPoint(x: 41, y: 52))
            key.closeSubpath()
            context.fill(key, with: .color(pearl))
        }.accessibilityHidden(true)
    }
}
