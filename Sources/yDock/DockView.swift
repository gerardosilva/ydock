import SwiftUI
import AppKit
import UniformTypeIdentifiers

final class RunningApps: ObservableObject {
    @Published var ids = Set<String>()
    init() {
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        for n in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
    }
    func refresh() {
        ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

final class HoverState: ObservableObject { @Published var on = false }

struct FileButton: View {
    let item: DockItem
    let size: Double
    @EnvironmentObject var running: RunningApps
    @EnvironmentObject var model: DockModel
    @StateObject private var hoverState = HoverState()

    private var path: String { item.value ?? "" }
    private var isApp: Bool { item.type == "app" }
    private var bundleID: String? { isApp ? Bundle(path: path)?.bundleIdentifier : nil }
    private var isRunning: Bool { bundleID.map(running.ids.contains) ?? false }

    var body: some View {
        VStack(spacing: 2) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable().frame(width: size, height: size)
                .scaleEffect(hoverState.on && model.config.hoverZoom ? 1.2 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hoverState.on)
            Circle().fill(Color.primary.opacity(isRunning && model.config.showIndicators ? 0.8 : 0)).frame(width: 4, height: 4)
        }
        .contentShape(Rectangle())
        .onHover { hoverState.on = $0 }
        .onTapGesture { launch() }
        .help(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
    }

    private func launch() {
        let url = URL(fileURLWithPath: path)
        if let id = bundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == id }) {
            app.activate(options: [.activateAllWindows])
        } else if isApp {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}

struct ReorderDelegate: DropDelegate {
    let item: DockItem
    let model: DockModel
    func validateDrop(info: DropInfo) -> Bool { model.dragging != nil }
    func dropEntered(info: DropInfo) {
        guard let d = model.dragging, d != item.id else { return }
        withAnimation(.easeInOut(duration: 0.2)) { model.move(d, before: item.id) }
    }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool { model.dragging = nil; return true }
}

/// Scroll position of an overflowing dock. Items glide one by one (arrows / mouse wheel) or follow the trackpad
/// continuously and then settle on the nearest item.
final class ScrollState: ObservableObject {
    static let shared = ScrollState()
    @Published var offset: CGFloat = 0
    private(set) var starts: [Double] = []
    private(set) var maxOffset = 0.0
    private var snapTimer: Timer?

    func configure(starts: [Double], maxOffset: Double) { self.starts = starts; self.maxOffset = maxOffset }

    func step(_ dir: Int) {
        let cur = min(Double(offset), maxOffset)
        let target = dir > 0 ? (starts.first { $0 > cur + 1 } ?? maxOffset) : (starts.last { $0 < cur - 1 } ?? 0)
        go(to: min(target, maxOffset))
    }

    func go(to t: Double) {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { offset = CGFloat(max(0, t)) }
    }

    func scrollBy(_ px: Double) {
        offset = CGFloat(min(max(Double(offset) + px, 0), maxOffset))
        snapTimer?.invalidate()
        snapTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: false) { [weak self] _ in self?.snap() }
    }

    private func snap() {
        let cur = Double(offset)
        let stops = (starts + [maxOffset]).filter { $0 <= maxOffset + 0.5 }
        if let t = stops.min(by: { abs($0 - cur) < abs($1 - cur) }) { go(to: t) }
    }
}

/// Real on-screen lengths of items (learned after they render), so pagination stops relying on guesses.
final class LengthStore: ObservableObject {
    static let shared = LengthStore()
    @Published var lengths: [String: Double] = [:]
    func merge(_ new: [String: Double]) {
        var next = lengths
        for (k, v) in new where abs((next[k] ?? -10) - v) > 1 { next[k] = v }
        if next != lengths { lengths = next }
    }
}

struct ItemLengthKey: PreferenceKey {
    static var defaultValue: [String: Double] = [:]
    static func reduce(value: inout [String: Double], nextValue: () -> [String: Double]) { value.merge(nextValue()) { $1 } }
}



final class ResizeDragState: ObservableObject {
    var start: NSPoint?
    var startSize = 48.0
    var pushed = false
}

/// Sets a cursor while the mouse is over the view, even though the dock panel is never the active window
/// (plain cursor rects / NSCursor.push are ignored in that case; `.activeAlways` tracking areas are not).
struct CursorArea: NSViewRepresentable {
    let cursor: NSCursor

    final class TrackingView: NSView {
        var cursor: NSCursor = .arrow
        private var reassert: Timer?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never swallow clicks
        override func updateTrackingAreas() {
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.activeAlways, .inVisibleRect, .cursorUpdate, .mouseEnteredAndExited, .mouseMoved],
                                           owner: self, userInfo: nil))
            super.updateTrackingAreas()
        }
        override func cursorUpdate(with event: NSEvent) { cursor.set() }
        override func mouseMoved(with event: NSEvent) { cursor.set() }
        override func mouseEntered(with event: NSEvent) {
            cursor.set()
            // The app is not active, so the system keeps resetting the cursor; re-assert it while hovering.
            reassert?.invalidate()
            let t = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in self?.cursor.set() }
            RunLoop.main.add(t, forMode: .common)
            reassert = t
        }
        override func mouseExited(with event: NSEvent) {
            reassert?.invalidate()
            reassert = nil
            NSCursor.arrow.set()
        }
        deinit { reassert?.invalidate() }
    }

    func makeNSView(context: Context) -> TrackingView { let v = TrackingView(); v.cursor = cursor; return v }
    func updateNSView(_ v: TrackingView, context: Context) { v.cursor = cursor }
}

final class HandleHover: ObservableObject { @Published var on = false }

/// Grabber at the end of the dock: drag to make the dock smaller / bigger, double-click to reset.
/// On hover it grows and the cursor turns into a resize arrow, so it reads as draggable.
struct ResizeHandle: View {
    @ObservedObject var model: DockModel
    let vertical: Bool
    @StateObject private var drag = ResizeDragState()
    @StateObject private var hover = HandleHover()

    var body: some View {
        let active = hover.on || drag.start != nil
        Capsule().fill(Color.primary.opacity(active ? 0.9 : 0.4))
            .frame(width: vertical ? (active ? 30 : 22) : (active ? 5 : 3),
                   height: vertical ? (active ? 5 : 3) : (active ? 30 : 22))
            .animation(.easeOut(duration: 0.15), value: active)
            .padding(vertical ? .vertical : .horizontal, 5)
            .contentShape(Rectangle())
            .overlay(CursorArea(cursor: vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight))
            .onHover { hover.on = $0 }
            .onTapGesture(count: 2) { model.config.iconSize = 48; model.save() }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { _ in
                        // Absolute screen coordinates: the dock re-centers while resizing, which would skew local translations.
                        let m = NSEvent.mouseLocation
                        if drag.start == nil { drag.start = m; drag.startSize = model.config.iconSize; hover.on = true }
                        guard let s = drag.start else { return }
                        let delta = vertical ? (s.y - m.y) : (m.x - s.x)
                        model.config.iconSize = min(max((drag.startSize + delta * 0.25).rounded(), 28), 96)
                    }
                    .onEnded { _ in drag.start = nil; model.save() }
            )
            .help(L("handle.hint"))
    }
}

struct DockMetrics {
    let vertical: Bool
    let spacing: Double
    let viewport: Double
    let overflow: Bool
    let maxOffset: Double
    let starts: [Double]
}

struct DockView: View {
    @ObservedObject var model: DockModel
    @StateObject private var running = RunningApps()
    @ObservedObject private var scroller = ScrollState.shared
    @ObservedObject private var lengths = LengthStore.shared

    private func metrics(_ cfg: DockConfig) -> DockMetrics {
        let vertical = cfg.position.vertical
        let spacing = vertical ? max(2, cfg.spacing * 0.6) : cfg.spacing
        let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let limit = (vertical ? screen.height : screen.width) - 160
        var starts: [Double] = []
        var acc = 0.0
        for it in cfg.items {
            starts.append(acc)
            acc += (lengths.lengths[it.id.uuidString] ?? WidgetCatalog.estimatedLength(it, size: cfg.iconSize, vertical: vertical)) + spacing
        }
        let total = max(acc - spacing, 0)
        let overflow = total > limit - 70
        let viewport = limit - 130
        return DockMetrics(vertical: vertical, spacing: spacing, viewport: viewport, overflow: overflow,
                           maxOffset: overflow ? max(0, total - viewport) : 0, starts: starts)
    }

    @ViewBuilder
    private func itemsList(_ cfg: DockConfig, _ vertical: Bool) -> some View {
        ForEach(cfg.items) { item in
            itemView(item, cfg: cfg)
                .id(item.renderKey)
                .background(GeometryReader { g in
                    Color.clear.preference(key: ItemLengthKey.self,
                                           value: [item.id.uuidString: Double(vertical ? g.size.height : g.size.width)])
                })
                .onDrag {
                    model.dragging = item.id
                    return NSItemProvider(object: item.id.uuidString as NSString)
                }
                .onDrop(of: [.plainText], delegate: ReorderDelegate(item: item, model: model))
                .contextMenu {
                    if item.type != "widget" && item.type != "divider" {
                        Button(L("item.reveal")) {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.value ?? "")])
                        }
                    }
                    if item.type == "widget" && !settingFields(for: item.value ?? "").isEmpty {
                        Button(L("menu.widgetsettings")) { DetailPresenter.shared.openSettings(for: item) }
                    }
                    if item.value == "dropdown" {
                        Button(L("menu.dropdownadd")) { model.pickChildren(for: item.id) }
                    }
                    Button(L("item.remove")) { withAnimation { model.remove(item.id) } }
                }
        }
    }

    /// Soft fade on whichever edge still has hidden items.
    private func fade(_ vertical: Bool, atStart: Bool, atEnd: Bool) -> some View {
        LinearGradient(stops: [
            .init(color: atStart ? .black : .clear, location: 0),
            .init(color: .black, location: 0.07),
            .init(color: .black, location: 0.93),
            .init(color: atEnd ? .black : .clear, location: 1),
        ], startPoint: vertical ? .top : .leading, endPoint: vertical ? .bottom : .trailing)
    }

    var body: some View {
        let cfg = model.config
        let m = metrics(cfg)
        let vertical = m.vertical
        let off = min(Double(scroller.offset), m.maxOffset)
        let layout = vertical
            ? AnyLayout(VStackLayout(spacing: m.spacing)) : AnyLayout(HStackLayout(spacing: m.spacing))

        layout {
            if m.overflow {
                arrowButton(off > 1, vertical ? "chevron.up" : "chevron.left") { scroller.step(-1) }
                layout { itemsList(cfg, vertical) }
                    .fixedSize()
                    .offset(x: vertical ? 0 : CGFloat(-off), y: vertical ? CGFloat(-off) : 0)
                    .frame(width: vertical ? nil : m.viewport, height: vertical ? m.viewport : nil,
                           alignment: vertical ? .top : .leading)
                    .clipped()
                    .mask(fade(vertical, atStart: off <= 1, atEnd: off >= m.maxOffset - 1))
                arrowButton(off < m.maxOffset - 1, vertical ? "chevron.down" : "chevron.right") { scroller.step(1) }
            } else {
                itemsList(cfg, vertical)
            }
            if cfg.showHandle { ResizeHandle(model: model, vertical: vertical) }
        }
        .onPreferenceChange(ItemLengthKey.self) { LengthStore.shared.merge($0) }
        .onAppear { scroller.configure(starts: m.starts, maxOffset: m.maxOffset) }
        .onChange(of: "\(Int(m.maxOffset))|\(m.starts.count)|\(Int(m.starts.last ?? 0))") { _ in
            scroller.configure(starts: m.starts, maxOffset: m.maxOffset)
        }
        .padding(.horizontal, vertical ? 6 : 14)
        .padding(.vertical, vertical ? 10 : 8)
        .background(
            RoundedRectangle(cornerRadius: cfg.cornerRadius).fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: cfg.cornerRadius)
                    .fill(Color(hex: cfg.tint).opacity(cfg.appearance == .tinted ? 0.45 : 0)))
                .overlay(RoundedRectangle(cornerRadius: cfg.cornerRadius).stroke(Color.primary.opacity(0.2)))
        )
        .padding(6)
        .environment(\.dockVertical, vertical)
        .environment(\.locale, Localizer.locale)
        .environment(\.colorScheme, cfg.appearance == .light ? .light : .dark)
        .environmentObject(running)
        .environmentObject(model)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { model.add(url: url) }
                }
            }
            return true
        }
        .contextMenu { dockMenu }
        .fixedSize()
    }

    private func arrowButton(_ enabled: Bool, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                .frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 0.9 : 0.25)
        .disabled(!enabled)
    }

    @ViewBuilder
    private func itemView(_ item: DockItem, cfg: DockConfig) -> some View {
        switch item.type {
        case "app", "file": FileButton(item: item, size: cfg.iconSize)
        case "widget": widgetView(item, size: cfg.iconSize)
        case "divider":
            Rectangle().fill(Color.primary.opacity(0.25))
                .frame(width: cfg.position.vertical ? cfg.iconSize * 0.6 : 1,
                       height: cfg.position.vertical ? 1 : cfg.iconSize * 0.8)
        default: EmptyView()
        }
    }

    /// Right-click menu on the dock: everything configurable lives in Settings.
    @ViewBuilder
    private var dockMenu: some View {
        Button(L("menu.addwidget") + "…") { GalleryPresenter.shared.show(model: model) }
        Menu(L("menu.profiles")) {
            ForEach(model.config.profiles) { p in
                Button { model.setActiveProfile(p.id) } label: {
                    if p.id == model.config.activeProfile { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                }
            }
        }
        Button(L("menu.settings")) { DetailPresenter.shared.toggleDockSettings() }
        Divider()
        Button(L("menu.quit")) { NSApp.terminate(nil) }
    }
}

extension Color {
    /// "#RRGGBB" -> Color (falls back to system blue).
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { self = .blue; return }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
