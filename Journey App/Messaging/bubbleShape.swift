//
//  BubbleShape.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//

import SwiftUI

// MARK: - Shapes & Components

struct BubbleShape: Shape {
    let isFromCurrentUser: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 18
        let corners: UIRectCorner = isFromCurrentUser
            ? [.topLeft, .topRight, .bottomRight]
            : [.topLeft, .topRight, .bottomLeft]

        let bez = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        var path = Path(bez.cgPath)

        // Tiny tail
        let tailWidth: CGFloat = 6
        let tailHeight: CGFloat = 10
        let y = rect.maxY - 6

        if isFromCurrentUser {
            var p = Path()
            p.move(to: CGPoint(x: rect.maxX - 10, y: y - tailHeight))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: y),
                           control: CGPoint(x: rect.maxX - 2, y: y - 4))
            p.addLine(to: CGPoint(x: rect.maxX - tailWidth, y: y - 2))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - 10, y: y - tailHeight),
                           control: CGPoint(x: rect.maxX - 8, y: y - 8))
            path.addPath(p)
        } else {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX + 10, y: y - tailHeight))
            p.addQuadCurve(to: CGPoint(x: rect.minX, y: y),
                           control: CGPoint(x: rect.minX + 2, y: y - 4))
            p.addLine(to: CGPoint(x: rect.minX + tailWidth, y: y - 2))
            p.addQuadCurve(to: CGPoint(x: rect.minX + 10, y: y - tailHeight),
                           control: CGPoint(x: rect.minX + 8, y: y - 8))
            path.addPath(p)
        }
        return path
    }
}

