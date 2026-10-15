import SwiftUI

/// Long-lived app objects, shared by every scene and the desktop lyrics panel.
@MainActor
final class AppModel {
    static let shared = AppModel()

    let settings = AppSettings.shared
    let player = PlayerMonitor()
    let lyrics = LyricsStore()
    let engine: LyricsEngine
    let desktopLyrics: DesktopLyricsController
    /// Captured from a live SwiftUI view so hotkeys can open windows.
    var openWindow: OpenWindowAction?

    private init() {
        engine = LyricsEngine(player: player, lyrics: lyrics, settings: settings)
        desktopLyrics = DesktopLyricsController(engine: engine, settings: settings)
        engine.start()
        _ = LaunchWithPlayer.shared
        HotKeyCenter.shared.handler = { [weak self] in self?.perform($0) }
        HotKeyCenter.shared.install()
    }

    func perform(_ action: ShortcutAction) {
        switch action {
        case .toggleDesktop: settings.karaokeEnabled.toggle()
        case .toggleLock: settings.karaokeDraggable.toggle()
        case .toggleMenuBar: settings.menuBarLyrics.toggle()
        case .showWindow: show("lyrics")
        case .earlier: engine.adjustOffset(by: 500)
        case .later: engine.adjustOffset(by: -500)
        case .resetOffset: engine.resetOffset()
        case .search: show("search")
        case .wrongLyrics:
            if let track = player.track { lyrics.markWrong(track) }
            show("search")
        }
    }

    func show(_ id: String) {
        NSApp.activate()
        if let openWindow {
            openWindow(id: id)
        } else if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.contains(id) == true }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct FloatingLyricsApp: App {
    private let model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarMenu().environmentObjects(model)
        } label: {
            MenuBarLabel().environmentObjects(model)
        }

        Window("Lyrics", id: "lyrics") {
            ContentView()
                .environmentObjects(model)
                .containerBackground(.ultraThinMaterial, for: .window)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 380, height: 520)
        .defaultLaunchBehavior(.suppressed)

        Window("Search Lyrics", id: "search") {
            SearchView().environmentObjects(model)
        }
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView().environmentObjects(model)
        }
    }
}

private extension View {
    func environmentObjects(_ model: AppModel) -> some View {
        self.environmentObject(model.settings)
            .environmentObject(model.player)
            .environmentObject(model.lyrics)
            .environmentObject(model.engine)
    }
}
