import SwiftUI
import AppKit

/// Text prompt used for naming profiles.
enum Prompt {
    static func text(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: L("common.ok"))
        alert.addButton(withTitle: L("common.cancel"))
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let s = field.stringValue.trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }
}

/// Builds/handles the profile menu (used by the pill above the dock and the menu-bar item).
final class ProfileActions: NSObject {
    static let shared = ProfileActions()
    weak var model: DockModel?

    func menu() -> NSMenu {
        let menu = NSMenu()
        guard let model else { return menu }
        for p in model.config.profiles {
            let i = NSMenuItem(title: p.name, action: #selector(pick(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = p.id.uuidString
            i.state = p.id == model.config.activeProfile ? .on : .off
            menu.addItem(i)
        }
        menu.addItem(.separator())
        for (title, sel) in [(L("profile.new"), #selector(newProfile)), (L("profile.rename"), #selector(renameProfile))] {
            let i = NSMenuItem(title: title, action: sel, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        if model.config.profiles.count > 1 {
            let i = NSMenuItem(title: L("profile.delete"), action: #selector(deleteProfile), keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        return menu
    }

    @objc func pick(_ s: NSMenuItem) {
        if let raw = s.representedObject as? String, let id = UUID(uuidString: raw) { model?.setActiveProfile(id) }
    }

    @objc func newProfile() {
        // Deferred so a menu that triggered us has finished closing.
        DispatchQueue.main.async { [weak self] in
            if let name = Prompt.text(title: L("profile.name"), initial: "") { self?.model?.addProfile(name: name) }
        }
    }

    @objc func renameProfile() {
        DispatchQueue.main.async { [weak self] in
            guard let m = self?.model else { return }
            let cur = m.config.profiles[m.config.activeIndex]
            if let name = Prompt.text(title: L("profile.name"), initial: cur.name) { m.renameProfile(cur.id, to: name) }
        }
    }

    @objc func deleteProfile() {
        guard let m = model else { return }
        m.deleteProfile(m.config.activeProfile)
    }
}

/// Small pill shown next to the dock with the active profile's name; click for the profile menu.
struct ProfilePill: View {
    @ObservedObject var model: DockModel
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle.grid.3x3.fill").font(.system(size: 10))
            Text(model.config.profiles[model.config.activeIndex].name).font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(
            Capsule().fill(.ultraThinMaterial)
                .overlay(Capsule().fill(Color(hex: model.config.tint).opacity(model.config.appearance == .tinted ? 0.4 : 0)))
                .overlay(Capsule().stroke(Color.primary.opacity(0.18)))
        )
        .padding(4)
        .contentShape(Rectangle())
        .onTapGesture { ProfileActions.shared.menu().popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
        .environment(\.colorScheme, model.config.appearance == .light ? .light : .dark)
        .fixedSize()
    }
}
