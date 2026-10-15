import Foundation

struct LyricLine: Identifiable, Equatable {
    let id: Int
    let time: Double
    let text: String
}

enum LyricsState: Equatable {
    case idle
    case loading
    case synced([LyricLine])
    case plain(String)
    case instrumental
    case notFound
    case failed(String)
}

/// Fetches lyrics from LRCLIB (https://lrclib.net), a free, keyless lyrics API.
@MainActor
final class LyricsStore: ObservableObject {
    @Published private(set) var state: LyricsState = .idle

    private var task: Task<Void, Never>?
    private var cache: [String: LyricsState] = [:]
    /// Per-song choice from the search window: an LRCLIB id, or -1 for "no lyrics".
    private let overridesKey = "lyricsOverrides"
    private static let markedWrong = -1

    private var overrides: [String: Int] {
        get { UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Int] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: overridesKey) }
    }

    func load(for track: Track?) {
        task?.cancel()
        guard let track else { state = .idle; return }

        let key = track.key
        if let cached = cache[key] { state = cached; return }

        let override = overrides[key]
        if override == Self.markedWrong { state = .notFound; return }

        state = .loading
        task = Task {
            let result: LyricsState
            do {
                if let id = override,
                   let record: Record = try await Self.request(URL(string: "https://lrclib.net/api/get/\(id)")!) {
                    result = Self.state(from: record)
                } else {
                    result = try await Self.fetch(track)
                }
            } catch is CancellationError {
                return
            } catch {
                result = .failed(error.localizedDescription)
            }
            guard !Task.isCancelled else { return }
            if case .failed = result {} else { cache[key] = result }
            state = result
        }
    }

    /// Manual search for the search window.
    func search(title: String, artist: String) async throws -> [Record] {
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [.init(name: "track_name", value: title)]
        if !artist.isEmpty { search.queryItems?.append(.init(name: "artist_name", value: artist)) }
        return try await Self.request(search.url!) ?? []
    }

    /// Uses `record` for `track` from now on.
    func choose(_ record: Record, for track: Track) {
        task?.cancel()
        let result = Self.state(from: record)
        overrides[track.key] = record.id
        cache[track.key] = result
        state = result
    }

    /// Hides the current lyrics for `track` until something else is chosen.
    func markWrong(_ track: Track) {
        task?.cancel()
        overrides[track.key] = Self.markedWrong
        cache[track.key] = .notFound
        state = .notFound
    }

    struct Record: Decodable, Identifiable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?

        var hasSynced: Bool { !(syncedLyrics ?? "").isEmpty }
    }

    private static func fetch(_ track: Track) async throws -> LyricsState {
        // 1. Exact match by signature (best results).
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [
            .init(name: "track_name", value: track.title),
            .init(name: "artist_name", value: track.artist),
            .init(name: "album_name", value: track.album),
            .init(name: "duration", value: String(Int(track.duration.rounded()))),
        ]
        if let record: Record = try await request(get.url!) {
            return state(from: record)
        }

        // 2. Fuzzy search fallback, preferring a synced result.
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [
            .init(name: "track_name", value: track.title),
            .init(name: "artist_name", value: track.artist),
        ]
        let results: [Record] = try await request(search.url!) ?? []
        guard let best = results.first(where: { $0.syncedLyrics != nil }) ?? results.first else {
            return .notFound
        }
        return state(from: best)
    }

    private static func request<T: Decodable>(_ url: URL) async throws -> T? {
        var req = URLRequest(url: url)
        req.setValue("FloatingLyrics/0.1 (personal macOS app)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func state(from record: Record) -> LyricsState {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = parseLRC(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = record.plainLyrics, !plain.isEmpty { return .plain(plain) }
        return .notFound
    }

    /// Parses LRC text like "[01:23.45] line" (a line may carry several timestamps).
    static func parseLRC(_ text: String) -> [LyricLine] {
        let regex = try! Regex(#"\[(\d+):(\d+(?:\.\d+)?)\]"#, as: (Substring, Substring, Substring).self)
        var entries: [(Double, String)] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            let stamps = line.matches(of: regex)
            guard let last = stamps.last else { continue }
            let lyric = line[last.range.upperBound...].trimmingCharacters(in: .whitespaces)
            for m in stamps {
                let time = (Double(m.output.1) ?? 0) * 60 + (Double(m.output.2) ?? 0)
                entries.append((time, lyric))
            }
        }
        return entries
            .sorted { $0.0 < $1.0 }
            .enumerated()
            .map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
