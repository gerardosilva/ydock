import SwiftUI
import AppKit
import Photos
import IOKit.ps

private func runCommand(_ path: String, _ args: [String]) -> String {
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

// MARK: - Notes (recent notes from Notes.app via AppleScript; only queried while Notes is running)

final class NotesMonitor: ObservableObject {
    static let shared = NotesMonitor()
    @Published var titles: [String] = []
    @Published var total = 0
    @Published var running = false
    private let queue = DispatchQueue(label: "ydock.notes")
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let isRunning = NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.apple.Notes" }
        running = isRunning
        guard isRunning else { return }   // never launch Notes just to peek
        queue.async { [weak self] in
            let src = """
            tell application "Notes"
                set c to count of notes
                set out to (c as text)
                set n to c
                if n > 6 then set n to 6
                repeat with i from 1 to n
                    set out to out & linefeed & (name of note i)
                end repeat
                return out
            end tell
            """
            var err: NSDictionary?
            guard let s = NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue else { return }
            let lines = s.components(separatedBy: "\n")
            DispatchQueue.main.async {
                self?.total = Int(lines.first ?? "") ?? 0
                self?.titles = Array(lines.dropFirst())
            }
        }
    }
}

struct NotesWidget: View {
    let size: Double
    @ObservedObject private var mon = NotesMonitor.shared
    var body: some View {
        WidgetCard(size: size) {
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "note.text").foregroundStyle(.yellow).font(.system(size: 13))
                    Text("\(mon.total)").font(.system(size: 16, weight: .semibold, design: .rounded))
                }
                caption(mon.titles.first ?? L("notes.open")).frame(maxWidth: 90)
            }
            .foregroundStyle(.primary)
        }
    }
}

struct NotesDetail: View {
    @ObservedObject private var mon = NotesMonitor.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(mon.titles.enumerated()), id: \.offset) { _, t in
                HStack(spacing: 8) {
                    Image(systemName: "note.text").font(.system(size: 11)).foregroundStyle(.yellow)
                    Text(t).font(.system(size: 12)).lineLimit(1)
                }
            }
            if mon.titles.isEmpty {
                Text(mon.running ? L("rem.empty") : L("notes.open")).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider()
            Button(L("notes.open")) { openApp("/System/Applications/Notes.app") }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { mon.refresh() }
    }
}

// MARK: - Photos (random photo from your library; asks for Photos access). options: source = recent|favorites, minutes

final class PhotosMonitor: ObservableObject {
    @Published var image: NSImage?
    @Published var denied = false
    private let source: String
    private var assets: [PHAsset] = []
    private var timer: Timer?

    init(source: String, minutes: Double) {
        self.source = source
        // Only ask when macOS has never been asked; otherwise just use the saved decision.
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
                DispatchQueue.main.async { self?.apply(status) }
            }
        } else {
            apply(current)
        }
        timer = Timer.scheduledTimer(withTimeInterval: max(minutes, 1) * 60, repeats: true) { [weak self] _ in self?.next() }
    }

    private func apply(_ status: PHAuthorizationStatus) {
        if status == .authorized || status == .limited { loadAssets(); next() }
        else { denied = true }
    }

    private func loadAssets() {
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = 200
        if source == "favorites" { o.predicate = NSPredicate(format: "favorite == YES") }
        var list: [PHAsset] = []
        PHAsset.fetchAssets(with: .image, options: o).enumerateObjects { a, _, _ in list.append(a) }
        assets = list
    }

    func next() {
        guard let a = assets.randomElement() else { return }
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .opportunistic
        opts.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 400, height: 400),
                                              contentMode: .aspectFill, options: opts) { [weak self] img, _ in
            if let img { DispatchQueue.main.async { self?.image = img } }
        }
    }
}

struct PhotosWidget: View {
    let size: Double
    @Environment(\.dockVertical) private var vertical
    @StateObject private var mon: PhotosMonitor

    init(size: Double, options: [String: String]) {
        self.size = size
        _mon = StateObject(wrappedValue: PhotosMonitor(source: options["source"] ?? "recent",
                                                       minutes: Double(options["minutes"] ?? "") ?? 30))
    }

    var body: some View {
        let w = vertical ? size * 1.15 : size * 1.4, h = vertical ? size * 1.15 : size
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.12))
            if let img = mon.image {
                Image(nsImage: img).resizable().scaledToFill().frame(width: w, height: h).clipped()
            } else {
                VStack(spacing: 3) {
                    Image(systemName: "photo.on.rectangle").font(.system(size: 16))
                    caption(mon.denied ? L("cal.noaccess") : L("widget.photos"))
                }
                .foregroundStyle(.primary)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { mon.next() }
    }
}

// MARK: - Batteries (Mac + Bluetooth devices: AirPods, Magic Keyboard/Mouse/Trackpad, other accessories)

struct DeviceBattery: Identifiable {
    let id = UUID()
    let name: String
    let pct: Int
    let symbol: String
}

private func deviceSymbol(_ name: String) -> String {
    let n = name.lowercased()
    if n.contains("airpods max") { return "airpodsmax" }
    if n.contains("airpods pro") { return "airpodspro" }
    if n.contains("airpods") { return "airpods" }
    if n.contains("keyboard") { return "keyboard" }
    if n.contains("mouse") { return "computermouse" }
    if n.contains("trackpad") { return "rectangle.and.hand.point.up.left" }
    if n.contains("mac") { return "laptopcomputer" }
    return "dot.radiowaves.left.and.right"
}

final class BatteriesMonitor: ObservableObject {
    static let shared = BatteriesMonitor()
    @Published var devices: [DeviceBattery] = []
    private let queue = DispatchQueue(label: "ydock.batteries")
    private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let mac = BatteryMonitor.shared
        let macEntry: DeviceBattery? = mac.present ? DeviceBattery(name: "Mac", pct: mac.pct, symbol: "laptopcomputer") : nil
        queue.async { [weak self] in
            var found: [DeviceBattery] = []
            // 1) HID accessories that publish BatteryPercent in the IORegistry (Magic Keyboard / Mouse / Trackpad).
            var product: String?
            for line in runCommand("/usr/sbin/ioreg", ["-r", "-k", "BatteryPercent", "-l", "-w0"]).split(separator: "\n") {
                let s = String(line)
                if s.contains("+-o") { product = nil }
                if s.contains("\"Product\" ="), let n = s.split(separator: "\"").dropFirst(2).first { product = String(n) }
                if s.contains("\"BatteryPercent\" ="), let v = Int(s.split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "") {
                    let name = product ?? "Device"
                    found.append(DeviceBattery(name: name, pct: v, symbol: deviceSymbol(name)))
                }
            }
            // 2) Connected Bluetooth devices that report a level (AirPods, third-party headphones…).
            let json = runCommand("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"])
            if let data = json.data(using: .utf8),
               let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["SPBluetoothDataType"] as? [[String: Any]],
               let connected = root.first?["device_connected"] as? [[String: Any]] {
                for entry in connected {
                    for (name, info) in entry {
                        guard let d = info as? [String: Any], !found.contains(where: { $0.name == name }) else { continue }
                        func level(_ k: String) -> Int? { (d[k] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) } }
                        let lr = [level("device_batteryLevelLeft"), level("device_batteryLevelRight")].compactMap { $0 }.min()
                        if let v = level("device_batteryLevelMain") ?? lr ?? level("device_batteryLevel") {
                            found.append(DeviceBattery(name: name, pct: v, symbol: deviceSymbol(name)))
                        }
                    }
                }
            }
            let all = (macEntry.map { [$0] } ?? []) + found
            DispatchQueue.main.async { self?.devices = all }
        }
    }
}

struct BatteryRing: View {
    let device: DeviceBattery
    var small = true
    var body: some View {
        let color: Color = device.pct <= 20 ? .red : .green
        VStack(spacing: 1) {
            ZStack {
                Circle().stroke(color.opacity(0.22), lineWidth: 3)
                Circle().trim(from: 0, to: Double(device.pct) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                Image(systemName: device.symbol).font(.system(size: small ? 10 : 12))
            }
            .frame(width: small ? 26 : 32, height: small ? 26 : 32)
            Text("\(device.pct)%").font(.system(size: 9, weight: .medium, design: .rounded))
        }
    }
}

struct BatteriesWidget: View {
    let size: Double
    @ObservedObject private var mon = BatteriesMonitor.shared
    @Environment(\.dockVertical) private var vertical
    var body: some View {
        WidgetCard(size: size) {
            if mon.devices.isEmpty {
                VStack(spacing: 3) {
                    Image(systemName: "battery.50").font(.system(size: 16))
                    caption(L("batteries.none"))
                }
                .foregroundStyle(.primary)
            } else {
                let layout = vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
                layout { ForEach(mon.devices.prefix(4)) { BatteryRing(device: $0) } }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, vertical ? 0 : 4).padding(.vertical, 4)
            }
        }
    }
}

struct BatteriesDetail: View {
    @ObservedObject private var mon = BatteriesMonitor.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if mon.devices.isEmpty { Text(L("batteries.none")).font(.system(size: 12)).foregroundStyle(.secondary) }
            ForEach(mon.devices) { d in
                HStack(spacing: 10) {
                    Image(systemName: d.symbol).frame(width: 20)
                    Text(d.name).font(.system(size: 12)).lineLimit(1)
                    Spacer()
                    Text("\(d.pct)%").font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
                ProgressView(value: Double(d.pct), total: 100).tint(d.pct <= 20 ? .red : .green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { mon.refresh() }
    }
}
