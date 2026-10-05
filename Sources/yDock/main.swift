import AppKit
import SwiftUI
import Combine

// Private WindowServer calls: let this (never-active) app change the mouse cursor while hovering its panel.
// Without it macOS ignores NSCursor.set() from a background app, so the resize cursor never shows.
@_silgen_name("CGSMainConnectionID") private func CGSMainConnectionID() -> Int32
@_silgen_name("CGSSetConnectionProperty")
private func CGSSetConnectionProperty(_ cid: Int32, _ target: Int32, _ key: CFString, _ value: CFTypeRef) -> Int32

func allowCursorChangesInBackground() {
    let cid = CGSMainConnectionID()
    _ = CGSSetConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
}

final class DockPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    // Allow parking the panel at the screen edge when auto-hidden.
    override func constrainFrameRect(_ r: NSRect, to s: NSScreen?) -> NSRect { r }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = DockModel()
    var panel: DockPanel!
    var host: NSHostingView<DockView>!
    var pill: DockPanel!
    var pillHost: NSHostingView<ProfilePill>!
    var statusItem: NSStatusItem!
    var bag = Set<AnyCancellable>()
    var shown = true
    var lastInside = Date()

    func applicationDidFinishLaunching(_ n: Notification) {
        allowCursorChangesInBackground()
        host = NSHostingView(rootView: DockView(model: model))
        panel = DockPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                          styleMask: [.borderless, .nonactivatingPanel],
                          backing: .buffered, defer: false)
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        ProfileActions.shared.model = model
        AlarmCenter.shared.model = model
        AlarmCenter.shared.start()
        DetailPresenter.shared.model = model
        DetailPresenter.shared.dockFrame = { [unowned self] in
            self.targetFrame(size: self.panel.frame.size, visible: true)
        }

        pillHost = NSHostingView(rootView: ProfilePill(model: model))
        pill = DockPanel(contentRect: NSRect(origin: .zero, size: pillHost.fittingSize),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        pill.contentView = pillHost
        pill.isOpaque = false
        pill.backgroundColor = .clear
        pill.hasShadow = false
        pill.level = .floating
        pill.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        refit()
        panel.orderFrontRegardless()

        // Re-fit after any config change (items added/removed, position switched…).
        model.$config.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
            for delay in [0.05, 0.3] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.refit() }
            }
        }.store(in: &bag)

        // Scroll wheel / trackpad swipe over an overflowing dock slides its items.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in self?.scroll(e); return e }
        NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel) { [weak self] e in self?.scroll(e) }

        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.model.reloadIfChanged() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.refit() }
        setupStatusItem()

        // Dev/test flags: open UI without clicking (e.g. `open yDock.app --args --gallery`).
        let args = CommandLine.arguments
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [self] in
            if args.contains("--gallery") { GalleryPresenter.shared.show(model: model) }
            if args.contains("--ring") { AlarmRingPanel.show(time: "07:30", label: "Test") { _ in } }
            if args.contains("--dock-settings") { DetailPresenter.shared.toggleDockSettings() }
            if let a = args.first(where: { $0.hasPrefix("--detail=") }),
               let item = model.config.items.first(where: { $0.value == String(a.dropFirst(9)) }) {
                DetailPresenter.shared.toggleDetail(for: item)
            }
        }
    }

    // MARK: scrolling an overflowing dock

    private var lastStep = Date.distantPast

    func scroll(_ e: NSEvent) {
        let s = ScrollState.shared
        guard s.maxOffset > 0, panel.frame.contains(NSEvent.mouseLocation) else { return }
        let vertical = model.config.position.vertical
        let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
        // Swipe left / up moves the content toward the start, like any scroll view.
        let delta = abs(dx) > abs(dy) ? -dx : -dy
        if e.hasPreciseScrollingDeltas {
            _ = vertical
            s.scrollBy(Double(delta))
        } else if abs(delta) > 0, Date().timeIntervalSince(lastStep) > 0.12 {   // classic wheel: one item per notch
            s.step(delta > 0 ? 1 : -1)
            lastStep = Date()
        }
    }

    // MARK: geometry

    func targetFrame(size: NSSize, visible: Bool) -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame, v = screen.visibleFrame
        let m: CGFloat = 4, w = size.width, h = size.height
        var o = NSPoint.zero
        switch model.config.position {
        case .bottom:
            o = NSPoint(x: f.midX - w / 2, y: visible ? f.minY + m : f.minY - h + 1)
        case .aboveSystemDock:
            o = NSPoint(x: v.midX - w / 2, y: visible ? v.minY + m : f.minY - h + 1)
        case .top:
            o = NSPoint(x: v.midX - w / 2, y: visible ? v.maxY - h : f.maxY - 1)   // notch: flush under the menu bar
        case .left:
            o = NSPoint(x: visible ? v.minX + m : f.minX - w + 1, y: v.midY - h / 2)
        case .right:
            o = NSPoint(x: visible ? v.maxX - w - m : f.maxX - 1, y: v.midY - h / 2)
        }
        return NSRect(origin: o, size: size)
    }

    func refit() {
        let visible = shown || !model.config.autoHide
        panel.setFrame(targetFrame(size: host.fittingSize, visible: visible), display: true)
        layoutPill()
    }

    /// The profile pill sits just outside the dock (only when there is more than one profile).
    func layoutPill() {
        guard model.config.profiles.count > 1, model.config.showProfilePill, shown || !model.config.autoHide else { pill.orderOut(nil); return }
        let s = pillHost.fittingSize
        pill.setContentSize(s)
        let d = panel.frame
        var o = NSPoint.zero
        switch model.config.position {
        case .bottom, .aboveSystemDock: o = NSPoint(x: d.midX - s.width / 2, y: d.maxY - 2)
        case .top: o = NSPoint(x: d.midX - s.width / 2, y: d.minY - s.height + 2)
        case .left: o = NSPoint(x: d.maxX - 2, y: d.maxY - s.height - 10)
        case .right: o = NSPoint(x: d.minX - s.width + 2, y: d.maxY - s.height - 10)
        }
        pill.setFrameOrigin(o)
        pill.orderFrontRegardless()
    }

    func setShown(_ v: Bool) {
        shown = v
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().setFrame(targetFrame(size: panel.frame.size, visible: v), display: true)
        } completionHandler: { [weak self] in self?.layoutPill() }
        if !v { pill.orderOut(nil) }
    }

    // MARK: auto-hide

    func tick() {
        guard model.config.autoHide else {
            if !shown { setShown(true) }
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let f = screen.frame
        let pf = targetFrame(size: panel.frame.size, visible: true)
        let inside = pf.insetBy(dx: -8, dy: -8).contains(mouse) || model.dragging != nil
            || DetailPresenter.shared.isOpen || (pill.isVisible && pill.frame.contains(mouse))
        let spanX = (pf.minX - 30)...(pf.maxX + 30), spanY = (pf.minY - 30)...(pf.maxY + 30)
        let trigger: Bool
        switch model.config.position {
        case .bottom, .aboveSystemDock: trigger = mouse.y <= f.minY + 2 && spanX.contains(mouse.x)
        case .top: trigger = mouse.y >= f.maxY - 2 && spanX.contains(mouse.x)
        case .left: trigger = mouse.x <= f.minX + 2 && spanY.contains(mouse.y)
        case .right: trigger = mouse.x >= f.maxX - 2 && spanY.contains(mouse.y)
        }
        if shown {
            if inside { lastInside = Date() }
            else if Date().timeIntervalSince(lastInside) > 0.5 { setShown(false) }
        } else if trigger {
            lastInside = Date()
            setShown(true)
        }
    }

    // MARK: menu bar item

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: "yDock")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        add(menu, L("menu.addwidget") + "…", #selector(openGallery))
        let pm = NSMenuItem(title: L("menu.profiles"), action: nil, keyEquivalent: "")
        pm.submenu = ProfileActions.shared.menu()
        menu.addItem(pm)
        add(menu, L("menu.settings"), #selector(openDockSettings))
        menu.addItem(.separator())
        add(menu, L("menu.quit"), #selector(quit))
    }

    private func add(_ menu: NSMenu, _ title: String, _ sel: Selector) {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        i.target = self
        menu.addItem(i)
    }

    @objc func openGallery() { GalleryPresenter.shared.show(model: model) }
    @objc func openDockSettings() { DetailPresenter.shared.toggleDockSettings() }
    @objc func quit() { NSApp.terminate(nil) }
}

// Single instance (launchd + manual `open` would otherwise stack two docks).
if let id = Bundle.main.bundleIdentifier,
   NSRunningApplication.runningApplications(withBundleIdentifier: id).count > 1 { exit(0) }

LegacyMigration.run()

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
