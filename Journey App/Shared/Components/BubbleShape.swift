import SwiftUI

// MARK: - BubbleShape
// A rounded rectangle with a small directional tail, used to render
// chat bubbles. The tail points left for assistant messages and right
// for user messages.

struct BubbleShape: Shape {
    /// True when the bubble belongs to the local user (tail points right).
    let isFromCurrentUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        // Round all corners except the tail-side bottom corner
        let corners: UIRectCorner = isFromCurrentUser
            ? [.topLeft, .topRight, .bottomLeft]
            : [.topLeft, .topRight, .bottomRight]

        let bez = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        var path = Path(bez.cgPath)

        // Draw the small curved tail
        let tailWidth:  CGFloat = 6
        let tailHeight: CGFloat = 10
        let y = rect.maxY - 6

        if isFromCurrentUser {
            var p = Path()
            p.move(to: CGPoint(x: rect.maxX - 10, y: y - tailHeight))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: y),
                control: CGPoint(x: rect.maxX - 2, y: y - 4)
            )
            p.addLine(to: CGPoint(x: rect.maxX - tailWidth, y: y - 2))
            p.addQuadCurve(
                to: CGPoint(x: rect.maxX - 10, y: y - tailHeight),
                control: CGPoint(x: rect.maxX - 8, y: y - 8)
            )
            path.addPath(p)
        } else {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + 10, y: y - tailHeight))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX, y: y),
                control: CGPoint(x: rect.minX + 2, y: y - 4)
            )
            p.addLine(to: CGPoint(x: rect.minX + tailWidth, y: y - 2))
            p.addQuadCurve(
                to: CGPoint(x: rect.minX + 10, y: y - tailHeight),
                control: CGPoint(x: rect.minX + 8, y: y - 8)
            )
            path.addPath(p)
        }
        return path
    }
}
