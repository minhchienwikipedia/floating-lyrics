import SwiftUI

/// The status-bar item: an icon, or the current line when menu bar lyrics are on.
struct MenuBarLabel: View {
    @EnvironmentObject private var engine: LyricsEngine
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if settings.menuBarLyrics, let text = engine.currentLine?.text, !text.isEmpty {
                let max = Int(settings.menuBarMaxLength)
                Text(text.count > max ? text.prefix(max) + "…" : text)
            } else {
                Image(systemName: "music.note")
            }
        }
        // The label is always alive, so it's where hotkeys get their window opener.
        .onAppear { AppModel.shared.openWindow = openWindow }
    }
}

struct MenuBarMenu: View {
    @EnvironmentObject private var engine: LyricsEngine
    @EnvironmentObject private var player: PlayerMonitor
    @EnvironmentObject private var lyrics: LyricsStore
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        if let track = player.track {
            Text(track.title)
            Text("\(track.artist) · \(track.source)")
        } else {
            Text("Nothing playing")
        }
        Divider()

        Toggle("Desktop Lyrics", isOn: $settings.karaokeEnabled)
        if settings.karaokeEnabled {
            Toggle("Unlock Desktop Lyrics (drag to move)", isOn: $settings.karaokeDraggable)
        }
        Toggle("Menu Bar Lyrics", isOn: $settings.menuBarLyrics)
        Button("Show Lyrics Window") { show("lyrics") }
            .keyboardShortcut("l")
        Divider()

        Text("Offset for this song: \(offsetLabel)")
        Button("Show Lyrics Earlier (+0.5s)") { engine.adjustOffset(by: 500) }
            .keyboardShortcut("=")
            .disabled(player.track == nil)
        Button("Show Lyrics Later (−0.5s)") { engine.adjustOffset(by: -500) }
            .keyboardShortcut("-")
            .disabled(player.track == nil)
        Button("Reset Offset") { engine.resetOffset() }
            .disabled(engine.trackOffsetMs == 0)
        Divider()

        Button("Search Lyrics…") { show("search") }
            .keyboardShortcut("f")
        Button("Wrong Lyrics") {
            if let track = player.track { lyrics.markWrong(track) }
            show("search")
        }
        .disabled(player.track == nil)
        Divider()

        Button("Settings…") {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")
        Button("Quit Floating Lyrics") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var offsetLabel: String {
        let s = engine.trackOffsetMs / 1000
        return s == 0 ? "0s" : String(format: "%+.1fs", s)
    }

    private func show(_ id: String) {
        AppModel.shared.openWindow = openWindow
        AppModel.shared.show(id)
    }
}
