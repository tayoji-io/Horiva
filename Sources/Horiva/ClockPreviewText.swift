import AppKit
import SwiftUI

/// Update the clock's text without invalidating the SwiftUI settings graph.
struct ClockPreviewText: NSViewRepresentable {
    @ObservedObject var store: SettingsStore
    func makeNSView(context: Context) -> PreviewClockHost { PreviewClockHost() }
    func updateNSView(_ view: PreviewClockHost, context: Context) { view.configure(store: store) }
}

final class PreviewClockHost: NSView {
    private let field = NSTextField(labelWithString: "")
    private weak var store: SettingsStore?
    private var timer: Timer?
    private var measuredSize = NSSize(width: 1, height: 18)

    override init(frame: NSRect) {
        super.init(frame: frame)
        field.textColor = .white
        field.lineBreakMode = .byClipping
        field.autoresizingMask = [.width, .height]
        field.frame = bounds
        addSubview(field)
    }
    required init?(coder: NSCoder) { nil }
    override var intrinsicContentSize: NSSize { measuredSize }

    func configure(store: SettingsStore) {
        self.store = store
        field.font = store.settings.font == .monospaced
            ? .monospacedSystemFont(ofSize: 13, weight: .regular)
            : .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        refresh()
        schedule()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        schedule()
    }

    private func refresh() {
        guard let store else { return }
        let text = store.renderer.title(at: Date())
        if field.stringValue != text { field.stringValue = text }
        let textSize = (text as NSString).size(withAttributes: [.font: field.font!])
        let size = NSSize(width: ceil(textSize.width) + 4, height: max(18, ceil(textSize.height)))
        if size != measuredSize {
            measuredSize = size
            invalidateIntrinsicContentSize()
        }
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard window != nil, let store else { return }
        refresh()
        let interval = store.settings.refreshInterval
        let timer = Timer(fire: store.settings.nextRefresh(after: Date()), interval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = min(interval * 0.05, 0.25)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit { timer?.invalidate() }
}
