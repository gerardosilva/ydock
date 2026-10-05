import SwiftUI
import AppKit
import Combine

// MARK: - Settings schema per widget (edited from the popover's sliders button / context menu)

struct SettingField { let key: String; let label: String; let placeholder: String }

func settingFields(for name: String) -> [SettingField] {
    switch name {
    case "weather":
        return [.init(key: "lat", label: "Latitude", placeholder: "19.43"),
                .init(key: "lon", label: "Longitude", placeholder: "-99.13"),
                .init(key: "unit", label: "Unit (c / f)", placeholder: "c")]
    case "countdown":
        return [.init(key: "label", label: "Label", placeholder: "Launch"),
                .init(key: "date", label: "Date (yyyy-MM-dd or yyyy-MM-dd HH:mm)", placeholder: "2027-01-01")]
    case "script":
        return [.init(key: "label", label: "Label", placeholder: "Revenue"),
                .init(key: "command", label: "Shell command", placeholder: "date +%H:%M"),
                .init(key: "interval", label: "Refresh (seconds)", placeholder: "30"),
                .init(key: "icon", label: "SF Symbol (optional)", placeholder: "bolt.fill")]
    case "stickynote": return [.init(key: "color", label: "Color (#RRGGBB)", placeholder: "#FFD60A")]
    case "shortcut":
        return [.init(key: "name", label: "Shortcut name", placeholder: "My Shortcut"),
                .init(key: "icon", label: "SF Symbol", placeholder: "bolt.fill")]
    case "dropdown":
        return [.init(key: "title", label: "Title", placeholder: "Folders"),
                .init(key: "icon", label: "SF Symbol", placeholder: "folder")]
    case "worldclock": return [.init(key: "zones", label: "Time zones (comma separated)", placeholder: "Europe/Paris,Asia/Tokyo")]
    case "stock": return [.init(key: "symbol", label: "Symbol", placeholder: "AAPL")]
    case "photos":
        return [.init(key: "source", label: "Source (recent / favorites)", placeholder: "recent"),
                .init(key: "minutes", label: "Change every (minutes)", placeholder: "30")]
    case "timeprogress": return [.init(key: "unit", label: "Unit (year / month / day)", placeholder: "year")]
    case "focustimer":
        return [.init(key: "work", label: "Focus (minutes)", placeholder: "25"),
                .init(key: "break", label: "Break (minutes)", placeholder: "5")]
    default: return []
    }
}

func hasDetail(_ name: String) -> Bool {
    ["activity", "cpu", "memory", "network", "battery", "weather", "calendar", "clock", "worldclock",
     "countdown", "stock", "reminders", "stopwatch", "focustimer", "alarm", "notes", "batteries", "monthcalendar"].contains(name)
}

func detailContent(for item: DockItem) -> (title: String, view: AnyView)? {
    let name = item.value ?? ""
    let opts = item.options ?? [:]
    switch name {
    case "activity", "cpu", "memory": return (L("widget.activity"), AnyView(ActivityDetail()))
    case "network": return (L("widget.network"), AnyView(NetworkDetail()))
    case "battery": return (L("widget.battery"), AnyView(BatteryDetail()))
    case "weather": return (L("widget.weather"), AnyView(WeatherDetail(options: opts)))
    case "calendar": return (L("widget.calendar"), AnyView(CalendarDetail()))
    case "clock", "worldclock": return (L("widget.clock"), AnyView(ClockDetail(zones: opts["zones"])))
    case "countdown": return (opts["label"] ?? L("widget.countdown"), AnyView(CountdownDetail(options: opts)))
    case "stock": return (L("widget.stock"), AnyView(StockDetail(symbol: opts["symbol"] ?? "AAPL")))
    case "reminders": return (L("widget.reminders"), AnyView(RemindersDetail()))
    case "stopwatch": return (L("widget.stopwatch"), AnyView(StopwatchDetail(id: item.id)))
    case "focustimer": return (L("widget.focustimer"), AnyView(FocusTimerDetail(id: item.id)))
    case "alarm": return (L("widget.alarm"), AnyView(AlarmDetail(id: item.id, model: DetailPresenter.shared.model)))
    case "monthcalendar": return (L("widget.monthcalendar"), AnyView(MonthDetail()))
    case "notes": return (L("widget.notes"), AnyView(NotesDetail()))
    case "batteries": return (L("widget.batteries"), AnyView(BatteriesDetail()))
    default: return nil
    }
}

// MARK: - Detail views

struct RingGauge: View {
    let value: Double
    let color: Color
    let label: String
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 7)
                Circle().trim(from: 0, to: min(max(value, 0), 100) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value))%").font(.system(size: 22, weight: .medium, design: .rounded))
            }
            .frame(width: 76, height: 76)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color
    var body: some View {
        GeometryReader { g in
            let top = max(values.max() ?? 1, 1)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)),
                        y: g.size.height * (1 - CGFloat(v / top)))
            }
            Path { p in
                guard let f = pts.first else { return }
                p.move(to: CGPoint(x: f.x, y: g.size.height))
                pts.forEach { p.addLine(to: $0) }
                p.addLine(to: CGPoint(x: g.size.width, y: g.size.height))
            }.fill(color.opacity(0.18))
            Path { p in
                guard let f = pts.first else { return }
                p.move(to: f)
                pts.dropFirst().forEach { p.addLine(to: $0) }
            }.stroke(color, lineWidth: 1.5)
        }
        .frame(height: 34)
    }
}

struct ActivityDetail: View {
    @ObservedObject private var cpu = CPUMonitor.shared
    @ObservedObject private var mem = MemoryMonitor.shared
    private var memText: String {
        let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        return String(format: "%.1f / %.0f GiB", mem.usedPct / 100 * total, total)
    }
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer(); RingGauge(value: cpu.usage, color: .purple, label: "CPU")
                Spacer(); RingGauge(value: mem.usedPct, color: .blue, label: L("widget.memory"))
                Spacer()
            }
            Divider()
            DetailRow(label: L("detail.memused"), value: memText)
        }
    }
}

struct NetworkDetail: View {
    @ObservedObject private var mon = NetworkMonitor.shared
    private func block(_ title: String, _ value: Double, _ hist: [Double], _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(speed(value)).fontWeight(.medium).monospacedDigit() }
                .font(.system(size: 12))
            Sparkline(values: hist, color: color)
        }
    }
    var body: some View {
        VStack(spacing: 14) {
            block(L("net.down"), mon.down, mon.downHistory, .green)
            block(L("net.up"), mon.up, mon.upHistory, .orange)
        }
    }
}

struct BatteryDetail: View {
    @ObservedObject private var mon = BatteryMonitor.shared
    var body: some View {
        VStack(spacing: 14) {
            RingGauge(value: Double(mon.pct), color: mon.pct <= 20 && !mon.charging ? .red : .green,
                      label: mon.charging ? L("battery.charging") : L("battery.onbattery"))
            Divider()
            DetailRow(label: L("battery.remaining"), value: mon.remaining ?? "—")
        }
    }
}

struct WeatherDetail: View {
    @StateObject private var mon: WeatherMonitor
    let unit: String
    init(options: [String: String]) {
        unit = options["unit"] == "f" ? "°F" : "°C"
        _mon = StateObject(wrappedValue: WeatherMonitor(lat: options["lat"] ?? "19.43", lon: options["lon"] ?? "-99.13",
                                                        fahrenheit: options["unit"] == "f"))
    }
    private func t(_ v: Double?) -> String { v.map { "\(Int($0.rounded()))\(unit)" } ?? "—" }
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: mon.symbol).font(.system(size: 34))
                Text(t(mon.temp)).font(.system(size: 34, weight: .medium, design: .rounded))
                Spacer()
            }
            Divider()
            DetailRow(label: L("weather.feels"), value: t(mon.feels))
            DetailRow(label: L("weather.humidity"), value: mon.humidity.map { "\($0)%" } ?? "—")
            DetailRow(label: L("weather.wind"), value: mon.wind.map { "\(Int($0.rounded())) \(mon.windUnit)" } ?? "—")
            DetailRow(label: L("weather.range"), value: "\(t(mon.high)) / \(t(mon.low))")
        }
    }
}

struct CalendarDetail: View {
    @ObservedObject private var mon = CalendarMonitor.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mon.denied {
                Text(L("cal.noaccess")).foregroundStyle(.secondary).font(.system(size: 12))
            } else if mon.upcoming.isEmpty {
                Text(L("cal.noevents")).foregroundStyle(.secondary).font(.system(size: 12))
            }
            ForEach(mon.upcoming) { e in
                HStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text(e.allDay ? e.start.formatted(.dateTime.weekday().day().month().locale(Localizer.locale))
                             : e.start.formatted(.dateTime.weekday().hour().minute().locale(Localizer.locale)))
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Button(L("cal.open")) { openApp("/System/Applications/Calendar.app") }
        }
    }
}

struct ClockDetail: View {
    let zones: [TimeZone]
    init(zones: String?) {
        self.zones = (zones ?? "").split(separator: ",")
            .compactMap { TimeZone(identifier: $0.trimmingCharacters(in: .whitespaces)) }
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 10) {
                Text(ctx.date, format: .dateTime.hour().minute().second())
                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if !zones.isEmpty { Divider() }
                ForEach(Array(zones.enumerated()), id: \.offset) { _, tz in
                    DetailRow(label: cityName(tz), value: timeString(ctx.date, tz))
                }
            }
        }
    }
}

struct CountdownDetail: View {
    let target: Date?
    let dateText: String
    init(options: [String: String]) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        let s = options["date"] ?? ""
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var d = f.date(from: s)
        if d == nil { f.dateFormat = "yyyy-MM-dd"; d = f.date(from: s) }
        target = d
        dateText = d?.formatted(.dateTime.day().month(.wide).year().locale(Localizer.locale)) ?? s
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let secs = max(0, Int((target ?? ctx.date).timeIntervalSince(ctx.date)))
            VStack(spacing: 12) {
                HStack {
                    ForEach([(secs / 86400, L("cd.days")), ((secs / 3600) % 24, "h"), ((secs / 60) % 60, "m"), (secs % 60, "s")],
                           id: \.1) { v, label in
                        VStack(spacing: 0) {
                            Text(String(format: "%02d", v)).font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                Divider()
                DetailRow(label: L("cd.target"), value: dateText)
            }
        }
    }
}

struct StockDetail: View {
    @StateObject private var mon: StockMonitor
    init(symbol: String) { _mon = StateObject(wrappedValue: StockMonitor(symbol: symbol)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(mon.symbol).font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(mon.price.map { String(format: "%.2f", $0) } ?? "—")
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                Text(mon.currency).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if let c = mon.changePct {
                Text(String(format: "%+.2f%%", c)).font(.system(size: 14, weight: .medium))
                    .foregroundStyle(c >= 0 ? Color.green : Color.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct RemindersDetail: View {
    @ObservedObject private var mon = RemindersMonitor.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mon.denied { Text(L("cal.noaccess")).foregroundStyle(.secondary).font(.system(size: 12)) }
            else if mon.titles.isEmpty { Text(L("rem.empty")).foregroundStyle(.secondary).font(.system(size: 12)) }
            ForEach(Array(mon.titles.enumerated()), id: \.offset) { _, t in
                HStack(spacing: 8) {
                    Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(.blue)
                    Text(t).font(.system(size: 12)).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StopwatchDetail: View {
    @ObservedObject private var mon: StopwatchMonitor
    init(id: UUID) { mon = StopwatchMonitor.for(id) }
    var body: some View {
        VStack(spacing: 14) {
            Text(clockString(mon.elapsed, tenths: true))
                .font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
            HStack(spacing: 10) {
                Button(mon.running ? L("sw.pause") : L("sw.start")) { mon.toggle() }
                Button(L("sw.reset")) { mon.reset() }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct FocusTimerDetail: View {
    @ObservedObject private var mon: FocusTimerMonitor
    init(id: UUID) { mon = FocusTimerMonitor.for(id) }
    var body: some View {
        VStack(spacing: 12) {
            Text(mon.isWork ? L("focus.work") : L("focus.break")).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(clockString(TimeInterval(mon.remaining)))
                .font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
            HStack(spacing: 10) {
                Button(mon.running ? L("sw.pause") : L("sw.start")) { mon.toggle() }
                Button(L("sw.reset")) { mon.reset() }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Dock settings card (position, auto-hide, size, appearance, language)

struct PositionGlyph: View {
    let position: DockPosition
    let selected: Bool
    var body: some View {
        let bar = selected ? Color.accentColor : Color.primary.opacity(0.6)
        ZStack {
            RoundedRectangle(cornerRadius: 5).stroke(Color.primary.opacity(0.6), lineWidth: 1.5)
            switch position {
            case .left: Capsule().fill(bar).frame(width: 3, height: 14).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
            case .right: Capsule().fill(bar).frame(width: 3, height: 14).frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 4)
            case .bottom: Capsule().fill(bar).frame(width: 14, height: 3).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
            case .top: Capsule().fill(bar).frame(width: 14, height: 3).frame(maxHeight: .infinity, alignment: .top).padding(.top, 4)
            case .aboveSystemDock:
                Capsule().fill(bar).frame(width: 14, height: 3).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 10)
                Capsule().fill(Color.primary.opacity(0.3)).frame(width: 20, height: 2).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 4)
            }
        }
        .frame(width: 38, height: 26)
    }
}

final class LoginState: ObservableObject {
    @Published var enabled = LoginItem.enabled
    func set(_ on: Bool) { LoginItem.set(on); enabled = LoginItem.enabled }
}

struct DockSettingsCard: View {
    @ObservedObject var model: DockModel
    @StateObject private var login = LoginState()

    private func positionButton(_ p: DockPosition) -> some View {
        let sel = model.config.position == p
        return Button { model.setPosition(p) } label: {
            VStack(spacing: 4) {
                PositionGlyph(position: p, selected: sel)
                Text(p.title).font(.system(size: 9)).lineLimit(2).minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center).frame(height: 24)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(sel ? Color.primary.opacity(0.14) : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }

    private func toggleRow(_ title: String, _ value: Bool, _ set: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Toggle("", isOn: Binding(get: { value }, set: set)).labelsHidden().toggleStyle(.switch)
        }
    }

    private func sliderRow(_ title: String, _ value: Double, _ range: ClosedRange<Double>,
                           _ set: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 12))
            Spacer()
            Slider(value: Binding(get: { value }, set: { set($0.rounded()) }), in: range,
                   onEditingChanged: { if !$0 { model.save() } })
                .frame(width: 170)
        }
    }

    private func smallButton(_ title: String, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: symbol).font(.system(size: 11)) }
    }

    var body: some View {
        let cfg = model.config
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("settings.position")).font(.system(size: 13, weight: .semibold))
                HStack(spacing: 4) {
                    ForEach([DockPosition.left, .bottom, .right, .top, .aboveSystemDock], id: \.self) { positionButton($0) }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08)))
                toggleRow(L("menu.autohide"), cfg.autoHide) { _ in model.toggleAutoHide() }

                Divider()
                section(L("menu.appearance"))
                HStack {
                    Text(L("menu.appearance")).font(.system(size: 12))
                    Spacer()
                    Picker("", selection: Binding(get: { cfg.appearance }, set: { model.setAppearance($0) })) {
                        ForEach(DockAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 190)
                }
                if cfg.appearance == .tinted {
                    HStack { Text(L("menu.tint")).font(.system(size: 12)); Spacer()
                        Button(L("menu.tint")) { model.pickTint() } }
                }
                sliderRow(L("settings.size"), cfg.iconSize, 28...96) { model.config.iconSize = $0 }
                sliderRow(L("settings.spacing"), cfg.spacing, 2...24) { model.config.spacing = $0 }
                sliderRow(L("settings.corner"), cfg.cornerRadius, 6...34) { model.config.cornerRadius = $0 }

                Divider()
                section(L("settings.behavior"))
                toggleRow(L("settings.hoverzoom"), cfg.hoverZoom) { v in model.update { $0.hoverZoom = v } }
                toggleRow(L("settings.indicators"), cfg.showIndicators) { v in model.update { $0.showIndicators = v } }
                toggleRow(L("settings.handle"), cfg.showHandle) { v in model.update { $0.showHandle = v } }
                toggleRow(L("settings.profilepill"), cfg.showProfilePill) { v in model.update { $0.showProfilePill = v } }
                toggleRow(L("menu.login"), login.enabled) { login.set($0) }

                Divider()
                section(L("menu.profiles"))
                ForEach(cfg.profiles) { p in
                    HStack(spacing: 8) {
                        Button { model.setActiveProfile(p.id) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: p.id == cfg.activeProfile ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(p.id == cfg.activeProfile ? Color.accentColor : Color.secondary)
                                Text(p.name).font(.system(size: 12))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            DispatchQueue.main.async {
                                if let n = Prompt.text(title: L("profile.name"), initial: p.name) { model.renameProfile(p.id, to: n) }
                            }
                        } label: { Image(systemName: "pencil").font(.system(size: 11)) }
                            .buttonStyle(.plain)
                        if cfg.profiles.count > 1 {
                            Button { model.deleteProfile(p.id) } label: { Image(systemName: "trash").font(.system(size: 11)) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                smallButton(L("profile.new"), "plus") { ProfileActions.shared.newProfile() }

                Divider()
                section(L("settings.general"))
                HStack {
                    Text(L("menu.language")).font(.system(size: 12))
                    Spacer()
                    Picker("", selection: Binding(get: { cfg.language }, set: { model.setLanguage($0) })) {
                        Text(L("lang.system")).tag("system")
                        ForEach(Localizer.languageNames, id: \.code) { Text($0.name).tag($0.code) }
                    }
                    .labelsHidden().frame(width: 140)
                }
                HStack(spacing: 12) {
                    smallButton(L("menu.openconfig"), "doc.text") { NSWorkspace.shared.open(DockConfig.url) }
                    smallButton(L("menu.reload"), "arrow.clockwise") { model.reload() }
                }
                smallButton(L("menu.quit"), "power") { NSApp.terminate(nil) }
            }
            .padding(.vertical, 2)
        }
        .frame(maxHeight: 480)
    }
}

// MARK: - Popover chrome + presenter

final class DetailState: ObservableObject {
    @Published var settings: Bool
    init(settings: Bool) { self.settings = settings }
}

struct DetailChrome: View {
    let title: String?
    let item: DockItem?
    let fields: [SettingField]
    @ObservedObject var model: DockModel
    let content: AnyView
    let close: () -> Void
    let resize: () -> Void
    @StateObject private var state: DetailState

    init(title: String?, item: DockItem?, fields: [SettingField], model: DockModel, content: AnyView,
         startInSettings: Bool, close: @escaping () -> Void, resize: @escaping () -> Void) {
        self.title = title; self.item = item; self.fields = fields; self.model = model
        self.content = content; self.close = close; self.resize = resize
        _state = StateObject(wrappedValue: DetailState(settings: startInSettings))
    }

    private func headerButton(_ symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(active ? Color.primary.opacity(0.18) : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func form(_ item: DockItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(fields, id: \.key) { f in
                VStack(alignment: .leading, spacing: 3) {
                    Text(f.label).font(.system(size: 10)).foregroundStyle(.secondary)
                    TextField(f.placeholder, text: Binding(
                        get: { model.config.items.first { $0.id == item.id }?.options?[f.key] ?? "" },
                        set: { model.setOption(item.id, f.key, $0) }))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13)).foregroundStyle(.secondary)
                    Spacer()
                    if !fields.isEmpty { headerButton("slider.horizontal.3", active: state.settings) { state.settings.toggle() } }
                    headerButton("xmark", active: false, action: close)
                }
            }
            if state.settings, let item { form(item) } else { content }
        }
        .padding(18)
        .frame(width: 330)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 22).fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22)
                    .fill(Color(hex: model.config.tint).opacity(model.config.appearance == .tinted ? 0.4 : 0)))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.18)))
        )
        .environment(\.colorScheme, model.config.appearance == .light ? .light : .dark)
        .environment(\.locale, Localizer.locale)
        .onChange(of: state.settings) { _ in resize() }
    }
}

final class DetailPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { close() }
}

final class DetailPresenter: NSObject, NSWindowDelegate {
    static let shared = DetailPresenter()
    var model: DockModel!
    var dockFrame: () -> NSRect = { .zero }

    private var panel: DetailPanel?
    private var host: NSHostingView<AnyView>?
    private var currentID: String?
    private var anchor = NSPoint.zero
    private var lastClosed: (id: String, at: Date)?

    var isOpen: Bool { panel != nil }

    func toggleDetail(for item: DockItem) {
        guard let d = detailContent(for: item) else { return }
        present(id: item.id.uuidString, title: d.title, item: item,
                fields: settingFields(for: item.value ?? ""), content: d.view, startInSettings: false)
    }

    func openSettings(for item: DockItem) {
        present(id: item.id.uuidString + "-settings", title: L("widget.\(item.value ?? "")"), item: item,
                fields: settingFields(for: item.value ?? ""), content: AnyView(EmptyView()), startInSettings: true)
    }

    func toggleDockSettings() {
        present(id: "dock-settings", title: nil, item: nil, fields: [],
                content: AnyView(DockSettingsCard(model: model)), startInSettings: false)
    }

    private func present(id: String, title: String?, item: DockItem?, fields: [SettingField],
                         content: AnyView, startInSettings: Bool) {
        if currentID == id, panel != nil { close(); return }
        if let l = lastClosed, l.id == id, Date().timeIntervalSince(l.at) < 0.3 { return }   // click that just dismissed it
        close()
        anchor = NSEvent.mouseLocation
        let chrome = DetailChrome(title: title, item: item, fields: fields, model: model, content: content,
                                  startInSettings: startInSettings,
                                  close: { [weak self] in self?.close() },
                                  resize: { [weak self] in
                                      DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.refit() }
                                  })
        let h = NSHostingView(rootView: AnyView(chrome))
        let p = DetailPanel(contentRect: NSRect(origin: .zero, size: h.fittingSize),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        p.contentView = h
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isReleasedWhenClosed = false
        p.delegate = self
        panel = p; host = h; currentID = id
        refit()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    private func refit() {
        guard let p = panel, let h = host else { return }
        let size = h.fittingSize
        p.setContentSize(size)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame, d = dockFrame(), gap: CGFloat = 8
        var o = NSPoint.zero
        switch model.config.position {
        case .bottom, .aboveSystemDock: o = NSPoint(x: anchor.x - size.width / 2, y: d.maxY + gap)
        case .top: o = NSPoint(x: anchor.x - size.width / 2, y: d.minY - size.height - gap)
        case .left: o = NSPoint(x: d.maxX + gap, y: anchor.y - size.height / 2)
        case .right: o = NSPoint(x: d.minX - size.width - gap, y: anchor.y - size.height / 2)
        }
        o.x = min(max(o.x, f.minX + 8), f.maxX - size.width - 8)
        o.y = min(max(o.y, f.minY + 8), f.maxY - size.height - 8)
        p.setFrameOrigin(o)
    }

    func close() {
        guard let p = panel else { return }
        p.delegate = nil
        p.orderOut(nil)
        lastClosed = (currentID ?? "", Date())
        panel = nil; host = nil; currentID = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}
