import SwiftUI

/// The scrolling lyrics window.
struct ContentView: View {
    @EnvironmentObject private var player: PlayerMonitor
    @EnvironmentObject private var lyrics: LyricsStore
    @EnvironmentObject private var engine: LyricsEngine
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.4)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 260, minHeight: 200)
        .background(WindowLevelSetter(floating: settings.windowAlwaysOnTop))
    }

    @ViewBuilder private var header: some View {
        VStack(spacing: 2) {
            Text(player.track?.title ?? "Nothing playing")
                .font(.headline)
                .lineLimit(1)
            if let track = player.track {
                Text("\(track.artist) · \(track.source)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 28)   // room for the traffic-light buttons
        .padding(.bottom, 10)
        .padding(.horizontal)
    }

    @ViewBuilder private var content: some View {
        switch lyrics.state {
        case .idle:
            message("Play something in Music, Spotify or YouTube Music")
        case .loading:
            ProgressView()
        case .instrumental:
            message("♪ Instrumental ♪")
        case .notFound:
            message("No lyrics found for this track\nTry Search Lyrics… in the menu bar")
        case .failed(let error):
            message("Couldn't load lyrics\n\(error)")
        case .plain(let text):
            ScrollView {
                Text(text)
                    .font(.system(size: settings.windowFontSize))
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
        case .synced:
            SyncedLyricsView(lines: engine.lines, currentID: engine.currentLineID,
                             fontSize: settings.windowFontSize) { engine.seek(to: $0) }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }
}

private struct SyncedLyricsView: View {
    let lines: [LyricLine]
    let currentID: Int?
    let fontSize: Double
    let onSeek: (LyricLine) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(lines) { line in
                        let isCurrent = line.id == currentID
                        Text(line.text.isEmpty ? "♪" : line.text)
                            .font(.system(size: isCurrent ? fontSize * 1.25 : fontSize,
                                          weight: isCurrent ? .bold : .regular))
                            .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                            .opacity(isCurrent ? 1 : 0.6)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { onSeek(line) }
                            .id(line.id)
                    }
                }
                .padding(.vertical, 120)
                .padding(.horizontal)
            }
            .scrollIndicators(.never)
            .onChange(of: currentID) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
            .onAppear {
                if let currentID { proxy.scrollTo(currentID, anchor: .center) }
            }
        }
    }
}

/// Applies the "keep on top" preference to the hosting window.
private struct WindowLevelSetter: NSViewRepresentable {
    let floating: Bool

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.level = floating ? .floating : .normal
        }
    }
}
