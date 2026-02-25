import SwiftUI

// MARK: - DayCell
// A single cell in the calendar grid. Tappable for current-month days,
// dimmed for padding days outside the month. Shows pastel dots beneath
// the day number to indicate stored conversation or journal data.

struct DayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isToday: Bool
    let hasConversation: Bool
    let hasJournalEntry: Bool

    private let calendar = Calendar.autoupdatingCurrent

    var body: some View {
        Group {
            if isCurrentMonth {
                NavigationLink(destination: DayDetailView(date: date)) {
                    cellContent
                }
                .buttonStyle(.plain)
            } else {
                cellContent.opacity(0.20)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Cell content

    private var cellContent: some View {
        let day = calendar.component(.day, from: date)
        return ZStack {
            // Background tile
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(isToday ? DS.Colors.dustyBlue.opacity(0.15) : DS.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .strokeBorder(
                            isToday ? DS.Colors.dustyBlue.opacity(0.45) : Color.clear,
                            lineWidth: 1.2
                        )
                )

            VStack(spacing: DS.Spacing.xxs) {
                // Day number
                Text("\(day)")
                    .font(DS.font(.callout, weight: isToday ? .semibold : .regular))
                    .foregroundColor(isToday ? DS.Colors.dustyBlue : DS.Colors.primary)

                // Indicator dots
                HStack(spacing: 3) {
                    if hasConversation  { dot(DS.Colors.dustyBlue) }
                    if hasJournalEntry  { dot(DS.Colors.sage) }
                }
                .frame(height: 5)
            }
        }
        .shadow(color: DS.Shadow.color.opacity(0.5), radius: 3, y: 1)
    }

    /// A tiny filled circle used as a data-presence indicator.
    private func dot(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 4, height: 4)
    }
}
