import Foundation

/// One-time carry-over from the app's previous name (MyDock): config file and the login-item agent.
enum LegacyMigration {
    static func run() {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        let oldConfig = home.appendingPathComponent(".config/mydock/config.json")
        if !fm.fileExists(atPath: DockConfig.url.path), fm.fileExists(atPath: oldConfig.path) {
            try? fm.createDirectory(at: DockConfig.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: oldConfig, to: DockConfig.url)   // the old file is left untouched
        }

        let oldAgent = home.appendingPathComponent("Library/LaunchAgents/local.mydock.plist")
        if fm.fileExists(atPath: oldAgent.path) {
            try? fm.removeItem(at: oldAgent)
            LoginItem.set(true)   // keep "open at login" on, now under the new name
        }
    }
}
