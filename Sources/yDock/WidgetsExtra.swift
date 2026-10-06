import SwiftUI
import AppKit
import EventKit

// MARK: - Helpers

private func runAppleScript(_ src: String) -> String? {
    var err: NSDictionary?
    return NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue
}

private func runProcess(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(decoding: data, as: UTF8.self)
}

/// Installed Shortcuts.app shortcut names.
func listShortcuts() -> [String] {
    runProcess("/usr/bin/shortcuts", ["list"]).split(separator: "\n").map(String.init)
}

func eventKitGranted(_ s: EKAuthorizationStatus) -> Bool {
    if #available(macOS 14.0, *) { return s == .fullAccess }
    return s == .authorized
}

func openApp(_ path: String) {
    NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
}

// MARK: - Calendar (EventKit — asks for calendar access the first time)

struct UpcomingEvent: Identifiable {
    let id = UUID()
    let title: String
    let start: Date
    let allDay: Bool
}

final class CalendarMonitor: ObservableObject {
    static let shared = CalendarMonitor()
    @Published var upcoming: [UpcomingEvent] = []
    @Published var title: String?
    @Published var start: Date?
    @Published var allDay = false
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
        // Only ask when macOS has never been asked; otherwise just use the saved decision.
        let status = EKEventStore.authorizationStatus(for: .event)
        if eventKitGranted(status) { refresh() }
        else if status == .notDetermined {
            if #available(macOS 14.0, *) { store.requestFullAccessToEvents(completion: handler) }
            else { store.requestAccess(to: .event, completion: handler) }
        } else { denied = true }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// Events between two dates (empty when calendar access has not been granted).
    func events(from: Date, to: Date) -> [UpcomingEvent] {
        guard eventKitGranted(EKEventStore.authorizationStatus(for: .event)) else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: nil))
            .sorted { $0.startDate < $1.startDate }
            .map { UpcomingEvent(title: $0.title ?? "", start: $0.startDate, allDay: $0.isAllDay) }
    }

    func refresh() {
        let now = Date()
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: now) else { return }
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: nil))
            .filter { $0.endDate > now }
            .sorted { $0.startDate < $1.startDate }
        let ev = events.first { !$0.isAllDay } ?? events.first
        upcoming = events.prefix(6).map { UpcomingEvent(title: $0.title ?? "", start: $0.startDate, allDay: $0.isAllDay) }
        title = ev?.title
        start = ev?.startDate
        allDay = ev?.isAllDay ?? false
    }
}

struct CalendarWidget: View {
    let size: Double
    @ObservedObject private var mon = CalendarMonitor.shared

    private var eventLine: String {
        if mon.denied { return L("cal.noaccess") }
        guard let t = mon.title else { return L("cal.noevents") }
        guard let s = mon.start, !mon.allDay else { return t }
        return s.formatted(.dateTime.hour().minute().locale(Localizer.locale)) + " " + t
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            WidgetCard(size: size) {
                VStack(spacing: 0) {
                    Text(ctx.date, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.red).textCase(.uppercase)
                    Text(ctx.date, format: .dateTime.day())
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text(eventLine).font(.system(size: 9)).opacity(0.75).lineLimit(1).frame(maxWidth: 90)
                }
                .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Countdown. options: date ("yyyy-MM-dd" or "yyyy-MM-dd HH:mm"), label

struct CountdownWidget: View {
    let size: Double
    let label: String
    let target: Date?

    init(size: Double, options: [String: String]) {
        self.size = size
        label = options["label"] ?? ""
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let s = options["date"] ?? ""
        f.dateFormat = "yyyy-MM-dd HH:mm"
        var d = f.date(from: s)
        if d == nil { f.dateFormat = "yyyy-MM-dd"; d = f.date(from: s) }
        target = d
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            WidgetCard(size: size) {
                VStack(spacing: 1) {
                    if let target {
                        let secs = max(0, Int(target.timeIntervalSince(ctx.date)))
                        if secs >= 86400 {
                            Text("\(secs / 86400)").font(.system(size: 22, weight: .semibold, design: .rounded))
                            caption(L("cd.days"))
                        } else {
                            Text(String(format: "%02d:%02d:%02d", secs / 3600, (secs / 60) % 60, secs % 60))
                                .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                    } else {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 14))
                    }
                    if !label.isEmpty { caption(label) }
                }
                .foregroundStyle(.primary)
            }
        }
    }
}

// MARK: - Network (live up/down speed)

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published var down = 0.0   // bytes/s
    @Published var up = 0.0
    @Published var downHistory = [Double](repeating: 0, count: 60)
    @Published var upHistory = [Double](repeating: 0, count: 60)
    private var last: (rx: UInt64, tx: UInt64, t: Date)?
    private var timer: Timer?

    init() {
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.sample() }
    }

    private func counters() -> (UInt64, UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0 else { return (0, 0) }
        var p = addrs
        while let cur = p {
            let ifa = cur.pointee
            if let a = ifa.ifa_addr, a.pointee.sa_family == UInt8(AF_LINK),
               ifa.ifa_flags & UInt32(IFF_UP) != 0, ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
               let d = ifa.ifa_data {
                let data = d.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(data.ifi_ibytes)
                tx += UInt64(data.ifi_obytes)
            }
            p = ifa.ifa_next
        }
        freeifaddrs(addrs)
        return (rx, tx)
    }

    private func sample() {
        let (rx, tx) = counters()
        let now = Date()
        if let l = last {
            let dt = now.timeIntervalSince(l.t)
            if dt > 0 {
                down = rx >= l.rx ? Double(rx - l.rx) / dt : 0
                up = tx >= l.tx ? Double(tx - l.tx) / dt : 0
            }
        }
        last = (rx, tx, now)
        downHistory.append(down); downHistory.removeFirst()
        upHistory.append(up); upHistory.removeFirst()
    }
}

func speed(_ b: Double) -> String {
    if b >= 1_048_576 { return String(format: "%.1f MB/s", b / 1_048_576) }
    if b >= 1024 { return String(format: "%.0f KB/s", b / 1024) }
    return String(format: "%.0f B/s", b)
}

struct NetworkWidget: View {
    let size: Double
    @ObservedObject private var mon = NetworkMonitor.shared
    var body: some View {
        WidgetCard(size: size) {
            VStack(alignment: .leading, spacing: 3) {
                Label(speed(mon.down), systemImage: "arrow.down").foregroundStyle(.green)
                Label(speed(mon.up), systemImage: "arrow.up").foregroundStyle(.orange)
            }
            .labelStyle(CompactLabel())
            .font(.system(size: 10, weight: .medium, design: .rounded)).monospacedDigit()
            .lineLimit(1)
        }
    }
}

struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) { configuration.icon.font(.system(size: 8, weight: .bold)); configuration.title }
    }
}

// MARK: - System activity (CPU + RAM in one card)

struct ActivityWidget: View {
    let size: Double
    @ObservedObject private var cpu = CPUMonitor.shared
    @ObservedObject private var mem = MemoryMonitor.shared

    private func metric(_ value: Double, _ name: String, _ color: Color) -> some View {
        VStack(spacing: 0) {
            Text("\(Int(value))%").font(.system(size: 17, weight: .semibold, design: .rounded))
            HStack(spacing: 3) { Circle().fill(color).frame(width: 5, height: 5); caption(name) }
        }
    }

    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 5) {
                metric(cpu.usage, "CPU", .purple)
                metric(mem.usedPct, "RAM", .blue)
            }
            .foregroundStyle(.primary)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Now playing (Music + Spotify via AppleScript; macOS asks for Automation permission)

final class NowPlayingMonitor: ObservableObject {
    @Published var title: String?
    @Published var artist = ""
    @Published var playing = false
    private var appName: String?
    private var timer: Timer?
    private let players = [("com.spotify.client", "Spotify"), ("com.apple.Music", "Music")]

    init() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var paused: (String, [String])?
        for (bundle, name) in players where running.contains(bundle) {
            let script = """
            tell application "\(name)"
                if player state is not stopped then
                    return (player state as text) & linefeed & (name of current track) & linefeed & (artist of current track)
                end if
            end tell
            """
            guard let out = runAppleScript(script) else { continue }
            let parts = out.components(separatedBy: "\n")
            guard parts.count >= 3 else { continue }
            if parts[0].contains("playing") { apply(name, parts, playing: true); return }
            if paused == nil { paused = (name, parts) }
        }
        if let (name, parts) = paused { apply(name, parts, playing: false) }
        else { title = nil; playing = false; appName = nil }
    }

    private func apply(_ app: String, _ parts: [String], playing: Bool) {
        appName = app
        title = parts[1]
        artist = parts[2]
        self.playing = playing
    }

    func togglePlay() {
        guard let appName else { return }
        _ = runAppleScript("tell application \"\(appName)\" to playpause")
        poll()
    }
}

struct NowPlayingWidget: View {
    let size: Double
    @StateObject private var mon = NowPlayingMonitor()
    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 1) {
                Image(systemName: mon.title == nil ? "music.note" : (mon.playing ? "pause.fill" : "play.fill"))
                    .font(.system(size: 13))
                Text(mon.title ?? L("np.nothing")).font(.system(size: 10, weight: .medium)).lineLimit(1)
                if mon.title != nil { caption(mon.artist) }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: 100)
        }
        .contentShape(Rectangle())
        .onTapGesture { mon.togglePlay() }
    }
}

// MARK: - Shortcut (runs a Shortcuts.app shortcut). options: name, icon

final class ShortcutRunner: ObservableObject {
    @Published var running = false
    func run(_ name: String) {
        guard !running else { return }
        running = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            _ = runProcess("/usr/bin/shortcuts", ["run", name])
            DispatchQueue.main.async { self?.running = false }
        }
    }
}

struct ShortcutWidget: View {
    let size: Double
    let name: String
    let icon: String
    @StateObject private var runner = ShortcutRunner()

    init(size: Double, options: [String: String]) {
        self.size = size
        name = options["name"] ?? ""
        icon = options["icon"] ?? "bolt.fill"
    }

    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 3) {
                if runner.running { ProgressView().controlSize(.small) }
                else { Image(systemName: icon).font(.system(size: 17)) }
                Text(name).font(.system(size: 10, weight: .medium)).multilineTextAlignment(.center)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: 80)
        }
        .contentShape(Rectangle())
        .onTapGesture { runner.run(name) }
        .help(name)
    }
}

// MARK: - AirDrop (drop files on it to open the AirDrop sheet; click opens AirDrop)

private let airDropAppPath = "/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app"

struct AirDropWidget: View {
    let size: Double
    @StateObject private var target = HoverState()

    /// The real AirDrop app icon (falls back to the SF Symbol if the system app is not where we expect it).
    @ViewBuilder
    private var icon: some View {
        if FileManager.default.fileExists(atPath: airDropAppPath) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: airDropAppPath))
                .resizable().frame(width: 30, height: 30)
                .scaleEffect(target.on ? 1.12 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: target.on)
        } else {
            Image(systemName: "airdrop").font(.system(size: 22))
        }
    }

    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 3) {
                icon
                caption(target.on ? L("airdrop.drop") : "AirDrop")
            }
            .foregroundStyle(target.on ? Color.accentColor : Color.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            openApp("/System/Library/CoreServices/Finder.app/Contents/Applications/AirDrop.app")
        }
        .onDrop(of: [.fileURL], isTargeted: Binding(get: { target.on }, set: { target.on = $0 })) { providers in
            var urls: [URL] = []
            let group = DispatchGroup()
            for p in providers {
                group.enter()
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { urls.append(url) } }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                if let svc = NSSharingService(named: .sendViaAirDrop), svc.canPerform(withItems: urls) {
                    NSApp.activate(ignoringOtherApps: true)
                    svc.perform(withItems: urls)
                }
            }
            return true
        }
    }
}

// MARK: - Dropdown: a button that pops up a menu of apps / folders / links (item.children)

final class DropdownMenuHandler: NSObject {
    static let shared = DropdownMenuHandler()
    @objc func open(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        if raw.contains("://"), let url = URL(string: raw) { NSWorkspace.shared.open(url) }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: raw)) }
    }
}

struct DropdownWidget: View {
    let size: Double
    let item: DockItem

    private var title: String { item.options?["title"] ?? "" }
    private var icon: String { item.options?["icon"] ?? "folder" }

    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 18))
                HStack(spacing: 2) { caption(title); Image(systemName: "chevron.down").font(.system(size: 7)) }
            }
            .foregroundStyle(.primary)
        }
        .contentShape(Rectangle())
        .onTapGesture { showMenu() }
    }

    private func showMenu() {
        let menu = NSMenu()
        for child in item.children ?? [] {
            let raw = child.value ?? ""
            let isLink = raw.contains("://")
            let name = isLink ? (URL(string: raw)?.host ?? raw)
                : URL(fileURLWithPath: raw).deletingPathExtension().lastPathComponent
            let mi = NSMenuItem(title: name, action: #selector(DropdownMenuHandler.open(_:)), keyEquivalent: "")
            mi.target = DropdownMenuHandler.shared
            mi.representedObject = raw
            let img = isLink ? NSImage(systemSymbolName: "link", accessibilityDescription: nil)
                : NSWorkspace.shared.icon(forFile: raw)
            img?.size = NSSize(width: 16, height: 16)
            mi.image = img
            menu.addItem(mi)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

// MARK: - Sticky note: click opens a small editor window; the widget previews the text

final class StickyEditor: NSObject, NSTextViewDelegate, NSWindowDelegate {
    private static var open: [UUID: StickyEditor] = [:]
    private let id: UUID
    private unowned let model: DockModel
    private let window: NSPanel
    private let textView: NSTextView

    static func show(id: UUID, text: String, colorHex: String, model: DockModel) {
        if let e = open[id] { e.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let e = StickyEditor(id: id, text: text, colorHex: colorHex, model: model)
        open[id] = e
        NSApp.activate(ignoringOtherApps: true)
        e.window.makeKeyAndOrderFront(nil)
    }

    private init(id: UUID, text: String, colorHex: String, model: DockModel) {
        self.id = id
        self.model = model
        let scroll = NSTextView.scrollableTextView()
        textView = scroll.documentView as! NSTextView
        window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 240),
                         styleMask: [.titled, .closable, .resizable, .utilityWindow],
                         backing: .buffered, defer: false)
        super.init()
        let bg = NSColor(Color(hex: colorHex))
        textView.string = text
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .black
        textView.insertionPointColor = .black
        textView.backgroundColor = bg
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.delegate = self
        scroll.drawsBackground = true
        scroll.backgroundColor = bg
        window.contentView = scroll
        window.title = L("widget.stickynote")
        window.isFloatingPanel = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    func textDidChange(_ notification: Notification) {
        model.setOption(id, "text", textView.string)
    }

    func windowWillClose(_ notification: Notification) {
        StickyEditor.open[id] = nil
    }
}

struct StickyWidget: View {
    let size: Double
    let item: DockItem
    @EnvironmentObject var model: DockModel
    @Environment(\.dockVertical) private var vertical

    private var text: String { item.options?["text"] ?? "" }
    private var hex: String { item.options?["color"] ?? "#FFD60A" }

    var body: some View {
        WidgetCard(size: size, fill: Color(hex: hex).opacity(0.9)) {
            Text(text.isEmpty ? L("sticky.placeholder") : text)
                .font(.system(size: 10)).foregroundStyle(.black.opacity(text.isEmpty ? 0.5 : 0.85))
                .lineLimit(4).multilineTextAlignment(.leading)
                .frame(width: vertical ? nil : 110, alignment: .topLeading)
                .padding(.vertical, 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { StickyEditor.show(id: item.id, text: text, colorHex: hex, model: model) }
    }
}
