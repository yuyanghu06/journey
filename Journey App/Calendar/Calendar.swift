import SwiftUI

// MARK: - Calendar Screen

struct CalendarView: View {
    @State private var monthAnchor: Date = Date() // which month we're showing
    private let calendar = Calendar.autoupdatingCurrent

    private var monthTitle: String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .autoupdatingCurrent
        f.dateFormat = "LLLL yyyy" // e.g., "August 2025"
        return f.string(from: monthAnchor)
    }

    private var weekdaySymbols: [String] {
        // Rotate symbols so they start at the calendar's firstWeekday
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1 // 0-based
        return Array(symbols[first...] + symbols[..<first])
    }

    private var gridDates: [Date] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: start)!.count

        // index (0..6) of the first day relative to calendar.firstWeekday
        let firstWeekdayOfMonth = calendar.component(.weekday, from: start) - 1 // 0..6 (Sun=0)
        let first = (firstWeekdayOfMonth - (calendar.firstWeekday - 1) + 7) % 7

        var dates: [Date] = []

        // leading fillers from previous month
        for i in 0..<first {
            if let d = calendar.date(byAdding: .day, value: i - first, to: start) {
                dates.append(d)
            }
        }
        // current month days
        for day in 0..<daysInMonth {
            dates.append(calendar.date(byAdding: .day, value: day, to: start)!)
        }
        // trailing fillers to complete the last week
        let remainder = (7 - (dates.count % 7)) % 7
        for i in 0..<remainder {
            dates.append(calendar.date(byAdding: .day, value: daysInMonth + i, to: start)!)
        }
        return dates
    }

    var body: some View {
        VStack(spacing: 12) {
            header

            // Weekday row
            HStack {
                ForEach(weekdaySymbols, id: \.self) { s in
                    Text(s.uppercased())
                        .font(.caption2)
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)

            // Days grid
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(gridDates, id: \.self) { date in
                    let isInThisMonth = calendar.isDate(date, equalTo: monthAnchor, toGranularity: .month)
                    DayCell(date: date,
                            calendar: calendar,
                            isCurrentMonth: isInThisMonth)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(monthTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut) {
                    monthAnchor = calendar.date(byAdding: .month, value: -1, to: monthAnchor)!
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
                    .padding(8)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(monthTitle)
                .font(.headline)

            Spacer()

            Button {
                withAnimation(.easeInOut) {
                    monthAnchor = calendar.date(byAdding: .month, value: 1, to: monthAnchor)!
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
                    .padding(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

// MARK: - Day Cell (tappable -> navigates to a day screen)

private struct DayCell: View {
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

// MARK: - Day Details

struct DayDetailView: View {
    let date: Date
    private let calendar = Calendar.autoupdatingCurrent

    var title: String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale = .autoupdatingCurrent
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()
                .padding(.top)

            if calendar.isDate(date, equalTo: Date(), toGranularity: .day) &&
            calendar.isDate(date, equalTo: Date(), toGranularity: .month) {
                Text(currEntry)
                .foregroundStyle(.secondary)
                Spacer()
            } else {
                Text("No events yet.")
                .foregroundStyle(.secondary)
                Spacer()
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .navigationTitle("Day")
        .navigationBarTitleDisplayMode(.inline)
    }
}
