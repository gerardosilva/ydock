import SwiftUI
import AppKit

// MARK: - Alarm model helpers. options: time "HH:mm", enabled "1"/"0", repeat daily|weekdays|once,
//                              sound (macOS system sound), label, armed/last (epoch seconds, managed by the app)

enum AlarmSupport {
    static let sounds = ["Glass", "Hero", "Ping", "Funk", "Submarine", "Sosumi", "Basso", "Blow", "Bottle", "Frog", "Morse", "Pop", "Purr", "Tink"]

    static func parse(_ time: String?) -> (h: Int, m: Int)? {
        guard let t = time else { return nil }
        let p = t.split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]), (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return (h, m)
    }

    static func date(for time: String?, on day: Date = Date()) -> Date? {
        guard let (h, m) = parse(time) else { return nil }
        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: day)
    }

    static func runsOn(_ opts: [String: String], day: Date) -> Bool {
        guard opts["repeat"] == "weekdays" else { return true }
        let wd = Calendar.current.component(.weekday, from: day)   // 1 = Sunday
        return (2...6).contains(wd)
    }

    /// Next time this alarm will ring (nil when off / unset).
    static func nextFire(_ opts: [String: String], now: Date = Date()) -> Date? {
        guard opts["enabled"] == "1", parse(opts["time"]) != nil else { return nil }
        let armed = Double(opts["armed"] ?? "") ?? 0
        for offset in 0..<8 {
            guard let day = Calendar.current.date(byAdding: .day, value: offset, to: now),
                  let d = date(for: opts["time"], on: day), runsOn(opts, day: day) else { continue }
            if d > now && d.timeIntervalSince1970 >= armed { return d }
        }
        return nil
    }
}

// MARK: - Scheduler (checks every second, across all profiles)

final class AlarmCenter {
    static let shared = AlarmCenter()
    weak var model: DockModel?
    private var timer: Timer?
    private var snoozed: [String: Date] = [:]   // keyed by profile|time|label so it survives config reloads
    private var ringing = false

    func start() {
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard let model else { return }
        let now = Date()
        for profile in model.config.profiles {
            for item in profile.items where item.type == "widget" && item.value == "alarm" {
                let o = item.options ?? [:]
                guard o["enabled"] == "1", let scheduled = AlarmSupport.date(for: o["time"]) else { continue }
                let key = "\(profile.id)|\(o["time"] ?? "")|\(o["label"] ?? "")"
                if let until = snoozed[key] {
                    if now >= until { snoozed[key] = nil; ring(item, key: key) }
                    continue
                }
                let armed = Double(o["armed"] ?? "") ?? 0
                let stamp = String(Int(scheduled.timeIntervalSince1970))
                if AlarmSupport.runsOn(o, day: now), now >= scheduled, now.timeIntervalSince(scheduled) < 600,
                   scheduled.timeIntervalSince1970 >= armed, o["last"] != stamp {
                    model.setOption(item.id, "last", stamp)
                    if o["repeat"] == "once" { model.setOption(item.id, "enabled", "0") }
                    ring(item, key: key)
                }
            }
        }
    }

    private func ring(_ item: DockItem, key: String) {
        guard !ringing else { return }
        ringing = true
        let o = item.options ?? [:]
        let sound = NSSound(named: o["sound"] ?? "Glass")
        sound?.loops = true
        sound?.play()
        AlarmRingPanel.show(time: o["time"] ?? "", label: o["label"] ?? "") { [weak self] snooze in
            sound?.stop()
            self?.ringing = false
            if snooze { self?.snoozed[key] = Date().addingTimeInterval(300) }
        }
    }
}

// MARK: - Ringing window

struct AlarmRingView: View {
    let time: String
    let label: String
    let done: (Bool) -> Void
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "alarm.fill").font(.system(size: 30)).foregroundStyle(.orange)
            Text(AlarmSupport.date(for: time)?.formatted(.dateTime.hour().minute().locale(Localizer.locale)) ?? time)
                .font(.system(size: 34, weight: .medium, design: .rounded))
            Text(label.isEmpty ? L("widget.alarm") : label).font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button(L("alarm.snooze")) { done(true) }
                Button(L("alarm.stop")) { done(false) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 280)
        .background(RoundedRectangle(cornerRadius: 22).fill(.regularMaterial)
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.18))))
        .environment(\.colorScheme, .dark)
        .environment(\.locale, Localizer.locale)
    }
}

enum AlarmRingPanel {
    private static var panel: DetailPanel?
    private static var autoStop: Timer?

    static func show(time: String, label: String, done: @escaping (Bool) -> Void) {
        let finish: (Bool) -> Void = { snooze in
            autoStop?.invalidate()
            panel?.orderOut(nil)
            panel = nil
            done(snooze)
        }
        let host = NSHostingView(rootView: AlarmRingView(time: time, label: label, done: finish))
        let p = DetailPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless],
                            backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .screenSaver
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.center()
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
        autoStop = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { _ in finish(false) }
    }
}

// MARK: - Dock widget

struct AlarmWidget: View {
    let size: Double
    let item: DockItem
    @Environment(\.dockVertical) private var vertical

    var body: some View {
        let o = item.options ?? [:]
        let date = AlarmSupport.date(for: o["time"])
        let on = o["enabled"] == "1" && date != nil
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            WidgetCard(size: size) {
                let layout = vertical ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(spacing: 8))
                layout {
                    VStack(alignment: vertical ? .center : .leading, spacing: 1) {
                        if let date {
                            Text(date.formatted(.dateTime.hour().minute().locale(Localizer.locale)))
                                .font(.system(size: 18, weight: .medium, design: .rounded)).opacity(on ? 1 : 0.5)
                            caption(on ? subtitle(o, now: ctx.date) : L("widget.alarm"))
                        } else {
                            Text(L("widget.alarm")).font(.system(size: 16, weight: .medium))
                            caption(L("alarm.set"))
                        }
                    }
                    if !vertical { Spacer(minLength: 4) }
                    Image(systemName: on ? "alarm.fill" : "alarm").font(.system(size: 14))
                        .foregroundStyle(on ? Color.orange : Color.primary.opacity(0.6))
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, vertical ? 0 : 6)
                .frame(minWidth: vertical ? nil : 104)
            }
        }
    }

    private func subtitle(_ o: [String: String], now: Date) -> String {
        if let l = o["label"], !l.isEmpty { return l }
        guard let next = AlarmSupport.nextFire(o, now: now) else { return L("widget.alarm") }
        let f = RelativeDateTimeFormatter()
        f.locale = Localizer.locale
        f.unitsStyle = .short
        return f.localizedString(for: next, relativeTo: now)
    }
}

// MARK: - Popover

struct AlarmDetail: View {
    let id: UUID
    @ObservedObject var model: DockModel

    private var opts: [String: String] {
        for p in model.config.profiles { if let i = p.items.first(where: { $0.id == id }) { return i.options ?? [:] } }
        return [:]
    }

    private func arm(_ extra: [String: String]) {
        var d = extra
        d["armed"] = String(Int(Date().timeIntervalSince1970))
        d["last"] = ""
        model.setOptions(id, d)
    }

    var body: some View {
        let o = opts
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L("alarm.enabled")).font(.system(size: 12))
                Spacer()
                Toggle("", isOn: Binding(get: { o["enabled"] == "1" },
                                         set: { arm(["enabled": $0 ? "1" : "0"]) }))
                    .labelsHidden().toggleStyle(.switch)
                    .disabled(AlarmSupport.parse(o["time"]) == nil)
            }
            DatePicker("", selection: Binding(
                get: { AlarmSupport.date(for: o["time"]) ?? AlarmSupport.date(for: "07:00") ?? Date() },
                set: { d in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    arm(["time": String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0), "enabled": "1"])
                }), displayedComponents: .hourAndMinute)
                .datePickerStyle(.graphical).labelsHidden()
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Text(L("alarm.repeat")).font(.system(size: 12))
                Spacer()
                Picker("", selection: Binding(get: { o["repeat"] ?? "daily" }, set: { arm(["repeat": $0]) })) {
                    Text(L("alarm.daily")).tag("daily")
                    Text(L("alarm.weekdays")).tag("weekdays")
                    Text(L("alarm.once")).tag("once")
                }
                .labelsHidden().frame(width: 150)
            }
            HStack {
                Text(L("alarm.sound")).font(.system(size: 12))
                Spacer()
                Picker("", selection: Binding(get: { o["sound"] ?? "Glass" }, set: {
                    model.setOption(id, "sound", $0)
                    NSSound(named: $0)?.play()
                })) {
                    ForEach(AlarmSupport.sounds, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 150)
            }
            TextField(L("alarm.label"), text: Binding(get: { o["label"] ?? "" }, set: { model.setOption(id, "label", $0) }))
                .textFieldStyle(.roundedBorder)
        }
    }
}
