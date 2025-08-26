//
//  dayCell.swift
//  Journey App
//
//  Created by Yuyang Hu on 8/24/25.
//
import SwiftUI

// MARK: - Day Cell (tappable -> navigates to a day screen)

struct DayCell: View {
    let date: Date
    let calendar: Calendar
    let isCurrentMonth: Bool

    var body: some View {
        Group {
            if isCurrentMonth {
                NavigationLink(destination: DayDetailView(date: date)) {
                    label
                }
                .buttonStyle(.plain)
            } else {
                label.opacity(0.35) // dim days from prev/next month
            }
        }
        .aspectRatio(1, contentMode: .fit) // squares
    }

    private var label: some View {
        let day = calendar.component(.day, from: date)
        return ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemBackground))
            Text("\(day)")
                .font(.body)
        }
    }
}
