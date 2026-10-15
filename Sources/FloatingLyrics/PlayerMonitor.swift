import AppKit

struct Track: Equatable {
    let title: String
    let artist: String
    let album: String
    let duration: Double   // seconds
    let source: String     // "Music", "Spotify" or "YouTube Music"
}

/// Polls Apple Music and Spotify (AppleScript), listens to YouTube Music (WebSocket), and interpolates the
/// playback position between polls so the UI can update smoothly.
@MainActor
final class PlayerMonitor: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false

    private var position: Double = 0
    private var positionDate = Date()
    private var timer: Timer?
    private let youTubeMusic = YouTubeMusicClient()

    func currentPosition(at date: Date = Date()) -> Double {
        isPlaying ? position + date.timeIntervalSince(positionDate) : position
    }

    func start() {
        guard timer == nil else { return }
        youTubeMusic.onChange = { [weak self] in self?.poll() }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        var states = Player.allCases
            .filter(\.isRunning)
            .compactMap { $0.query() }
        if youTubeMusic.isRunning {
            youTubeMusic.ensureConnected()
            if let s = youTubeMusic.snapshot, let track = s.track {
                states.append(PlayerState(track: track, position: s.position,
                                          date: s.date, playing: s.playing))
            }
        } else {
            youTubeMusic.disconnect()
        }
        apply(states)
    }

    /// Jumps the active player to `seconds` and updates our clock right away.
    func seek(to seconds: Double) {
        guard let track else { return }
        switch track.source {
        case "YouTube Music":
            youTubeMusic.seek(to: seconds)
        default:
            Player.allCases.first { $0.name == track.source }?.seek(to: seconds)
        }
        position = seconds
        positionDate = Date()
    }

    private func apply(_ states: [PlayerState]) {
        var states = states
        let preferred = AppSettings.shared.preferredPlayer
        if preferred != .auto {
            states = states.filter { $0.track.source == preferred.rawValue }
        }
        // Prefer whichever player is actually playing.
        guard let state = states.first(where: \.playing) ?? states.first else {
            track = nil
            isPlaying = false
            return
        }
        // Re-sync only on fresh data: AppleScript players are fresh every poll, while
        // YouTube Music's snapshot changes only when its socket pushes an event.
        if state.track != track || state.date != positionDate || state.playing != isPlaying {
            position = state.position
            positionDate = state.date
        }
        if track != state.track { track = state.track }
        isPlaying = state.playing
    }
}

private struct PlayerState {
    let track: Track
    let position: Double
    let date: Date
    let playing: Bool
}

private enum Player: CaseIterable {
    case music, spotify

    var bundleID: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    var name: String { self == .music ? "Music" : "Spotify" }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private var source: String {
        """
        tell application id "\(bundleID)"
            if player state is stopped then return ""
            set t to current track
            return (name of t) & "|||" & (artist of t) & "|||" & (album of t) & "|||" & ((duration of t) as string) & "|||" & ((player position) as string) & "|||" & ((player state) as string)
        end tell
        """
    }

    func seek(to seconds: Double) {
        let script = "tell application id \"\(bundleID)\" to set player position to \(seconds)"
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
    }

    func query() -> PlayerState? {
        var error: NSDictionary?
        guard let output = NSAppleScript(source: source)?
            .executeAndReturnError(&error).stringValue, error == nil else { return nil }

        let parts = output.components(separatedBy: "|||")
        guard parts.count == 6 else { return nil }

        func number(_ s: String) -> Double {
            Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
        }
        var duration = number(parts[3])
        if self == .spotify { duration /= 1000 } // Spotify reports milliseconds

        let track = Track(title: parts[0], artist: parts[1], album: parts[2],
                          duration: duration, source: name)
        return PlayerState(track: track, position: number(parts[4]), date: Date(),
                           playing: parts[5] == "playing")
    }
}
