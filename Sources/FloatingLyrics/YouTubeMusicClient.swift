import AppKit

/// Listens to the "API Server" plugin of th-ch/youtube-music over its WebSocket
/// (Plugins → API Server in the YouTube Music app, default port 26538).
///
/// The socket pushes events — track change, play/pause, seek — rather than a
/// steady position tick, so `snapshot.date` marks when `position` was true and
/// the caller extrapolates from there.
@MainActor
final class YouTubeMusicClient {
    static let bundleID = "com.github.th-ch.youtube-music"

    struct Snapshot {
        var track: Track?
        var position: Double
        var date: Date
        var playing: Bool
    }

    private(set) var snapshot: Snapshot?
    /// Called on every pushed event so the UI can react immediately.
    var onChange: (() -> Void)?

    private let host = "127.0.0.1:26538"
    private let clientID = "FloatingLyrics"
    private let tokenKey = "ytmAccessToken"
    private var socket: URLSessionWebSocketTask?
    private var lastConnectAttempt: Date?
    private var lastAuthAttempt: Date?

    private var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty
    }

    // MARK: - Connection

    /// Opens the socket if it isn't open; retries at most every 3 seconds.
    func ensureConnected() {
        guard socket == nil else { return }
        if let last = lastConnectAttempt, Date().timeIntervalSince(last) < 3 { return }
        lastConnectAttempt = Date()

        var components = URLComponents(string: "ws://\(host)/api/v1/ws")!
        if let token { components.queryItems = [.init(name: "token", value: token)] }
        var req = URLRequest(url: components.url!)
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let task = URLSession.shared.webSocketTask(with: req)
        socket = task
        task.resume()
        receive(on: task)
    }

    func disconnect() {
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if snapshot != nil {
            snapshot = nil
            onChange?()
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.socket === task else { return }
                switch result {
                case .success(.string(let text)):
                    self.handle(Data(text.utf8))
                    self.receive(on: task)
                case .success(.data(let data)):
                    self.handle(data)
                    self.receive(on: task)
                case .success:
                    self.receive(on: task)
                case .failure:
                    self.socketClosed(task)
                }
            }
        }
    }

    private func socketClosed(_ task: URLSessionWebSocketTask) {
        socket = nil
        snapshot = nil
        onChange?()
        // No token yet, or the server rejected ours — either as a 1008 close frame or by
        // refusing the handshake with an HTTP error: ask for a new one.
        let status = (task.response as? HTTPURLResponse)?.statusCode
        if token == nil || task.closeCode == .policyViolation || status == 401 || status == 403 {
            token = nil
            Task { await authorize() }
        }
    }

    /// Asks YouTube Music for a token; the app shows an "allow?" dialog the first time.
    /// Throttled so a declined dialog doesn't pop up again and again.
    private func authorize() async {
        if let last = lastAuthAttempt, Date().timeIntervalSince(last) < 60 { return }
        lastAuthAttempt = Date()

        var req = URLRequest(url: URL(string: "http://\(host)/auth/\(clientID)")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60 // waits while the user answers the dialog
        struct Auth: Decodable { let accessToken: String }
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let auth = try? JSONDecoder().decode(Auth.self, from: data) else { return }
        token = auth.accessToken
        lastConnectAttempt = nil
        ensureConnected()
    }

    func seek(to seconds: Double) {
        var req = URLRequest(url: URL(string: "http://\(host)/api/v1/seek-to")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try? JSONEncoder().encode(["seconds": seconds])
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: - Messages

    private struct Song: Decodable {
        let title: String
        let artist: String
        let album: String?
        let songDuration: Double
        let isPaused: Bool?

        var track: Track {
            Track(title: title, artist: artist, album: album ?? "",
                  duration: songDuration, source: "YouTube Music")
        }
    }

    private struct Message: Decodable {
        let type: String
        let song: Song?
        let position: Double?
        let isPlaying: Bool?
    }

    private func handle(_ data: Data) {
        guard let message = try? JSONDecoder().decode(Message.self, from: data) else { return }
        let now = Date()
        var snap = snapshot ?? Snapshot(track: nil, position: 0, date: now, playing: false)

        switch message.type {
        case "PLAYER_INFO":
            snap = Snapshot(track: message.song?.track, position: message.position ?? 0,
                            date: now, playing: message.isPlaying ?? false)
        case "VIDEO_CHANGED":
            snap.track = message.song?.track
            snap.position = message.position ?? 0
            snap.date = now
            if let paused = message.song?.isPaused { snap.playing = !paused }
        case "PLAYER_STATE_CHANGED":
            snap.position = message.position ?? currentPosition(of: snap, at: now)
            snap.date = now
            snap.playing = message.isPlaying ?? snap.playing
        case "POSITION_CHANGED":
            guard let position = message.position else { return }
            snap.position = position
            snap.date = now
        default:
            return // volume, repeat, shuffle, likes
        }
        snapshot = snap
        onChange?()
    }

    private func currentPosition(of snap: Snapshot, at date: Date) -> Double {
        snap.playing ? snap.position + date.timeIntervalSince(snap.date) : snap.position
    }
}
