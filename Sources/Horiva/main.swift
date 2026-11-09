import AppKit
import SwiftUI
import Combine
import ClockCore
import ServiceManagement

final class SettingsStore: ObservableObject {
    @Published private(set) var settings: ClockSettings
    private let key = "clockSettings.v1"
    let renderer = ClockRenderer(settings: .defaults)
    var timelineSchedule: PeriodicTimelineSchedule {
        let interval = settings.refreshInterval
        return .init(from: settings.nextRefresh(after: Date()).addingTimeInterval(-interval), by: interval)
    }
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    @Published var serviceError: String?

    func refreshLoginStatus() { loginStatus = SMAppService.mainApp.status }

    func setLaunchAtLogin(_ enabled: Bool) {
        serviceError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else if [.enabled, .requiresApproval].contains(SMAppService.mainApp.status) { try SMAppService.mainApp.unregister() }
        } catch { serviceError = error.localizedDescription }
        refreshLoginStatus()
    }

    func restoreDefaults() {
        setLaunchAtLogin(false)
        guard serviceError == nil else { return }
        update { $0 = .defaults }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(ClockSettings.self, from: data) {
            settings = saved.normalized()
        } else {
            settings = .defaults
        }
        renderer.update(settings)
        refreshLoginStatus()
    }

    func update(_ change: (inout ClockSettings) -> Void) {
        var next = settings
        change(&next)
        let normalized = next.normalized()
        renderer.update(normalized)
        settings = normalized
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: key) }
    }
}

/// Keep the settings scrollbars floating without changing macOS preferences.
final class SettingsHostingView: NSHostingView<SettingsView> {
    private weak var configuredScrollView: NSScrollView?
    override func layout() {
        super.layout()
        if configuredScrollView == nil { configureScrollers(in: self) }
    }

    private func configureScrollers(in view: NSView) {
        guard configuredScrollView == nil else { return }
        if let scrollView = view as? NSScrollView {
            if scrollView.scrollerStyle != .overlay { scrollView.scrollerStyle = .overlay }
            scrollView.autohidesScrollers = true
            scrollView.verticalScroller?.controlSize = .small
            configuredScrollView = scrollView
            return
        }
        for child in view.subviews { configureScrollers(in: child) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let store = SettingsStore()
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var subscription: AnyCancellable?
    private var formatters: [(ClockZone, DateFormatter)] = []
    private var settingsWindow: NSWindow?
    private let menu = NSMenu()
    private var converterWindow: NSWindow?
    private var calendarWindow: NSWindow?
    private var activeSettings = ClockSettings.defaults
    private var wakeObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "ZoneBarClock"
        statusItem.menu = menu
        subscription = store.$settings.sink { [weak self] settings in
            guard let self else { return }
            self.activeSettings = settings
            self.settingsWindow?.title = settings.language.localized("时屿 · Horiva 设置")
            self.converterWindow?.title = settings.language.localized("跨时区会议换算器")
            self.calendarWindow?.title = settings.language.localized("日历与时区")
            self.statusItem.button?.font = settings.font == .monospaced
                ? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
                : NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            self.formatters = settings.zones.map { ($0, settings.formatter(for: $0)) }
            self.statusItem.button?.toolTip = settings.zones.map { "\($0.label) — \($0.id)" }.joined(separator: "\n")
            DispatchQueue.main.async { [weak self] in
                self?.rebuildMenu()
                self?.resizeConverter()
            }
            self.refresh()
            self.configureTimer()
        }
        wakeObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh(); self?.configureTimer() })
        wakeObservers.append(NotificationCenter.default.addObserver(forName: NSNotification.Name.NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in self?.refresh(); self?.configureTimer() })
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
    }

    private func configureTimer() {
        timer?.invalidate()
        let interval = activeSettings.refreshInterval
        let timer = Timer(fire: activeSettings.nextRefresh(after: Date()), interval: interval, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = min(interval * 0.05, 0.25)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func refresh() {
        let now = Date()
        let rows = formatters.map { ($0.0, $0.1.string(from: now)) }
        let strings = rows.map { "\($0.0.label) \($0.1)" }
        let title = rows.map { $0.0.displayText(time: $0.1) }.joined(separator: activeSettings.separator.text)
        if statusItem.button?.title != title {
            statusItem.button?.title = title
            statusItem.button?.setAccessibilityLabel(activeSettings.language.localized("多时区时钟") + ": " + strings.joined(separator: ", "))
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        if activeSettings.showCalendar {
            addMenuAction("日历与时区", icon: "calendar", action: #selector(showCalendar))
        }
        addMenuAction("跨时区会议换算器", icon: "arrow.triangle.2.circlepath", action: #selector(showConverter), key: "k")
        menu.addItem(.separator())
        addMenuAction("打开偏好设置…", icon: "gearshape", action: #selector(showSettings), key: ",")
        addMenuAction("退出 Horiva", icon: "power", action: #selector(quitApp), key: "q")
    }

    @discardableResult
    private func addMenuAction(_ title: String, icon: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: activeSettings.language.localized(title), action: action, keyEquivalent: key)
        item.target = self
        item.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
        menu.addItem(item)
        return item
    }

    @objc private func showCalendar() { showTimeWindow(meetingMode: false) }
    @objc private func showConverter() { showTimeWindow(meetingMode: true) }

    private func showTimeWindow(meetingMode: Bool) {
        let existing = meetingMode ? converterWindow : calendarWindow
        let window: NSWindow
        if let existing { window = existing }
        else {
            let content = NSHostingView(rootView: TimeDetailsView(store: store, meetingMode: meetingMode))
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 500), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = activeSettings.language.localized(meetingMode ? "跨时区会议换算器" : "日历与时区")
            window.contentView = content
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            if meetingMode { converterWindow = window } else { calendarWindow = window }
        }
        resizeConverter()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func resizeConverter() {
        for window in [converterWindow, calendarWindow].compactMap({ $0 }) {
            guard let content = window.contentView else { continue }
            content.layoutSubtreeIfNeeded()
            window.setContentSize(content.fittingSize)
        }
    }

    private func showMenuPreview() {
        guard let content = settingsWindow?.contentView else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: content.bounds.maxX - 440, y: 30), in: content)
    }

    @objc private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsHostingView(rootView: SettingsView(store: store, onPreview: { [weak self] in self?.showMenuPreview() }, onDone: { [weak self] in self?.settingsWindow?.performClose(nil) }))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = activeSettings.language.localized("时屿 · Horiva 设置")
            window.delegate = self
            window.contentView = view
            window.minSize = NSSize(width: 760, height: 600)
            window.setContentSize(NSSize(width: 800, height: 760))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.makeFirstResponder(nil)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow { settingsWindow = nil }
        if window === converterWindow { converterWindow = nil }
        if window === calendarWindow { calendarWindow = nil }
        window.contentView = nil
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
