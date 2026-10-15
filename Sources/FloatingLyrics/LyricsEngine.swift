import Combine
import Foundation

/// Ties player, lyrics and settings together: loads lyrics on track change,
/// applies the filter and offsets, and tracks which line is current.
@MainActor
final class LyricsEngine: ObservableObject {
    @Published private(set) var lines: [LyricLine] = []
    @Published private(set) var currentLineID: Int?
    /// Per-track offset in ms; positive shows lyrics earlier.
    @Published private(set) var trackOffsetMs: Double = 0

    let player: PlayerMonitor
    let lyrics: LyricsStore
    private let settings: AppSettings
    private var timer: Timer?
    private var bag: Set<AnyCancellable> = []
    private let offsetsKey = "trackOffsets"

    init(player: PlayerMonitor, lyrics: LyricsStore, settings: AppSettings) {
        self.player = player
        self.lyrics = lyrics
        self.settings = settings

        player.$track
            .removeDuplicates()
            .sink { [weak self] track in self?.trackChanged(track) }
            .store(in: &bag)
        lyrics.$state
            .sink { [weak self] state in self?.rebuildLines(from: state) }
            .store(in: &bag)
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self else { return }
                self.rebuildLines(from: self.lyrics.state)
            }
            .store(in: &bag)
    }

    func start() {
        player.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    // MARK: - Timing

    var offsetSeconds: Double { (settings.globalOffsetMs + trackOffsetMs) / 1000 }

    func lyricsTime(at date: Date = Date()) -> Double {
        player.currentPosition(at: date) + offsetSeconds
    }

    struct LinePosition {
        let index: Int?
        let progress: Double   // 0...1 through the current line
    }

    func position(at date: Date = Date()) -> LinePosition {
        let t = lyricsTime(at: date)
        guard let i = lines.lastIndex(where: { $0.time <= t }) else {
            return LinePosition(index: nil, progress: 0)
        }
        let end = i + 1 < lines.count
            ? lines[i + 1].time
            : max(player.track?.duration ?? 0, lines[i].time + 5)
        let progress = (t - lines[i].time) / max(end - lines[i].time, 0.1)
        return LinePosition(index: i, progress: min(max(progress, 0), 1))
    }

    var currentLine: LyricLine? {
        guard let id = currentLineID else { return nil }
        return lines.first { $0.id == id }
    }

    private func tick() {
        let id = position().index.map { lines[$0].id }
        if id != currentLineID { currentLineID = id }
    }

    // MARK: - Actions

    func adjustOffset(by ms: Double) {
        setTrackOffset(trackOffsetMs + ms)
    }

    func resetOffset() {
        setTrackOffset(0)
    }

    func seek(to line: LyricLine) {
        player.seek(to: max(0, line.time - offsetSeconds + 0.05))
    }

    // MARK: - Private

    private func trackChanged(_ track: Track?) {
        lyrics.load(for: track)
        let offsets = UserDefaults.standard.dictionary(forKey: offsetsKey) as? [String: Double] ?? [:]
        trackOffsetMs = track.flatMap { offsets[$0.key] } ?? 0
    }

    private func setTrackOffset(_ ms: Double) {
        guard let track = player.track else { return }
        trackOffsetMs = ms
        var offsets = UserDefaults.standard.dictionary(forKey: offsetsKey) as? [String: Double] ?? [:]
        offsets[track.key] = ms == 0 ? nil : ms
        UserDefaults.standard.set(offsets, forKey: offsetsKey)
    }

    /// Drops credit lines like "Composer: …" when the filter is on.
    private func rebuildLines(from state: LyricsState) {
        guard case .synced(let all) = state else {
            if !lines.isEmpty { lines = [] }
            currentLineID = nil
            return
        }
        var result = all
        if settings.filterEnabled {
            let keywords = settings.filterKeywordList
            result = all.filter { line in
                let isCredit = line.text.contains(":") || line.text.contains("：")
                return !(isCredit && keywords.contains { line.text.localizedCaseInsensitiveContains($0) })
            }
        }
        if result != lines { lines = result }
        tick()
    }
}

extension Track {
    /// Stable identity for per-song preferences (offset, chosen lyrics).
    var key: String { "\(artist)|\(title)" }
}
