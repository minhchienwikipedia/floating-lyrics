import Combine
import SwiftUI

enum PreferredPlayer: String, CaseIterable, Identifiable {
    case auto = "Automatic"
    case music = "Music"
    case spotify = "Spotify"
    case youTubeMusic = "YouTube Music"

    var id: String { rawValue }
}

/// All user preferences, persisted to UserDefaults. Observable from views and
/// from non-view code (engine, desktop lyrics panel) alike.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // General
    @Stored("preferredPlayer") var preferredPlayerRaw = PreferredPlayer.auto.rawValue
    @Stored("globalOffsetMs") var globalOffsetMs = 0.0
    @Stored("hideWhenPaused") var hideWhenPaused = true
    @Stored("quitWithPlayer") var quitWithPlayer = false

    // Menu bar
    @Stored("menuBarLyrics") var menuBarLyrics = false
    @Stored("menuBarMaxLength") var menuBarMaxLength = 40.0

    // Desktop (karaoke) lyrics
    @Stored("karaokeEnabled") var karaokeEnabled = true
    @Stored("karaokeDraggable") var karaokeDraggable = false
    @Stored("karaokeOneLine") var karaokeOneLine = false
    @Stored("karaokeHideOnHover") var karaokeHideOnHover = true
    @Stored("karaokeFurigana") var karaokeFurigana = true
    @Stored("karaokeGlow") var karaokeGlow = true
    @Stored("karaokeFontName") var karaokeFontName = ""          // "" = system font
    @Stored("karaokeFontSize") var karaokeFontSize = 24.0
    @Stored("karaokeTextColor") var karaokeTextHex = "FFFFFFFF"
    @Stored("karaokeHighlightColor") var karaokeHighlightHex = "4FC3F7FF"
    @Stored("karaokeShadow") var karaokeShadow = true
    @Stored("karaokeBackground") var karaokeBackground = false
    @Stored("karaokeBackgroundColor") var karaokeBackgroundHex = "00000080"

    // Lyrics window
    @Stored("windowFontSize") var windowFontSize = 16.0
    @Stored("windowAlwaysOnTop") var windowAlwaysOnTop = true

    // Filter
    @Stored("filterEnabled") var filterEnabled = true
    @Stored("filterKeywords") var filterKeywords =
        "作词, 作曲, 编曲, 制作人, 作詞, 編曲, Lyricist, Lyrics by, Composer, Composed by, Arranger, Producer"

    // MARK: Typed accessors

    var preferredPlayer: PreferredPlayer {
        get { PreferredPlayer(rawValue: preferredPlayerRaw) ?? .auto }
        set { preferredPlayerRaw = newValue.rawValue }
    }

    var karaokeTextColor: Color {
        get { Color(hex: karaokeTextHex) }
        set { karaokeTextHex = newValue.hex }
    }

    var karaokeHighlightColor: Color {
        get { Color(hex: karaokeHighlightHex) }
        set { karaokeHighlightHex = newValue.hex }
    }

    var karaokeBackgroundColor: Color {
        get { Color(hex: karaokeBackgroundHex) }
        set { karaokeBackgroundHex = newValue.hex }
    }

    func karaokeFont(scale: Double = 1) -> Font {
        let size = karaokeFontSize * scale
        return karaokeFontName.isEmpty
            ? .system(size: size, weight: .semibold, design: .rounded)
            : .custom(karaokeFontName, size: size)
    }

    var filterKeywordList: [String] {
        filterKeywords
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}

/// A UserDefaults-backed property that notifies its enclosing ObservableObject.
/// Values must be plist types (Bool, Double, String).
@propertyWrapper
struct Stored<Value> {
    let key: String
    let defaultValue: Value

    init(wrappedValue: Value, _ key: String) {
        self.key = key
        self.defaultValue = wrappedValue
    }

    static subscript<T: ObservableObject>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value where T.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            let s = instance[keyPath: storageKeyPath]
            return UserDefaults.standard.object(forKey: s.key) as? Value ?? s.defaultValue
        }
        set {
            instance.objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: instance[keyPath: storageKeyPath].key)
        }
    }

    @available(*, unavailable, message: "@Stored is only available on ObservableObject classes")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
}

extension Color {
    /// "RRGGBB" or "RRGGBBAA".
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        if hex.count != 8 { value = value << 8 | 0xFF }
        self.init(.sRGB,
                  red: Double((value >> 24) & 0xFF) / 255,
                  green: Double((value >> 16) & 0xFF) / 255,
                  blue: Double((value >> 8) & 0xFF) / 255,
                  opacity: Double(value & 0xFF) / 255)
    }

    var hex: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        func byte(_ v: CGFloat) -> Int { Int((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "%02X%02X%02X%02X",
                      byte(c.redComponent), byte(c.greenComponent),
                      byte(c.blueComponent), byte(c.alphaComponent))
    }
}
