import SwiftUI
import IOKit.ps

// MARK: - Container

struct DockVerticalKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// True when the dock is on the left/right edge (compact, narrow column layout).
    var dockVertical: Bool {
        get { self[DockVerticalKey.self] }
        set { self[DockVerticalKey.self] = newValue }
    }
}

struct WidgetCard<Content: View>: View {
    let size: Double
    var fill: Color? = nil
    @Environment(\.dockVertical) private var vertical
    @ViewBuilder var content: Content
    var body: some View {
        content
            .lineLimit(2)
            .minimumScaleFactor(0.6)
            .frame(width: vertical ? size * 1.15 : nil)
            .frame(minWidth: vertical ? nil : size * 1.4, minHeight: vertical ? size * 0.9 : size)
            .padding(.horizontal, vertical ? 2 : 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(fill ?? Color.primary.opacity(0.12)))
    }
}

func caption(_ s: String) -> some View {
    Text(s).font(.system(size: 10)).opacity(0.7).lineLimit(1)
}

// MARK: - Clock

struct ClockWidget: View {
    let size: Double
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            WidgetCard(size: size) {
                VStack(spacing: 0) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(ctx.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(.system(size: 10)).opacity(0.7)
                }
                .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Battery

final class BatteryMonitor: ObservableObject {
    static let shared = BatteryMonitor()
    @Published var pct = 0
    @Published var charging = false
    @Published var remaining: String?
    @Published var present = false   // false on desktop Macs
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let est = IOPSGetTimeRemainingEstimate()
        remaining = est > 0 ? "\(Int(est) / 3600)h \(Int(est) / 60 % 60)m" : nil
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as Array
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(info, ps).takeUnretainedValue() as? [String: Any],
               let cur = d[kIOPSCurrentCapacityKey] as? Int {
                pct = cur
                present = true
                charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
                return
            }
        }
        pct = 100 // desktop Mac, no battery
    }
}

struct BatteryWidget: View {
    let size: Double
    @ObservedObject private var mon = BatteryMonitor.shared
    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 2) {
                Image(systemName: mon.charging ? "battery.100.bolt" : "battery.75").font(.system(size: 16))
                Text("\(mon.pct)%").font(.system(size: 14, weight: .medium, design: .rounded))
                if let r = mon.remaining { caption(r) }
            }
            .foregroundStyle(mon.pct <= 20 && !mon.charging ? Color.red : Color.primary)
        }
    }
}

// MARK: - CPU

final class CPUMonitor: ObservableObject {
    static let shared = CPUMonitor()
    @Published var usage = 0.0
    private var last: host_cpu_load_info?
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.sample() }
        sample()
    }

    private func sample() {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        if let l = last {
            let u = Double(info.cpu_ticks.0 - l.cpu_ticks.0)
            let s = Double(info.cpu_ticks.1 - l.cpu_ticks.1)
            let i = Double(info.cpu_ticks.2 - l.cpu_ticks.2)
            let n = Double(info.cpu_ticks.3 - l.cpu_ticks.3)
            let total = u + s + i + n
            if total > 0 { usage = (u + s + n) / total * 100 }
        }
        last = info
    }
}

struct CPUWidget: View {
    let size: Double
    @ObservedObject private var mon = CPUMonitor.shared
    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 2) {
                caption("CPU")
                Text("\(Int(mon.usage))%").font(.system(size: 18, weight: .semibold, design: .rounded))
                ProgressView(value: min(mon.usage, 100), total: 100)
                    .tint(mon.usage > 80 ? .red : .green).frame(width: 40)
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Memory

final class MemoryMonitor: ObservableObject {
    static let shared = MemoryMonitor()
    @Published var usedPct = 0.0
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.sample() }
        sample()
    }

    private func sample() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let pages = Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)
        usedPct = pages * Double(getpagesize()) / Double(ProcessInfo.processInfo.physicalMemory) * 100
    }
}

struct MemoryWidget: View {
    let size: Double
    @ObservedObject private var mon = MemoryMonitor.shared
    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 2) {
                caption("RAM")
                Text("\(Int(mon.usedPct))%").font(.system(size: 18, weight: .semibold, design: .rounded))
                ProgressView(value: min(mon.usedPct, 100), total: 100)
                    .tint(mon.usedPct > 85 ? .red : .blue).frame(width: 40)
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Weather (Open-Meteo, no API key). options: lat, lon, unit = c|f

final class WeatherMonitor: ObservableObject {
    @Published var temp: Double?
    @Published var code = 0
    @Published var feels: Double?
    @Published var humidity: Int?
    @Published var wind: Double?
    @Published var high: Double?
    @Published var low: Double?
    let windUnit: String
    private let url: URL?
    private var timer: Timer?

    init(lat: String, lon: String, fahrenheit: Bool) {
        windUnit = fahrenheit ? "mph" : "km/h"
        url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
                  + "&current=temperature_2m,weather_code,apparent_temperature,relative_humidity_2m,wind_speed_10m"
                  + "&daily=temperature_2m_max,temperature_2m_min&forecast_days=1&timezone=auto"
                  + "&temperature_unit=\(fahrenheit ? "fahrenheit" : "celsius")&wind_speed_unit=\(fahrenheit ? "mph" : "kmh")")
        fetch()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in self?.fetch() }
    }

    private func fetch() {
        guard let url else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cur = j["current"] as? [String: Any],
                  let t = cur["temperature_2m"] as? Double,
                  let c = cur["weather_code"] as? Int else { return }
            let daily = j["daily"] as? [String: Any]
            let hi = (daily?["temperature_2m_max"] as? [Double])?.first
            let lo = (daily?["temperature_2m_min"] as? [Double])?.first
            DispatchQueue.main.async {
                self?.temp = t; self?.code = c
                self?.feels = cur["apparent_temperature"] as? Double
                self?.humidity = (cur["relative_humidity_2m"] as? Double).map(Int.init) ?? (cur["relative_humidity_2m"] as? Int)
                self?.wind = cur["wind_speed_10m"] as? Double
                self?.high = hi; self?.low = lo
            }
        }.resume()
    }

    var symbol: String {
        switch code {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51...57: return "cloud.drizzle"
        case 61...67: return "cloud.rain"
        case 71...77: return "cloud.snow"
        case 80...82: return "cloud.heavyrain"
        case 95...99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }
}

struct WeatherWidget: View {
    let size: Double
    let unit: String
    @StateObject private var mon: WeatherMonitor

    init(size: Double, options: [String: String]) {
        self.size = size
        unit = options["unit"] == "f" ? "°F" : "°C"
        _mon = StateObject(wrappedValue: WeatherMonitor(lat: options["lat"] ?? "19.43",
                                                        lon: options["lon"] ?? "-99.13",
                                                        fahrenheit: options["unit"] == "f"))
    }

    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 2) {
                Image(systemName: mon.symbol).font(.system(size: 16))
                Text(mon.temp.map { "\(Int($0.rounded()))\(unit)" } ?? "—")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
            }
            .foregroundStyle(.primary)
        }
    }
}

// MARK: - Script: runs a shell command, shows its output. options: command, label, interval, icon

final class ScriptMonitor: ObservableObject {
    @Published var text = "…"
    private let command: String
    private var timer: Timer?

    init(command: String, interval: Double) {
        self.command = command
        run()
        timer = Timer.scheduledTimer(withTimeInterval: max(interval, 2), repeats: true) { [weak self] _ in self?.run() }
    }

    private func run() {
        let cmd = command
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", cmd]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            var result = "err"
            if (try? p.run()) != nil {
                let data = out.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                result = s.isEmpty ? "—" : s
            }
            DispatchQueue.main.async { self?.text = result }
        }
    }
}

struct ScriptWidget: View {
    let size: Double
    let label: String
    let icon: String?
    @StateObject private var mon: ScriptMonitor

    init(size: Double, options: [String: String]) {
        self.size = size
        label = options["label"] ?? ""
        icon = options["icon"]
        _mon = StateObject(wrappedValue: ScriptMonitor(command: options["command"] ?? "echo ?",
                                                       interval: Double(options["interval"] ?? "") ?? 30))
    }

    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 2) {
                if let icon { Image(systemName: icon).font(.system(size: 14)) }
                else if !label.isEmpty { caption(label) }
                Text(mon.text).font(.system(size: 14, weight: .medium, design: .rounded))
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: 110)
        }
    }
}

// MARK: - Registry (add new widgets here and in DockModel.widgetNames)

/// Widget view; widgets that have a detail popover open it on click.
@ViewBuilder
func widgetView(_ item: DockItem, size: Double) -> some View {
    if hasDetail(item.value ?? "") {
        baseWidget(item, size: size)
            .contentShape(Rectangle())
            .onTapGesture { DetailPresenter.shared.toggleDetail(for: item) }
    } else {
        baseWidget(item, size: size)
    }
}

@ViewBuilder
func baseWidget(_ item: DockItem, size: Double) -> some View {
    let opts = item.options ?? [:]
    switch item.value ?? "" {
    case "clock": ClockWidget(size: size)
    case "battery": BatteryWidget(size: size)
    case "cpu": CPUWidget(size: size)
    case "memory": MemoryWidget(size: size)
    case "weather": WeatherWidget(size: size, options: opts)
    case "script": ScriptWidget(size: size, options: opts)
    case "calendar": CalendarWidget(size: size)
    case "countdown": CountdownWidget(size: size, options: opts)
    case "network": NetworkWidget(size: size)
    case "activity": ActivityWidget(size: size)
    case "nowplaying": NowPlayingWidget(size: size)
    case "shortcut": ShortcutWidget(size: size, options: opts)
    case "airdrop": AirDropWidget(size: size)
    case "dropdown": DropdownWidget(size: size, item: item)
    case "stickynote": StickyWidget(size: size, item: item)
    case "worldclock": WorldClockWidget(size: size, options: opts)
    case "reminders": RemindersWidget(size: size)
    case "stock": StockWidget(size: size, options: opts)
    case "timeprogress": TimeProgressWidget(size: size, options: opts)
    case "stopwatch": StopwatchWidget(size: size, item: item)
    case "focustimer": FocusTimerWidget(size: size, item: item)
    case "alarm": AlarmWidget(size: size, item: item)
    case "monthcalendar": MonthCalendarWidget(size: size)
    case "notes": NotesWidget(size: size)
    case "photos": PhotosWidget(size: size, options: opts)
    case "batteries": BatteriesWidget(size: size)
    default: WidgetCard(size: size) { Text("?\(item.value ?? "")").foregroundStyle(.primary) }
    }
}
