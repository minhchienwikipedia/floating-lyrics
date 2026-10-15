import AppKit
import Carbon.HIToolbox
import SwiftUI

enum ShortcutAction: String, CaseIterable, Identifiable {
    case toggleDesktop, toggleLock, toggleMenuBar, showWindow
    case earlier, later, resetOffset
    case search, wrongLyrics

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggleDesktop: "Show / hide desktop lyrics"
        case .toggleLock: "Lock / unlock desktop lyrics"
        case .toggleMenuBar: "Show / hide menu bar lyrics"
        case .showWindow: "Show lyrics window"
        case .earlier: "Show lyrics earlier (+0.5s)"
        case .later: "Show lyrics later (−0.5s)"
        case .resetOffset: "Reset lyrics offset"
        case .search: "Search lyrics"
        case .wrongLyrics: "Mark lyrics as wrong"
        }
    }

    var defaultShortcut: Shortcut? {
        let hyper: NSEvent.ModifierFlags = [.control, .option, .command]
        switch self {
        case .toggleDesktop: return Shortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: hyper.rawValue, key: "L")
        case .showWindow: return Shortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: hyper.rawValue, key: "W")
        case .earlier: return Shortcut(keyCode: UInt32(kVK_ANSI_Equal), modifiers: hyper.rawValue, key: "=")
        case .later: return Shortcut(keyCode: UInt32(kVK_ANSI_Minus), modifiers: hyper.rawValue, key: "-")
        default: return nil
        }
    }
}

struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt      // NSEvent.ModifierFlags raw value
    var key: String          // display name of the key

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }

    var display: String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "") + key
    }

    static func keyName(for event: NSEvent) -> String {
        let special: [Int: String] = [
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(event.keyCode)] { return name }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}

/// Registers system-wide hotkeys (Carbon API — no Accessibility permission needed).
@MainActor
final class HotKeyCenter: ObservableObject {
    static let shared = HotKeyCenter()

    /// Actions whose shortcut couldn't be registered (taken by another app or duplicated).
    @Published private(set) var failed: Set<ShortcutAction> = []
    var handler: ((ShortcutAction) -> Void)?

    private var refs: [EventHotKeyRef] = []
    private var installed = false
    private let storeKey = "shortcuts"
    private let signature: OSType = 0x464C_5952 // "FLYR"

    func install() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
            let index = Int(hotKey.id)
            DispatchQueue.main.async {
                guard ShortcutAction.allCases.indices.contains(index) else { return }
                HotKeyCenter.shared.handler?(ShortcutAction.allCases[index])
            }
            return noErr
        }, 1, &spec, nil, nil)
        registerAll()
    }

    func shortcut(for action: ShortcutAction) -> Shortcut? {
        guard let stored = storedShortcuts[action.rawValue] else { return action.defaultShortcut }
        return try? JSONDecoder().decode(Shortcut.self, from: Data(stored.utf8)) // "" = cleared
    }

    func set(_ shortcut: Shortcut?, for action: ShortcutAction) {
        var all = storedShortcuts
        all[action.rawValue] = shortcut.flatMap { try? String(decoding: JSONEncoder().encode($0), as: UTF8.self) } ?? ""
        storedShortcuts = all
        registerAll()
    }

    func resetAll() {
        UserDefaults.standard.removeObject(forKey: storeKey)
        registerAll()
    }

    /// Temporarily releases all hotkeys, e.g. while recording a new one.
    func suspend() { unregisterAll() }
    func resume() { registerAll() }

    private var storedShortcuts: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: storeKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: storeKey) }
    }

    private func registerAll() {
        unregisterAll()
        var failures: Set<ShortcutAction> = []
        for (index, action) in ShortcutAction.allCases.enumerated() {
            guard let shortcut = shortcut(for: action) else { continue }
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers,
                                             EventHotKeyID(signature: signature, id: UInt32(index)),
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) } else { failures.insert(action) }
        }
        failed = failures
        objectWillChange.send()
    }

    private func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }
}

/// A button that records the next key combination pressed.
struct ShortcutRecorder: View {
    let action: ShortcutAction
    @ObservedObject private var center = HotKeyCenter.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            if center.failed.contains(action) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("This shortcut is already used by another app or action")
            }
            Button(recording ? "Press keys…" : (center.shortcut(for: action)?.display ?? "Record")) {
                recording ? stop() : start()
            }
            .frame(minWidth: 110)
            Button {
                center.set(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .opacity(center.shortcut(for: action) == nil ? 0 : 1)
            .help("Clear shortcut")
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        center.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape { stop(); return nil }
            let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard !mods.isDisjoint(with: [.command, .option, .control]) else {
                NSSound.beep() // require ⌘, ⌥ or ⌃ so plain typing isn't captured system-wide
                return nil
            }
            center.set(Shortcut(keyCode: UInt32(event.keyCode), modifiers: mods.rawValue,
                                key: Shortcut.keyName(for: event)), for: action)
            stop()
            return nil
        }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        center.resume()
    }
}
