import SwiftUI

// MARK: - CalendarView
// Displays a scrollable month grid with navigation arrows.
// Each day cell shows dots for stored conversations and journal entries.

struct CalendarView: View {
    @StateObject private var viewModel = CalendarViewModel()
    @EnvironmentObject var auth: AuthService

    var body: some View {
        ZStack {
            JourneyBackground()

            VStack(spacing: DS.Spacing.md) {
                monthHeader
                weekdayRow
                daysGrid
                Spacer()
            }
            .padding(.top, DS.Spacing.sm)
        }
        .navigationTitle(viewModel.monthTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Month Header

    private var monthHeader: some View {
        HStack {
            Button(action: viewModel.previousMonth) {
                navChevron(icon: "chevron.left")
            }
            Spacer()
            Text(viewModel.monthTitle)
                .font(DS.fontSize(17, weight: .semibold))
                .foregroundColor(DS.Colors.primary)
            Spacer()
            Button(action: viewModel.nextMonth) {
                navChevron(icon: "chevron.right")
            }
        }
        .padding(.horizontal, DS.Spacing.lg)
        .padding(.top, DS.Spacing.xs)
    }

    /// Circular navigation arrow button.
    private func navChevron(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(DS.Colors.secondary)
            .frame(width: 34, height: 34)
            .background(DS.Colors.backgroundAlt)
            .clipShape(Circle())
    }

    // MARK: - Weekday Row

    private var weekdayRow: some View {
        HStack(spacing: 0) {
            ForEach(viewModel.weekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(DS.font(.caption2))
                    .foregroundColor(DS.Colors.tertiary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DS.Spacing.md)
    }

    // MARK: - Days Grid

    private var daysGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: DS.Spacing.xs), count: 7),
            spacing: DS.Spacing.xs
        ) {
            ForEach(viewModel.gridDates, id: \.self) { date in
                DayCell(
                    date:            date,
                    isCurrentMonth:  viewModel.isCurrentMonth(date),
                    isToday:         viewModel.isToday(date),
                    hasConversation: viewModel.hasConversation(on: date),
                    hasJournalEntry: viewModel.hasJournalEntry(on: date)
                )
            }
        }
        .padding(.horizontal, DS.Spacing.md)
    }
}
