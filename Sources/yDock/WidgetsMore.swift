import SwiftUI
import AppKit
import EventKit

// MARK: - World clock. options: zones = comma-separated IANA ids

struct WorldClockWidget: View {
    let size: Double
    let zones: [TimeZone]
    @Environment(\.dockVertical) private var vertical

    init(size: Double, options: [String: String]) {
        self.size = size
        zones = (options["zones"] ?? "America/Mexico_City,Europe/London")
            .split(separator: ",").compactMap { TimeZone(identifier: $0.trimmingCharacters(in: .whitespaces)) }
            .prefix(3).map { $0 }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            WidgetCard(size: size) {
                let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
                layout {
                    ForEach(Array(zones.enumerated()), id: \.offset) { _, tz in
                        VStack(spacing: 0) {
                            Text(timeString(ctx.date, tz)).font(.system(size: 14, weight: .semibold, design: .rounded))
                            caption(cityName(tz))
                        }
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, vertical ? 0 : 6)
            }
        }
    }
}

func timeString(_ d: Date, _ tz: TimeZone) -> String {
    d.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Localizer.locale, timeZone: tz))
}

func cityName(_ tz: TimeZone) -> String {
    (tz.identifier.split(separator: "/").last.map(String.init) ?? tz.identifier).replacingOccurrences(of: "_", with: " ")
}

// MARK: - Reminders (EventKit)

final class RemindersMonitor: ObservableObject {
    static let shared = RemindersMonitor()
    @Published var titles: [String] = []
    @Published var count = 0
    @Published var denied = false
    private let store = EKEventStore()
    private var timer: Timer?

    init() {
        let handler: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.denied = !granted
                if granted { self?.refresh() }
            }
        }
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if eventKitGranted(status) { refresh() }
        else if status == .notDetermined {
            if #available(macOS 14.0, *) { store.requestFullAccessToReminders(completion: handler) }
            else { store.requestAccess(to: .reminder, completion: handler) }
        } else { denied = true }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date()))
        let pred = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: endOfToday, calendars: nil)
        store.fetchReminders(matching: pred) { [weak self] rems in
            let titles = (rems ?? []).map { $0.title ?? "" }
            DispatchQueue.main.async { self?.titles = Array(titles.prefix(6)); self?.count = titles.count }
        }
    }
}

struct RemindersWidget: View {
    let size: Double
    @ObservedObject private var mon = RemindersMonitor.shared
    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "checklist").font(.system(size: 12)).foregroundStyle(.blue)
                    Text("\(mon.count)").font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                caption(mon.denied ? L("cal.noaccess") : (mon.titles.first ?? L("rem.empty")))
                    .frame(maxWidth: 90)
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Stocks (Yahoo Finance public chart endpoint — unofficial, may change). options: symbol

final class StockMonitor: ObservableObject {
    @Published var price: Double?
    @Published var previous: Double?
    @Published var currency = ""
    let symbol: String
    private var timer: Timer?

    init(symbol: String) {
        self.symbol = symbol.uppercased()
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.fetch() }
    }

    private func fetch() {
        let enc = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? symbol
        guard let url = URL(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(enc)?interval=1d&range=1d") else { return }
        var req = URLRequest(url: url)
        req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let chart = j["chart"] as? [String: Any],
                  let result = (chart["result"] as? [[String: Any]])?.first,
                  let meta = result["meta"] as? [String: Any],
                  let p = meta["regularMarketPrice"] as? Double else { return }
            let prev = meta["chartPreviousClose"] as? Double
            let cur = meta["currency"] as? String ?? ""
            DispatchQueue.main.async { self?.price = p; self?.previous = prev; self?.currency = cur }
        }.resume()
    }

    var changePct: Double? {
        guard let p = price, let v = previous, v != 0 else { return nil }
        return (p - v) / v * 100
    }
}

struct StockWidget: View {
    let size: Double
    @StateObject private var mon: StockMonitor

    init(size: Double, options: [String: String]) {
        self.size = size
        _mon = StateObject(wrappedValue: StockMonitor(symbol: options["symbol"] ?? "AAPL"))
    }

    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 1) {
                caption(mon.symbol)
                Text(mon.price.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                if let c = mon.changePct {
                    Text(String(format: "%+.2f%%", c)).font(.system(size: 10, weight: .medium))
                        .foregroundStyle(c >= 0 ? Color.green : Color.red)
                }
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Time progress (year / month / day). options: unit

struct TimeProgressWidget: View {
    let size: Double
    let unit: String
    @Environment(\.dockVertical) private var vertical

    init(size: Double, options: [String: String]) {
        self.size = size
        unit = options["unit"] ?? "year"
    }

    static func fraction(_ unit: String, _ now: Date) -> Double {
        let comp: Calendar.Component = unit == "day" ? .day : (unit == "month" ? .month : .year)
        guard let iv = Calendar.current.dateInterval(of: comp, for: now), iv.duration > 0 else { return 0 }
        return now.timeIntervalSince(iv.start) / iv.duration
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            let f = Self.fraction(unit, ctx.date)
            WidgetCard(size: size) {
                VStack(spacing: 4) {
                    HStack {
                        Group {
                            if unit == "day" { Text(ctx.date, format: .dateTime.hour().minute()) }
                            else if unit == "month" { Text(ctx.date, format: .dateTime.month(.abbreviated)) }
                            else { Text(ctx.date, format: .dateTime.year()) }
                        }.font(.system(size: 10, weight: .bold))
                        Spacer(minLength: 4)
                        Text("\(Int(f * 100))%").font(.system(size: 11, weight: .semibold))
                    }
                    HStack(spacing: 1) {
                        ForEach(0..<(vertical ? 14 : 36), id: \.self) { i in
                            Rectangle().fill(Color.primary.opacity(Double(i) / Double(vertical ? 14 : 36) < f ? 0.85 : 0.2))
                                .frame(width: 1.5, height: 14)
                        }
                    }
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, vertical ? 4 : 8)
                .frame(width: vertical ? nil : 120)
            }
        }
    }
}

// MARK: - Stopwatch (state lives in a per-widget store so popover + widget share it)

final class StopwatchMonitor: ObservableObject {
    private static var stores: [UUID: StopwatchMonitor] = [:]
    static func `for`(_ id: UUID) -> StopwatchMonitor {
        if let s = stores[id] { return s }
        let s = StopwatchMonitor(); stores[id] = s; return s
    }

    @Published var elapsed: TimeInterval = 0
    @Published var running = false
    private var startedAt: Date?
    private var base: TimeInterval = 0
    private var timer: Timer?

    func toggle() {
        if running {
            base = elapsed
            timer?.invalidate()
            running = false
        } else {
            startedAt = Date()
            running = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let s = self.startedAt else { return }
                self.elapsed = self.base + Date().timeIntervalSince(s)
            }
        }
    }

    func reset() {
        timer?.invalidate()
        running = false
        base = 0
        elapsed = 0
    }
}

func clockString(_ t: TimeInterval, tenths: Bool = false) -> String {
    let s = Int(t)
    let base = s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    return tenths ? base + String(format: ".%d", Int(t * 10) % 10) : base
}

struct StopwatchWidget: View {
    let size: Double
    @ObservedObject private var mon: StopwatchMonitor
    init(size: Double, item: DockItem) { self.size = size; mon = StopwatchMonitor.for(item.id) }
    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 1) {
                Text(clockString(mon.elapsed)).font(.system(size: 18, weight: .semibold, design: .rounded)).monospacedDigit()
                caption(mon.running ? L("sw.start") + " ●" : L("widget.stopwatch"))
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Focus timer (work / break). options: work, break (minutes)

final class FocusTimerMonitor: ObservableObject {
    private static var stores: [UUID: FocusTimerMonitor] = [:]
    static func `for`(_ id: UUID) -> FocusTimerMonitor {
        if let s = stores[id] { return s }
        let s = FocusTimerMonitor(); stores[id] = s; return s
    }

    @Published var remaining = 25 * 60
    @Published var isWork = true
    @Published var running = false
    private(set) var workMin = 25
    private(set) var breakMin = 5
    private var timer: Timer?

    var total: Int { (isWork ? workMin : breakMin) * 60 }

    func configure(work: Int, rest: Int) {
        guard work != workMin || rest != breakMin else { return }
        workMin = work; breakMin = rest
        if !running { remaining = total }
    }

    func toggle() {
        if running { timer?.invalidate(); running = false; return }
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    func reset() {
        timer?.invalidate()
        running = false
        isWork = true
        remaining = total
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            NSSound.beep()
            isWork.toggle()
            remaining = total
        }
    }
}

struct FocusTimerWidget: View {
    let size: Double
    @ObservedObject private var mon: FocusTimerMonitor

    init(size: Double, item: DockItem) {
        self.size = size
        mon = FocusTimerMonitor.for(item.id)
        mon.configure(work: Int(item.options?["work"] ?? "") ?? 25, rest: Int(item.options?["break"] ?? "") ?? 5)
    }

    var body: some View {
        WidgetCard(size: size) {
            HStack(spacing: 6) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.2), lineWidth: 4)
                    Circle().trim(from: 0, to: Double(mon.remaining) / Double(max(mon.total, 1)))
                        .stroke(mon.isWork ? Color.orange : Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(clockString(TimeInterval(mon.remaining))).font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                    caption(mon.isWork ? L("focus.work") : L("focus.break"))
                }
            }
            .foregroundStyle(.primary)
        }
    }
}
