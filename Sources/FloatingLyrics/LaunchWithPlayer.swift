import AppKit
import ServiceManagement

enum SupportedPlayers {
    static let bundleIDs: Set<String> = ["com.apple.Music", "com.spotify.client", "com.github.th-ch.youtube-music"]

    static var anyRunning: Bool {
        NSWorkspace.shared.runningApplications.contains { bundleIDs.contains($0.bundleIdentifier ?? "") }
    }
}

/// "Launch with player": a login-item helper (Contents/Library/LoginItems) watches for a
/// music player to start and opens Floating Lyrics. "Quit with player" is handled here.
@MainActor
final class LaunchWithPlayer: ObservableObject {
    static let shared = LaunchWithPlayer()
    static let helperID = "local.floatinglyrics.helper"

    @Published private(set) var status: SMAppService.Status
    @Published private(set) var lastError: String?

    private var service: SMAppService { .loginItem(identifier: Self.helperID) }

    private init() {
        status = SMAppService.loginItem(identifier: Self.helperID).status
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            Task { @MainActor in LaunchWithPlayer.shared.playerQuit(bundleID: id) }
        }
    }

    var isEnabled: Bool {
        get { status == .enabled || status == .requiresApproval }
        set {
            lastError = nil
            do {
                if newValue { try service.register() } else { try service.unregister() }
            } catch {
                lastError = error.localizedDescription
            }
            refresh()
        }
    }

    func refresh() {
        status = service.status
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func playerQuit(bundleID: String?) {
        guard AppSettings.shared.quitWithPlayer,
              let bundleID, SupportedPlayers.bundleIDs.contains(bundleID) else { return }
        // Give a player that's restarting a moment before deciding.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if AppSettings.shared.quitWithPlayer && !SupportedPlayers.anyRunning {
                NSApp.terminate(nil)
            }
        }
    }
}
