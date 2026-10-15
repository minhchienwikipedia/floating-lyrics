import SwiftUI

/// Manual lyrics search: pick the right LRCLIB entry for the current song.
struct SearchView: View {
    @EnvironmentObject private var player: PlayerMonitor
    @EnvironmentObject private var lyrics: LyricsStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var artist = ""
    @State private var results: [LyricsStore.Record] = []
    @State private var selection: Int?
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Title", text: $title)
                TextField("Artist", text: $artist)
                Button("Search") { Task { await search() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty || searching)
            }

            Table(results, selection: $selection) {
                TableColumn("Title") { Text($0.trackName ?? "") }
                TableColumn("Artist") { Text($0.artistName ?? "") }
                TableColumn("Album") { Text($0.albumName ?? "") }
                TableColumn("Length") { Text(Self.duration($0.duration)).monospacedDigit() }
                    .width(56)
                TableColumn("Synced") { Text($0.hasSynced ? "✓" : "") }
                    .width(52)
            }
            .overlay {
                if searching { ProgressView() }
                else if let error { Text(error).foregroundStyle(.secondary) }
                else if results.isEmpty { Text("No results").foregroundStyle(.secondary) }
            }

            HStack {
                if let track = player.track {
                    Text("Now playing: \(track.title) — \(track.artist) (\(Self.duration(track.duration)))")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Use Selected Lyrics") { useSelected() }
                    .disabled(selection == nil || player.track == nil)
            }
        }
        .padding()
        .frame(minWidth: 620, minHeight: 360)
        .onAppear {
            title = player.track?.title ?? ""
            artist = player.track?.artist ?? ""
            if !title.isEmpty { Task { await search() } }
        }
    }

    private func search() async {
        searching = true
        error = nil
        defer { searching = false }
        do {
            results = try await lyrics.search(title: title, artist: artist)
                .sorted { $0.hasSynced && !$1.hasSynced }
            selection = results.first?.id
        } catch {
            results = []
            self.error = error.localizedDescription
        }
    }

    private func useSelected() {
        guard let track = player.track,
              let record = results.first(where: { $0.id == selection }) else { return }
        lyrics.choose(record, for: track)
        dismiss()
    }

    private static func duration(_ seconds: Double?) -> String {
        guard let s = seconds, s > 0 else { return "" }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}
