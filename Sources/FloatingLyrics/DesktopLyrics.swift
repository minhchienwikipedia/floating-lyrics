import AppKit
import Combine
import SwiftUI

/// Owns the transparent, click-through panel that shows karaoke lyrics on the desktop.
@MainActor
final class DesktopLyricsController: ObservableObject {
    @Published private(set) var size: CGSize = .zero

    static let minSize = CGSize(width: 300, height: 80)
    var maxSize: CGSize {
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return CGSize(width: screen.width, height: min(500, screen.height))
    }

    private let panel: NSPanel
    private let settings: AppSettings
    private var bag: Set<AnyCancellable> = []
    private var dragStart: (mouse: NSPoint, frame: NSRect)?
    /// Our own frame storage. NSWindow autosave was overwritten at launch when the
    /// hosting view resized the panel, so the frame is saved only on user changes.
    private let frameKey = "desktopLyricsFrame"
    private var hoverTimer: Timer?
    private var isHovered = false

    init(engine: LyricsEngine, settings: AppSettings) {
        self.settings = settings
        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = DesktopLyricsView(controller: self)
            .environmentObject(engine)
            .environmentObject(engine.player)
            .environmentObject(settings)
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [] // the panel's size is ours, not the content's
        panel.contentView = hosting

        // Restore after the content is attached so nothing can resize it afterwards.
        setFrame(savedFrame() ?? Self.defaultFrame(), save: false)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applySettings() }
            .store(in: &bag)
        applySettings()

        // The panel is click-through, so it can't receive mouse-entered events; poll instead.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateHover() }
        }
    }

    /// Fades the lyrics out while the cursor is over them, so what's underneath stays readable.
    private func updateHover() {
        let hovered = settings.karaokeHideOnHover
            && !settings.karaokeDraggable
            && panel.isVisible
            && panel.frame.contains(NSEvent.mouseLocation)
        guard hovered != isHovered else { return }
        isHovered = hovered
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = hovered ? 0.05 : 1
        }
    }

    func resetPosition() {
        setFrame(Self.defaultFrame())
    }

    /// Called continuously while dragging (unlocked mode) — follows the mouse in screen space.
    func drag() {
        guard let (start, dx, dy) = dragDelta() else { return }
        panel.setFrameOrigin(NSPoint(x: start.minX + dx, y: start.minY + dy))
    }

    /// Called continuously while dragging the bottom-right resize handle; the top-left stays put.
    func resize() {
        guard let (start, dx, dy) = dragDelta() else { return }
        let width = clamp(start.width + dx, Self.minSize.width, maxSize.width)
        let height = clamp(start.height - dy, Self.minSize.height, maxSize.height)
        setFrame(NSRect(x: start.minX, y: start.maxY - height, width: width, height: height), save: false)
    }

    func endDrag() {
        dragStart = nil
        saveFrame()
    }

    /// Sets the size from Settings, keeping the panel centered horizontally and its bottom edge fixed.
    func setSize(width: CGFloat? = nil, height: CGFloat? = nil) {
        let f = panel.frame
        let w = clamp(width ?? f.width, Self.minSize.width, maxSize.width)
        let h = clamp(height ?? f.height, Self.minSize.height, maxSize.height)
        setFrame(NSRect(x: f.midX - w / 2, y: f.minY, width: w, height: h))
    }

    private func dragDelta() -> (NSRect, CGFloat, CGFloat)? {
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame) }
        guard let start = dragStart else { return nil }
        return (start.frame, mouse.x - start.mouse.x, mouse.y - start.mouse.y)
    }

    private func setFrame(_ frame: NSRect, save: Bool = true) {
        panel.setFrame(frame, display: true)
        size = frame.size
        if save { saveFrame() }
    }

    private func saveFrame() {
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: frameKey)
    }

    /// The saved frame, if it still lands on a connected screen.
    private func savedFrame() -> NSRect? {
        guard let string = UserDefaults.standard.string(forKey: frameKey) else { return nil }
        let frame = NSRectFromString(string)
        guard frame.width >= Self.minSize.width, frame.height >= Self.minSize.height,
              NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) else { return nil }
        return frame
    }

    private func clamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(max(v, lo), hi)
    }

    private func applySettings() {
        panel.ignoresMouseEvents = !settings.karaokeDraggable
        if settings.karaokeEnabled {
            panel.orderFrontRegardless()
        } else {
            panel.orderOut(nil)
        }
    }

    private static func defaultFrame() -> NSRect {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let width = min(1100, screen.width * 0.85)
        let height: CGFloat = 170
        return NSRect(x: screen.midX - width / 2, y: screen.minY + 30, width: width, height: height)
    }
}

private struct DesktopLyricsView: View {
    let controller: DesktopLyricsController
    @EnvironmentObject private var engine: LyricsEngine
    @EnvironmentObject private var player: PlayerMonitor
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let pos = engine.position(at: context.date)
            let visible = !engine.lines.isEmpty && (player.isPlaying || !settings.hideWhenPaused)
            let rows = displayedRows(currentIndex: pos.index)

            // Rows are keyed by line id, so when the line advances the "next" row keeps its
            // identity and slides up into the current slot while the old line scrolls out.
            VStack(spacing: 6) {
                ForEach(rows, id: \.line.id) { row in
                    KaraokeLineView(text: row.line.text.isEmpty ? "♪" : row.line.text,
                                    progress: row.isCurrent ? pos.progress : 0, settings: settings)
                        .opacity(row.isCurrent ? 1 : 0.75)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 24)),
                            removal: .opacity.combined(with: .offset(y: -24))))
                }
            }
            .animation(.easeInOut(duration: 0.35), value: pos.index)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background {
                if settings.karaokeBackground {
                    RoundedRectangle(cornerRadius: 14).fill(settings.karaokeBackgroundColor)
                }
            }
            .opacity(visible || settings.karaokeDraggable ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: visible)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .overlay {
            if settings.karaokeDraggable {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.black.opacity(0.25))
                    .strokeBorder(.white.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .overlay(alignment: .top) {
                        Text("Drag to move · drag corner to resize · lock again from the menu bar")
                            .font(.caption).foregroundStyle(.white).padding(8)
                    }
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in controller.drag() }
                        .onEnded { _ in controller.endDrag() })
                    .overlay(alignment: .bottomTrailing) { resizeHandle }
            }
        }
    }
}

private extension DesktopLyricsView {
    struct Row {
        let line: LyricLine
        let isCurrent: Bool
    }

    /// The current line plus the one after it (or just the current line in one-line mode).
    /// Before the first line starts, the first line is shown as "up next".
    func displayedRows(currentIndex: Int?) -> [Row] {
        let lines = engine.lines
        guard !lines.isEmpty else { return [] }
        let count = settings.karaokeOneLine ? 1 : 2
        guard let i = currentIndex else {
            return [Row(line: lines[0], isCurrent: false)]
        }
        return (i..<min(i + count, lines.count)).map { Row(line: lines[$0], isCurrent: $0 == i) }
    }

    var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
            .frame(width: 26, height: 26)
            .background(.white.opacity(0.9), in: Circle())
            .padding(6)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in controller.resize() }
                .onEnded { _ in controller.endDrag() })
            .help("Drag to resize")
    }
}

/// One lyric line at a fixed font size. Long lines wrap instead of shrinking, Japanese
/// gets furigana over kanji, and the karaoke highlight sweeps through each wrapped row in turn.
struct KaraokeLineView: View {
    let text: String
    let progress: Double
    @ObservedObject var settings: AppSettings
    @State private var rowHeight: CGFloat = 1

    private var segments: [Furigana.Segment]? {
        settings.karaokeFurigana ? Furigana.segments(for: text) : nil
    }

    var body: some View {
        let glow = settings.karaokeGlow
        let highlight = settings.karaokeHighlightColor
        label(settings.karaokeTextColor)
            .shadow(color: settings.karaokeTextColor.opacity(glow ? 0.35 : 0), radius: 4)
            .overlay {
                label(highlight)
                    .mask(alignment: .topLeading) {
                        GeometryReader { g in sweepMask(in: g.size) }
                    }
                    .shadow(color: highlight.opacity(glow ? 0.9 : 0), radius: 4)
                    .shadow(color: highlight.opacity(glow ? 0.6 : 0), radius: 10)
            }
            .background {
                // Height of one row (including the furigana row), to count wrapped rows.
                sampleRow.hidden()
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { rowHeight = max($0, 1) }
            }
            .shadow(color: .black.opacity(settings.karaokeShadow ? 0.85 : 0), radius: 3, y: 1)
    }

    @ViewBuilder private var sampleRow: some View {
        if segments != nil {
            VStack(spacing: 0) {
                Text("あ").font(settings.karaokeFont(scale: 0.45))
                Text("Ag").font(settings.karaokeFont())
            }
        } else {
            Text("Ag").font(settings.karaokeFont())
        }
    }

    private func sweepMask(in size: CGSize) -> some View {
        let rows = max(1, Int((size.height / rowHeight).rounded()))
        let filled = progress * Double(rows)
        let fullRows = min(Int(filled), rows)
        let fraction = filled - Double(fullRows)
        let height = size.height / CGFloat(rows)
        return ZStack(alignment: .topLeading) {
            Rectangle().frame(width: size.width, height: height * CGFloat(fullRows))
            Rectangle()
                .frame(width: size.width * fraction, height: height)
                .offset(y: height * CGFloat(fullRows))
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    @ViewBuilder private func label(_ color: Color) -> some View {
        if let segments {
            FlowLayout {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    VStack(spacing: 0) {
                        Text(segment.ruby ?? " ").font(settings.karaokeFont(scale: 0.45))
                        Text(segment.base).font(settings.karaokeFont())
                    }
                }
            }
            .foregroundStyle(color)
        } else {
            Text(text)
                .font(settings.karaokeFont())
                .foregroundStyle(color)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
