import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            DesktopLyricsSettings()
                .tabItem { Label("Desktop Lyrics", systemImage: "text.bubble") }
            WindowSettings()
                .tabItem { Label("Window", systemImage: "macwindow") }
            FilterSettings()
                .tabItem { Label("Filter", systemImage: "line.3.horizontal.decrease.circle") }
            ShortcutSettings()
                .tabItem { Label("Shortcuts", systemImage: "command") }
        }
        .frame(width: 520)
    }
}

private struct GeneralSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var launch = LaunchWithPlayer.shared

    var body: some View {
        Form {
            Section("Launch") {
                Toggle("Open automatically when a music player starts", isOn: $launch.isEnabled)
                switch launch.status {
                case .requiresApproval:
                    HStack {
                        Text("Allow Floating Lyrics in System Settings → General → Login Items.")
                            .font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Open Login Items") { launch.openLoginItemsSettings() }
                    }
                case .notFound:
                    Text("Helper not found — rebuild the app with build.sh.")
                        .font(.caption).foregroundStyle(.red)
                default:
                    EmptyView()
                }
                if let error = launch.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Toggle("Quit when all music players quit", isOn: $settings.quitWithPlayer)
                Text("Works with Music, Spotify and YouTube Music. Keep the app in the same place after turning this on.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .onAppear { launch.refresh() }
            Section("Player") {
                Picker("Preferred music player", selection: $settings.preferredPlayer) {
                    ForEach(PreferredPlayer.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("Automatic follows whichever of Music, Spotify or YouTube Music is playing.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Timing") {
                LabeledContent("Global offset") {
                    Stepper(value: $settings.globalOffsetMs, in: -10_000...10_000, step: 100) {
                        Text("\(Int(settings.globalOffsetMs)) ms").monospacedDigit()
                    }
                }
                Text("Positive shows lyrics earlier. Per-song offsets are set from the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Behavior") {
                Toggle("Hide desktop lyrics when music is paused", isOn: $settings.hideWhenPaused)
                Toggle("Show lyrics in the menu bar", isOn: $settings.menuBarLyrics)
                LabeledContent("Menu bar max length") {
                    Slider(value: $settings.menuBarMaxLength, in: 15...80, step: 1)
                    Text("\(Int(settings.menuBarMaxLength))").monospacedDigit().frame(width: 28)
                }
                .disabled(!settings.menuBarLyrics)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DesktopLyricsSettings: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var desktop = AppModel.shared.desktopLyrics
    private let fonts = NSFontManager.shared.availableFontFamilies

    private func sizeBinding(_ dimension: WritableKeyPath<CGSize, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { desktop.size[keyPath: dimension] },
            set: { value in
                if dimension == \CGSize.width { desktop.setSize(width: value) }
                else { desktop.setSize(height: value) }
            }
        )
    }

    var body: some View {
        Form {
            Section {
                preview
            }
            Section("Desktop lyrics") {
                Toggle("Show desktop lyrics", isOn: $settings.karaokeEnabled)
                Toggle("Unlock to drag into position", isOn: $settings.karaokeDraggable)
                Toggle("One line mode", isOn: $settings.karaokeOneLine)
                Toggle("Fade out when the mouse is over the lyrics", isOn: $settings.karaokeHideOnHover)
                Button("Reset Position & Size") { desktop.resetPosition() }
            }
            Section("Effects") {
                Toggle("Glow", isOn: $settings.karaokeGlow)
                Toggle("Furigana over kanji for Japanese lyrics", isOn: $settings.karaokeFurigana)
            }
            Section("Size") {
                LabeledContent("Max width") {
                    Slider(value: sizeBinding(\.width), in: DesktopLyricsController.minSize.width...desktop.maxSize.width)
                    Text("\(Int(desktop.size.width))").monospacedDigit().frame(width: 40)
                }
                LabeledContent("Height") {
                    Slider(value: sizeBinding(\.height), in: DesktopLyricsController.minSize.height...desktop.maxSize.height)
                    Text("\(Int(desktop.size.height))").monospacedDigit().frame(width: 40)
                }
                Text("Lines longer than the width wrap onto more rows. You can also unlock the desktop lyrics and drag the corner handle.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Font") {
                Picker("Font", selection: $settings.karaokeFontName) {
                    Text("System").tag("")
                    Divider()
                    ForEach(fonts, id: \.self) { Text($0).tag($0) }
                }
                LabeledContent("Size") {
                    Slider(value: $settings.karaokeFontSize, in: 14...72, step: 1)
                    Text("\(Int(settings.karaokeFontSize))").monospacedDigit().frame(width: 28)
                }
            }
            Section("Colors") {
                ColorPicker("Text", selection: $settings.karaokeTextColor, supportsOpacity: true)
                ColorPicker("Highlight", selection: $settings.karaokeHighlightColor, supportsOpacity: true)
                Toggle("Shadow", isOn: $settings.karaokeShadow)
                Toggle("Background", isOn: $settings.karaokeBackground)
                if settings.karaokeBackground {
                    ColorPicker("Background color", selection: $settings.karaokeBackgroundColor,
                                supportsOpacity: true)
                }
            }
            Section {
                Button("Restore Defaults", role: .destructive) { restoreDefaults() }
            }
        }
        .formStyle(.grouped)
    }

    private var preview: some View {
        VStack(spacing: 6) {
            KaraokeLineView(text: "Sample lyric line", progress: 0.55, settings: settings)
            if !settings.karaokeOneLine {
                // A generic Japanese sentence to preview furigana.
                KaraokeLineView(text: "今日は良い天気です", progress: 0, settings: settings)
                    .opacity(0.75)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background {
            if settings.karaokeBackground {
                RoundedRectangle(cornerRadius: 12).fill(settings.karaokeBackgroundColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .background(LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 8))
    }

    private func restoreDefaults() {
        for key in ["karaokeFontName", "karaokeFontSize", "karaokeTextColor", "karaokeHighlightColor",
                    "karaokeShadow", "karaokeBackground", "karaokeBackgroundColor", "karaokeOneLine",
                    "karaokeGlow", "karaokeFurigana"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        settings.objectWillChange.send()
    }
}

private struct WindowSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Lyrics window") {
                Toggle("Keep window on top", isOn: $settings.windowAlwaysOnTop)
                LabeledContent("Font size") {
                    Slider(value: $settings.windowFontSize, in: 11...32, step: 1)
                    Text("\(Int(settings.windowFontSize))").monospacedDigit().frame(width: 28)
                }
                Text("Double-click a line in the lyrics window to jump the song there.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FilterSettings: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section("Credit line filter") {
                Toggle("Hide credit lines", isOn: $settings.filterEnabled)
                Text("Hides lines that contain a colon and any of these words, e.g. \"Composer: …\". Separate with commas or new lines.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $settings.filterKeywords)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .disabled(!settings.filterEnabled)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                ForEach(ShortcutAction.allCases) { action in
                    LabeledContent(action.title) { ShortcutRecorder(action: action) }
                }
            } header: {
                Text("Global shortcuts")
            } footer: {
                Text("Work from any app. Click a shortcut, then press the new keys (must include ⌘, ⌥ or ⌃). Esc cancels.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("Restore Default Shortcuts") { HotKeyCenter.shared.resetAll() }
            }
        }
        .formStyle(.grouped)
    }
}
