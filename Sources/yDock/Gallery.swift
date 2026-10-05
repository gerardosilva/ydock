import SwiftUI
import AppKit

// MARK: - Catalog (single source of truth for the "Add Widget" gallery)

struct WidgetSpec {
    let name: String
    let category: String      // key suffix of "cat.<category>"
    let symbol: String        // used by the static preview
    let live: Bool            // true: preview renders the real widget
    var label: String? = nil  // overrides the localized widget name (e.g. a specific shortcut)
}

enum WidgetCatalog {
    static let categories: [(key: String, symbol: String)] = [
        ("clocks", "clock"), ("calendar", "calendar"), ("reminders", "checklist"), ("notes", "note.text"),
        ("media", "play.rectangle"), ("system", "desktopcomputer"), ("weather", "cloud.sun"),
        ("photos", "photo.on.rectangle"), ("stocks", "chart.xyaxis.line"), ("tools", "wrench.and.screwdriver"),
    ]

    static let all: [WidgetSpec] = [
        .init(name: "clock", category: "clocks", symbol: "clock", live: true),
        .init(name: "worldclock", category: "clocks", symbol: "globe", live: true),
        .init(name: "stopwatch", category: "clocks", symbol: "stopwatch", live: true),
        .init(name: "focustimer", category: "clocks", symbol: "timer", live: true),
        .init(name: "alarm", category: "clocks", symbol: "alarm", live: true),
        .init(name: "timeprogress", category: "clocks", symbol: "chart.bar", live: true),
        .init(name: "countdown", category: "clocks", symbol: "hourglass", live: true),
        .init(name: "calendar", category: "calendar", symbol: "calendar", live: false),
        .init(name: "monthcalendar", category: "calendar", symbol: "calendar.badge.clock", live: true),
        .init(name: "reminders", category: "reminders", symbol: "checklist", live: false),
        .init(name: "stickynote", category: "notes", symbol: "note.text", live: true),
        .init(name: "notes", category: "notes", symbol: "note.text", live: false),
        .init(name: "photos", category: "photos", symbol: "photo.on.rectangle", live: false),
        .init(name: "batteries", category: "system", symbol: "battery.100", live: true),
        .init(name: "nowplaying", category: "media", symbol: "music.note", live: false),
        .init(name: "activity", category: "system", symbol: "gauge", live: true),
        .init(name: "cpu", category: "system", symbol: "cpu", live: true),
        .init(name: "memory", category: "system", symbol: "memorychip", live: true),
        .init(name: "network", category: "system", symbol: "network", live: true),
        .init(name: "battery", category: "system", symbol: "battery.75", live: true),
        .init(name: "weather", category: "weather", symbol: "cloud.sun", live: true),
        .init(name: "stock", category: "stocks", symbol: "chart.line.uptrend.xyaxis", live: true),
        .init(name: "dropdown", category: "tools", symbol: "folder", live: true),
        .init(name: "shortcut", category: "tools", symbol: "bolt.fill", live: true),
        .init(name: "airdrop", category: "tools", symbol: "airdrop", live: true),
        .init(name: "script", category: "tools", symbol: "terminal", live: true),
    ]

    /// Rough on-screen length of an item along the dock axis; used to decide when the dock must page.
    static func estimatedLength(_ item: DockItem, size: Double, vertical: Bool) -> Double {
        switch item.type {
        case "divider": return 1
        case "widget":
            let name = item.value ?? ""
            if vertical {
                switch name {
                case "activity": return 100
                case "worldclock": return 150
                case "stickynote": return 80
                case "network": return 60
                case "monthcalendar": return 70
                default: return max(size * 0.9, 56)
                }
            }
            switch name {
            case "worldclock": return 190
            case "stickynote": return 134
            case "timeprogress": return 134
            case "nowplaying": return 120
            case "focustimer": return 110
            case "calendar", "script", "reminders": return 100
            case "batteries": return 130
            case "monthcalendar": return size * 1.68 + 14
            case "photos": return size * 1.4
            case "alarm": return 118
            case "stopwatch": return 90
            default: return size * 1.4 + 12
            }
        default: return size + 8
        }
    }
}

/// A fresh widget item with sensible defaults (used when adding from the gallery or menus).
func makeWidgetItem(_ name: String, shortcuts: [String]) -> DockItem {
    var opts: [String: String]?
    var children: [DockItem]?
    switch name {
    case "weather": opts = ["lat": "19.43", "lon": "-99.13", "unit": "c"]
    case "script": opts = ["command": "date +%H:%M", "label": "Script", "interval": "30"]
    case "countdown":
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        opts = ["date": f.string(from: Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()),
                "label": L("widget.countdown")]
    case "stickynote": opts = ["text": "", "color": "#FFD60A"]
    case "worldclock": opts = ["zones": "America/Mexico_City,Europe/London,Asia/Tokyo"]
    case "stock": opts = ["symbol": "AAPL"]
    case "timeprogress": opts = ["unit": "year"]
    case "focustimer": opts = ["work": "25", "break": "5"]
    case "photos": opts = ["source": "recent", "minutes": "30"]
    case "alarm": opts = ["time": "", "enabled": "0", "repeat": "daily", "sound": "Glass"]
    case "shortcut": opts = ["name": shortcuts.first ?? "Shortcut", "icon": "bolt.fill"]
    case "dropdown":
        opts = ["title": L("widget.dropdown"), "icon": "folder"]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        children = ["Downloads", "Documents", "Desktop"].map { .init(type: "file", value: "\(home)/\($0)") }
    default: break
    }
    var item = DockItem(type: "widget", value: name, options: opts)
    item.children = children
    return item
}

// MARK: - Gallery UI

final class GalleryState: ObservableObject {
    @Published var query = ""
    @Published var category = "all"
    @Published var added = Set<String>()
}

struct GalleryView: View {
    @ObservedObject var model: DockModel
    let close: () -> Void
    @StateObject private var ui = GalleryState()

    private func title(_ s: WidgetSpec) -> String { s.label ?? L("widget.\(s.name)") }

    /// Catalog + one card per installed Shortcut + the separator.
    private var specs: [WidgetSpec] {
        var list = WidgetCatalog.all.filter { !($0.name == "shortcut" && !model.shortcuts.isEmpty) }
        list += model.shortcuts.map { WidgetSpec(name: "shortcut:\($0)", category: "tools", symbol: "bolt.fill", live: false, label: $0) }
        list.append(WidgetSpec(name: "divider", category: "tools", symbol: "rectangle.split.2x1", live: false, label: L("widget.divider")))
        return list
    }

    private func add(_ s: WidgetSpec) {
        if s.name == "divider" { model.addDivider() }
        else if s.name.hasPrefix("shortcut:") { model.addShortcut(String(s.name.dropFirst(9))) }
        else { model.addWidget(s.name) }
    }

    private func matches(_ s: WidgetSpec) -> Bool {
        let q = ui.query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || title(s).lowercased().contains(q) || s.name.contains(q)
    }

    private func sidebarRow(_ key: String, _ symbol: String, _ title: String) -> some View {
        let sel = ui.category == key
        return Button { ui.category = key } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).frame(width: 18)
                Text(title).font(.system(size: 13))
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(sel ? Color.primary.opacity(0.14) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func preview(_ s: WidgetSpec) -> some View {
        let item = makeWidgetItem(s.live ? s.name : "clock", shortcuts: model.shortcuts)
        let est = WidgetCatalog.estimatedLength(item, size: 48, vertical: false)
        return ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.07))
            if s.live {
                baseWidget(item, size: 48)
                    .fixedSize()
                    .scaleEffect(est > 150 ? 150 / est : 1)
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: s.symbol).font(.system(size: 22))
                    caption(title(s))
                }
            }
        }
        .frame(height: 76)
    }

    private func card(_ s: WidgetSpec) -> some View {
        let added = ui.added.contains(s.name)
        return VStack(alignment: .leading, spacing: 6) {
            preview(s)
            HStack {
                Text(title(s)).font(.system(size: 12)).lineLimit(1)
                Spacer()
                Button {
                    add(s)
                    ui.added.insert(s.name)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { ui.added.remove(s.name) }
                } label: {
                    Image(systemName: added ? "checkmark" : "plus").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(added ? Color.green : Color.secondary)
                        .frame(width: 24, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "square.grid.2x2")
                    Text(L("gallery.title")).font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 6)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("gallery.search"), text: Binding(get: { ui.query }, set: { ui.query = $0 }))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor.opacity(0.7), lineWidth: 1.5)))
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        sidebarRow("all", "square.grid.2x2", L("cat.all"))
                        ForEach(WidgetCatalog.categories, id: \.key) { sidebarRow($0.key, $0.symbol, L("cat.\($0.key)")) }
                    }
                }
            }
            .padding(16)
            .frame(width: 210)

            Divider()

            ZStack(alignment: .topTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        ForEach(WidgetCatalog.categories, id: \.key) { cat in
                            let specs = self.specs.filter { $0.category == cat.key && matches($0) }
                            if !specs.isEmpty && (ui.category == "all" || ui.category == cat.key) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(L("cat.\(cat.key)")).font(.system(size: 16, weight: .semibold))
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16, alignment: .top)],
                                              alignment: .leading, spacing: 16) {
                                        ForEach(specs, id: \.name) { card($0) }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24).padding(.vertical, 28)
                }
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(14)
            }
        }
        .frame(width: 800, height: 500)
        .background(
            RoundedRectangle(cornerRadius: 22).fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.18)))
        )
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .environment(\.colorScheme, model.config.appearance == .light ? .light : .dark)
        .environment(\.locale, Localizer.locale)
        .environmentObject(model)
    }
}

final class GalleryPresenter {
    static let shared = GalleryPresenter()
    private var panel: DetailPanel?

    func show(model: DockModel) {
        if let p = panel { p.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let host = NSHostingView(rootView: GalleryView(model: model, close: { [weak self] in self?.close() }))
        let p = DetailPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        p.contentView = host
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isMovableByWindowBackground = true
        p.isReleasedWhenClosed = false
        p.center()
        panel = p
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
