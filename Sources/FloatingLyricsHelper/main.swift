import AppKit

// Background login item: opens Floating Lyrics whenever a supported music player starts.
// Lives at FloatingLyrics.app/Contents/Library/LoginItems/FloatingLyricsHelper.app.

let players: Set<String> = ["com.apple.Music", "com.spotify.client", "com.github.th-ch.youtube-music"]
let mainAppID = "local.floatinglyrics"

func launchMainApp() {
    guard NSRunningApplication.runningApplications(withBundleIdentifier: mainAppID).isEmpty else { return }
    let mainApp = Bundle.main.bundleURL
        .deletingLastPathComponent()   // LoginItems
        .deletingLastPathComponent()   // Library
        .deletingLastPathComponent()   // Contents
        .deletingLastPathComponent()   // FloatingLyrics.app
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false
    NSWorkspace.shared.openApplication(at: mainApp, configuration: config)
}

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
) { note in
    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    if let id = app?.bundleIdentifier, players.contains(id) { launchMainApp() }
}

if NSWorkspace.shared.runningApplications.contains(where: { players.contains($0.bundleIdentifier ?? "") }) {
    launchMainApp()
}

NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.run()
