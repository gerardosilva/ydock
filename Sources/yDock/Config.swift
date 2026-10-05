import AppKit

enum DockPosition: String, Codable, CaseIterable {
    case bottom, aboveSystemDock, top, left, right

    var title: String {
        switch self {
        case .bottom: return L("pos.bottom")
        case .aboveSystemDock: return L("pos.above")
        case .top: return L("pos.top")
        case .left: return L("pos.left")
        case .right: return L("pos.right")
        }
    }
    var vertical: Bool { self == .left || self == .right }
}

enum DockAppearance: String, Codable, CaseIterable {
    case dark, light, tinted
    var title: String {
        switch self {
        case .dark: return L("app.dark")
        case .light: return L("app.light")
        case .tinted: return L("app.tinted")
        }
    }
}

struct DockItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var type: String            // "app" | "file" | "widget" | "divider"
    var value: String?          // path or widget name
    var options: [String: String]?
    var children: [DockItem]?    // dropdown entries ("app" | "file" | "link")

    enum CodingKeys: String, CodingKey { case type, value, options, children }
}

struct DockProfile: Codable, Identifiable {
    var id = UUID()
    var name: String
    var items: [DockItem]
}

extension DockItem {
    /// Changes whenever the widget's options change, so SwiftUI rebuilds the widget with the new settings.
    var renderKey: String {
        "\(id)|" + (options ?? [:]).sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
            + "|\(children?.count ?? 0)"
    }
}

struct DockConfig: Codable {
    var profiles: [DockProfile]
    var activeProfile: UUID
    var iconSize: Double = 48
    var position: DockPosition = .bottom
    var autoHide: Bool = false
    var appearance: DockAppearance = .dark
    var language: String = "system"   // "system" or one of Localizer.supported
    var tint: String = "#0A84FF"     // used by the "tinted" appearance
    var hoverZoom = true             // magnify app icons under the cursor
    var showIndicators = true        // dot under running apps
    var showHandle = true            // resize grabber at the end of the dock
    var showProfilePill = true       // profile switcher next to the dock (when 2+ profiles)
    var spacing: Double = 10         // gap between items
    var cornerRadius: Double = 22

    var activeIndex: Int { profiles.firstIndex { $0.id == activeProfile } ?? 0 }

    /// Items of the active profile.
    var items: [DockItem] {
        get { profiles[activeIndex].items }
        set { profiles[activeIndex].items = newValue }
    }

    init(items: [DockItem]) {
        let p = DockProfile(name: "Default", items: items)
        profiles = [p]
        activeProfile = p.id
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        if let p = try c.decodeIfPresent([DockProfile].self, forKey: .profiles), !p.isEmpty {
            profiles = p
            activeProfile = try c.decodeIfPresent(UUID.self, forKey: .activeProfile) ?? p[0].id
        } else {   // legacy config: a single "items" list
            let legacy = DockProfile(name: "Default", items: try c.decode([DockItem].self, forKey: .items))
            profiles = [legacy]
            activeProfile = legacy.id
        }
        iconSize = try c.decodeIfPresent(Double.self, forKey: .iconSize) ?? 48
        position = try c.decodeIfPresent(DockPosition.self, forKey: .position) ?? .bottom
        autoHide = try c.decodeIfPresent(Bool.self, forKey: .autoHide) ?? false
        appearance = try c.decodeIfPresent(DockAppearance.self, forKey: .appearance) ?? .dark
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "system"
        tint = try c.decodeIfPresent(String.self, forKey: .tint) ?? "#0A84FF"
        hoverZoom = try c.decodeIfPresent(Bool.self, forKey: .hoverZoom) ?? true
        showIndicators = try c.decodeIfPresent(Bool.self, forKey: .showIndicators) ?? true
        showHandle = try c.decodeIfPresent(Bool.self, forKey: .showHandle) ?? true
        showProfilePill = try c.decodeIfPresent(Bool.self, forKey: .showProfilePill) ?? true
        spacing = try c.decodeIfPresent(Double.self, forKey: .spacing) ?? 10
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 22
    }
    enum Keys: String, CodingKey { case items, profiles, activeProfile, iconSize, position, autoHide, appearance, tint, language, hoverZoom, showIndicators, showHandle, showProfilePill, spacing, cornerRadius }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ydock/config.json")

    static let defaults = DockConfig(items: [
        .init(type: "app", value: "/System/Library/CoreServices/Finder.app"),
        .init(type: "app", value: "/Applications/Safari.app"),
        .init(type: "app", value: "/System/Applications/Messages.app"),
        .init(type: "app", value: "/System/Applications/Calendar.app"),
        .init(type: "app", value: "/System/Applications/Notes.app"),
        .init(type: "app", value: "/System/Applications/System Settings.app"),
        .init(type: "divider"),
        .init(type: "widget", value: "clock"),
        .init(type: "widget", value: "battery"),
        .init(type: "widget", value: "cpu"),
        .init(type: "widget", value: "memory"),
        .init(type: "widget", value: "weather", options: ["lat": "19.43", "lon": "-99.13", "unit": "c"]),
    ])

    static func read() -> DockConfig? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DockConfig.self, from: data)
    }
}

/// Source of truth for the dock; saves to disk on every mutation and
/// picks up external edits of config.json.
final class DockModel: ObservableObject {
    @Published var config: DockConfig { didSet { Localizer.update(preference: config.language) } }
    var dragging: UUID?
    private var lastMTime: Date?

    static let widgetNames = WidgetCatalog.all.map(\.name)
    @Published var shortcuts: [String] = []

    init() {
        config = DockConfig.defaults
        if let c = DockConfig.read() {
            config = c
            lastMTime = mtime()
        } else {
            save()
        }
        Localizer.update(preference: config.language)
        loadShortcuts()
    }

    func loadShortcuts() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let names = listShortcuts()
            DispatchQueue.main.async { self?.shortcuts = names }
        }
    }

    private func mtime() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: DockConfig.url.path))?[.modificationDate] as? Date
    }

    func save() {
        try? FileManager.default.createDirectory(at: DockConfig.url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? enc.encode(config).write(to: DockConfig.url)
        lastMTime = mtime()
    }

    func reload() {
        loadShortcuts()
        lastMTime = mtime()
        if let c = DockConfig.read() { config = c }   // keep current config if the file is mid-edit/invalid
    }

    func reloadIfChanged() {
        if mtime() != lastMTime { reload() }
    }

    // MARK: mutations

    func add(url: URL) {
        let isApp = url.pathExtension == "app"
        config.items.append(.init(type: isApp ? "app" : "file", value: url.path))
        save()
    }

    func addWidget(_ name: String) {
        config.items.append(makeWidgetItem(name, shortcuts: shortcuts))
        save()
    }

    func addShortcut(_ name: String) {
        config.items.append(.init(type: "widget", value: "shortcut", options: ["name": name, "icon": "bolt.fill"]))
        save()
    }

    func setOption(_ id: UUID, _ key: String, _ value: String) { setOptions(id, [key: value]) }

    /// Sets several options on a widget in any profile (alarms must keep working while another profile is active).
    func setOptions(_ id: UUID, _ values: [String: String]) {
        for pi in config.profiles.indices {
            if let ii = config.profiles[pi].items.firstIndex(where: { $0.id == id }) {
                var o = config.profiles[pi].items[ii].options ?? [:]
                for (k, v) in values { o[k] = v }
                config.profiles[pi].items[ii].options = o
                save()
                return
            }
        }
    }

    /// Lets the user pick files/folders/apps to add into a dropdown widget.
    func pickChildren(for id: UUID) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK,
              let i = config.items.firstIndex(where: { $0.id == id }) else { return }
        var kids = config.items[i].children ?? []
        kids += panel.urls.map { .init(type: $0.pathExtension == "app" ? "app" : "file", value: $0.path) }
        config.items[i].children = kids
        save()
    }

    func addDivider() { config.items.append(.init(type: "divider")); save() }

    func remove(_ id: UUID) { config.items.removeAll { $0.id == id }; save() }

    func move(_ id: UUID, before target: UUID) {
        guard let from = config.items.firstIndex(where: { $0.id == id }),
              let to = config.items.firstIndex(where: { $0.id == target }), from != to else { return }
        config.items.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        save()
    }

    func setPosition(_ p: DockPosition) { config.position = p; save() }
    private lazy var tintPicker = TintPicker(model: self)

    /// Opens the system color panel; changes apply live and switch the dock to "tinted".
    func pickTint() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        if let v = UInt32(config.tint.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) {
            panel.color = NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                                  blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        }
        panel.setTarget(tintPicker)
        panel.setAction(#selector(TintPicker.changed(_:)))
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if config.appearance != .tinted { setAppearance(.tinted) }
    }

    /// Mutate the config and persist it.
    func update(_ change: (inout DockConfig) -> Void) { change(&config); save() }

    func setLanguage(_ code: String) { config.language = code; save() }
    func setActiveProfile(_ id: UUID) { config.activeProfile = id; save() }

    func addProfile(name: String) {
        let items = config.items.map { i -> DockItem in var n = i; n.id = UUID(); return n }
        let p = DockProfile(name: name, items: items)
        config.profiles.append(p)
        config.activeProfile = p.id
        save()
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let i = config.profiles.firstIndex(where: { $0.id == id }) else { return }
        config.profiles[i].name = name
        save()
    }

    func deleteProfile(_ id: UUID) {
        guard config.profiles.count > 1 else { return }
        config.profiles.removeAll { $0.id == id }
        if !config.profiles.contains(where: { $0.id == config.activeProfile }) { config.activeProfile = config.profiles[0].id }
        save()
    }

    func setAppearance(_ a: DockAppearance) { config.appearance = a; save() }
    func toggleAutoHide() { config.autoHide.toggle(); save() }
}

final class TintPicker: NSObject {
    private unowned let model: DockModel
    init(model: DockModel) { self.model = model }

    @objc func changed(_ sender: NSColorPanel) {
        guard let rgb = sender.color.usingColorSpace(.sRGB) else { return }
        let hex = String(format: "#%02X%02X%02X", Int((rgb.redComponent * 255).rounded()),
                         Int((rgb.greenComponent * 255).rounded()), Int((rgb.blueComponent * 255).rounded()))
        guard hex != model.config.tint else { return }
        model.config.tint = hex
        model.save()
    }
}
