import SwiftUI

// MARK: - CalendarViewModel
// Manages the currently-displayed month and computes the grid of dates.
// Also exposes which days have conversation or journal data for badge display.

@MainActor
final class CalendarViewModel: ObservableObject {

    // MARK: - Published state

    @Published var monthAnchor: Date = Date()

    // MARK: - Dependencies

    private let conversationRepository: ConversationRepositoryProtocol
    private let journalRepository: JournalRepositoryProtocol
    private let calendar = Calendar.autoupdatingCurrent

    // MARK: - Badge data (loaded once per calendar open)

    /// Days that have at least one chat message.
    @Published var daysWithConversations: Set<String> = []

    /// Days that have a generated journal entry.
    @Published var daysWithJournalEntries: Set<String> = []

    // MARK: - Init

    init(
        conversationRepository: ConversationRepositoryProtocol = InMemoryConversationRepository(),
        journalRepository: JournalRepositoryProtocol = InMemoryJournalRepository()
    ) {
        self.conversationRepository = conversationRepository
        self.journalRepository      = journalRepository
        loadBadgeData()
    }

    // MARK: - Computed properties

    /// e.g. "February 2026"
    var monthTitle: String {
        let f = DateFormatter()
        f.calendar = calendar
        f.locale   = .autoupdatingCurrent
        f.dateFormat = "LLLL yyyy"
        return f.string(from: monthAnchor)
    }

    /// Short weekday symbols starting from the locale's first weekday.
    var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first   = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// All dates needed to fill the month grid, including leading/trailing padding days.
    var gridDates: [Date] {
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: monthAnchor)),
              let range = calendar.range(of: .day, in: .month, for: start) else { return [] }

        let daysInMonth      = range.count
        let firstWeekday     = calendar.component(.weekday, from: start) - 1
        let leadingDays      = (firstWeekday - (calendar.firstWeekday - 1) + 7) % 7

        var dates: [Date] = []

        // Leading padding from the previous month
        for i in 0..<leadingDays {
            if let d = calendar.date(byAdding: .day, value: i - leadingDays, to: start) {
                dates.append(d)
            }
        }

        // Current month's days
        for day in 0..<daysInMonth {
            if let d = calendar.date(byAdding: .day, value: day, to: start) {
                dates.append(d)
            }
        }

        // Trailing padding to complete the last row
        let remainder = (7 - (dates.count % 7)) % 7
        for i in 0..<remainder {
            if let d = calendar.date(byAdding: .day, value: daysInMonth + i, to: start) {
                dates.append(d)
            }
        }
        return dates
    }

    // MARK: - Helpers

    /// True when the given date falls within the currently displayed month.
    func isCurrentMonth(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: monthAnchor, toGranularity: .month)
    }

    /// True when the given date is today.
    func isToday(_ date: Date) -> Bool {
        calendar.isDateInToday(date)
    }

    /// True when the day has at least one stored chat message.
    func hasConversation(on date: Date) -> Bool {
        daysWithConversations.contains(DayKey.from(date).rawValue)
    }

    /// True when the day has a generated journal entry.
    func hasJournalEntry(on date: Date) -> Bool {
        daysWithJournalEntries.contains(DayKey.from(date).rawValue)
    }

    // MARK: - Navigation

    func previousMonth() {
        withAnimation(DS.Anim.gentle) {
            monthAnchor = calendar.date(byAdding: .month, value: -1, to: monthAnchor) ?? monthAnchor
        }
    }

    func nextMonth() {
        withAnimation(DS.Anim.gentle) {
            monthAnchor = calendar.date(byAdding: .month, value: 1, to: monthAnchor) ?? monthAnchor
        }
    }

    // MARK: - Private

    /// Loads badge data from both repositories.
    private func loadBadgeData() {
        Task {
            async let chatDays    = conversationRepository.listDaysWithConversations()
            async let journalDays = journalRepository.listDaysWithJournalEntries()
            let (chat, journal) = await (chatDays, journalDays)
            daysWithConversations  = Set(chat.map    { $0.rawValue })
            daysWithJournalEntries = Set(journal.map { $0.rawValue })
        }
    }
}
