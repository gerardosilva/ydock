import SwiftUI
import AppKit
import EventKit

// MARK: - Month grid helpers

enum MonthGrid {
    /// Calendar with the app's language for names, but the system's first weekday.
    static var calendar: Calendar {
        var c = Calendar.current
        c.locale = Localizer.locale
        c.firstWeekday = Calendar.current.firstWeekday
        return c
    }

    /// 42 cells (6 weeks); nil = day outside the month.
    static func days(for date: Date) -> [Int?] {
        let cal = calendar
        guard let start = cal.dateInterval(of: .month, for: date)?.start,
              let count = cal.range(of: .day, in: .month, for: date)?.count else { return Array(repeating: nil, count: 42) }
        let offset = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
        return (0..<42).map { i in
            let d = i - offset + 1
            return (1...count).contains(d) ? d : nil
        }
    }

    /// Single-letter weekday headers starting at the first weekday.
    static func weekdaySymbols() -> [String] {
        let cal = calendar
        let s = cal.veryShortStandaloneWeekdaySymbols
        let first = cal.firstWeekday - 1
        return Array(s[first...] + s[..<first])
    }

    static func isToday(_ day: Int, in month: Date) -> Bool {
        let cal = calendar
        guard let d = cal.date(bySetting: .day, value: day, of: cal.dateInterval(of: .month, for: month)?.start ?? month) else { return false }
        return cal.isDateInToday(d)
    }
}

// MARK: - Dock widget (compact month, today highlighted)

struct MonthCalendarWidget: View {
    let size: Double
    @Environment(\.dockVertical) private var vertical

    var body: some View {
        let cw = vertical ? size * 0.15 : size * 0.24
        let ch = vertical ? size * 0.15 : size * 0.17
        TimelineView(.periodic(from: .now, by: 1800)) { ctx in
            let days = MonthGrid.days(for: ctx.date)
            WidgetCard(size: size) {
                VStack(spacing: 1) {
                    Text(ctx.date, format: .dateTime.month(.wide))
                        .font(.system(size: 8, weight: .bold)).foregroundStyle(.red).textCase(.uppercase).lineLimit(1)
                        .minimumScaleFactor(1).fixedSize()
                    HStack(spacing: 0) {
                        ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, s in
                            Text(s).font(.system(size: ch * 0.8)).opacity(0.55).frame(width: cw, height: ch)
                        }
                    }
                    ForEach(0..<6, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { col in
                                let day = days[row * 7 + col]
                                let today = day.map { MonthGrid.isToday($0, in: ctx.date) } ?? false
                                ZStack {
                                    if today { Circle().fill(Color.red).frame(width: min(cw, ch) * 1.15, height: min(cw, ch) * 1.15) }
                                    if let day {
                                        Text("\(day)").font(.system(size: ch * 0.8, weight: today ? .bold : .regular))
                                            .foregroundStyle(today ? Color.white : Color.primary)
                                    }
                                }
                                .frame(width: cw, height: ch)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, vertical ? 0 : 4)
            }
        }
    }
}

// MARK: - Popover: full month with navigation and the selected day's events

final class MonthState: ObservableObject {
    @Published var month = Date()
    @Published var selected = Date()
    @Published var events: [UpcomingEvent] = []

    init() { reload() }

    func shift(_ months: Int) {
        month = MonthGrid.calendar.date(byAdding: .month, value: months, to: month) ?? month
        reload()
    }

    func today() { month = Date(); selected = Date(); reload() }

    func reload() {
        let cal = MonthGrid.calendar
        guard let iv = cal.dateInterval(of: .month, for: month) else { return }
        events = CalendarMonitor.shared.events(from: iv.start, to: iv.end)
    }

    func hasEvents(_ day: Int) -> Bool {
        let cal = MonthGrid.calendar
        return events.contains { cal.component(.day, from: $0.start) == day }
    }

    func date(_ day: Int) -> Date? {
        let cal = MonthGrid.calendar
        return cal.date(bySetting: .day, value: day, of: cal.dateInterval(of: .month, for: month)?.start ?? month)
    }

    var selectedEvents: [UpcomingEvent] {
        let cal = MonthGrid.calendar
        return events.filter { cal.isDate($0.start, inSameDayAs: selected) }
    }
}

struct MonthDetail: View {
    @StateObject private var st = MonthState()
    @ObservedObject private var cal = CalendarMonitor.shared

    private func cell(_ day: Int?) -> some View {
        ZStack {
            if let day, let d = st.date(day) {
                let today = MonthGrid.calendar.isDateInToday(d)
                let sel = MonthGrid.calendar.isDate(d, inSameDayAs: st.selected)
                VStack(spacing: 1) {
                    Text("\(day)").font(.system(size: 12, weight: today ? .bold : .regular))
                        .foregroundStyle(today ? Color.white : Color.primary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(today ? Color.red : Color.clear))
                    Circle().fill(st.hasEvents(day) ? Color.accentColor : Color.clear).frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 8).fill(sel && !today ? Color.primary.opacity(0.14) : Color.clear))
                .contentShape(Rectangle())
                .onTapGesture { st.selected = d }
            }
        }
        .frame(height: 34)
    }

    var body: some View {
        let days = MonthGrid.days(for: st.month)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(st.month, format: .dateTime.month(.wide).year()).font(.system(size: 15, weight: .semibold))
                Spacer()
                Button { st.shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 22, height: 22) }
                Button { st.today() } label: { Image(systemName: "circle.fill").font(.system(size: 6)).frame(width: 22, height: 22) }
                Button { st.shift(1) } label: { Image(systemName: "chevron.right").frame(width: 22, height: 22) }
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, s in
                    Text(s).font(.system(size: 10)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) { ForEach(0..<7, id: \.self) { col in cell(days[row * 7 + col]) } }
                }
            }

            Divider()
            if cal.denied { Text(L("cal.noaccess")).font(.system(size: 12)).foregroundStyle(.secondary) }
            else if st.selectedEvents.isEmpty { Text(L("cal.noevents")).font(.system(size: 12)).foregroundStyle(.secondary) }
            ForEach(st.selectedEvents.prefix(5)) { e in
                HStack(spacing: 8) {
                    Circle().fill(Color.accentColor).frame(width: 6, height: 6)
                    Text(e.allDay ? e.title : e.start.formatted(.dateTime.hour().minute().locale(Localizer.locale)) + "  " + e.title)
                        .font(.system(size: 12)).lineLimit(1)
                }
            }
            Button(L("cal.open")) { openApp("/System/Applications/Calendar.app") }
        }
        .onChange(of: cal.title) { _ in st.reload() }
    }
}
