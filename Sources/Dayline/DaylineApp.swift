import AppKit
import DaylineCore
import SwiftUI

@main
struct DaylineApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // Dayline is light mode only.
        app.appearance = NSAppearance(named: .aqua)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    let model = AppModel.shared
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var windows: [String: NSWindow] = [:]
    private var overlayWindows: [NSWindow] = []
    private var sessionWindowEventID: String?
    private var eventMonitor: Any?
    private var statusDot: NSView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildStatusItem()
        buildPopover()
        buildMenu()
        wireModel()
        model.start()
        if ProcessInfo.processInfo.environment["DAYLINE_DEMO"] == "1" {
            model.evaluate(forceTick: true)
        }
        #if DEBUG
        if let show = ProcessInfo.processInfo.environment["DAYLINE_SHOW"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.handleShow(show)
            }
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.saveNow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = statusImage()
        button.imagePosition = .imageLeading
        button.font = .systemFont(ofSize: 11.5, weight: .medium)
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        let dot = NSView(frame: .zero)
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 2.5
        dot.isHidden = true
        button.addSubview(dot)
        statusDot = dot
        updateStatusItem()
    }

    private func statusImage() -> NSImage? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("MenuBarIcon.png"),
            Bundle.main.resourceURL?.appendingPathComponent("MenuBarIcon@2x.png"),
        ].compactMap { $0 }
        for url in candidates {
            if let image = NSImage(contentsOf: url) {
                image.isTemplate = true
                image.size = NSSize(width: 18, height: 18)
                return image
            }
        }
        let fallback = NSImage(systemSymbolName: "figure.walk", accessibilityDescription: "Dayline")
        fallback?.isTemplate = true
        return fallback
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showStatusMenu()
            return
        }
        togglePopover()
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            model.isPopoverOpen = true
            model.evaluate(forceTick: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                Task { @MainActor in self?.closePopover() }
            }
        }
    }

    private func closePopover() {
        popover.performClose(nil)
        model.isPopoverOpen = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        statusItem.button?.state = .off
    }

    private func buildPopover() {
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .aqua)
        let host = NSHostingController(rootView: PopoverView().environmentObject(model).daylineTheme())
        host.view.frame = NSRect(x: 0, y: 0, width: 392, height: 640)
        popover.contentSize = NSSize(width: 392, height: 640)
        popover.contentViewController = host
    }

    private func showStatusMenu() {
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Dayline", action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        if model.today?.end == nil, model.today?.start != nil {
            let brk = NSMenuItem(title: "Start a break", action: #selector(menuBreak), keyEquivalent: "")
            brk.target = self
            menu.addItem(brk)
        }
        if model.today?.start == nil {
            let start = NSMenuItem(title: "Start day", action: #selector(menuStartDay), keyEquivalent: "")
            start.target = self
            menu.addItem(start)
        } else if model.today?.end == nil {
            let end = NSMenuItem(title: "End day", action: #selector(menuEndDay), keyEquivalent: "")
            end.target = self
            menu.addItem(end)
        }
        let off = NSMenuItem(title: model.today?.isOff == true ? "Back on today" : "Off today",
                             action: #selector(menuOff), keyEquivalent: "")
        off.target = self
        menu.addItem(off)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Dayline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuOpen() { togglePopover() }
    @objc private func menuBreak() { model.startBreakNow() }
    @objc private func menuStartDay() { model.startDay() }
    @objc private func menuEndDay() { model.endDay() }
    @objc private func menuOff() { model.toggleOffToday() }

    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        let decision = model.decision
        var title = ""
        var dotColor: NSColor?
        if decision.phase == .dayOff {
            title = ""
        } else if decision.phase == .inBreak {
            title = "Break"
            dotColor = NSColor.daylineCalm
        } else if decision.isDue {
            title = decision.step == .overlay ? "Break" : (decision.kind?.shortTitle ?? "Break")
            dotColor = NSColor.daylineAccent
        } else if decision.isPausedByMedia && decision.waitingForMeeting != nil {
            title = "In call"
        } else if let seconds = decision.secondsUntilDue, seconds <= 60 * 60 {
            let minutes = max(1, Int(ceil(Double(seconds) / 60)))
            title = "\(minutes)m"
        } else if decision.isFocusActive {
            title = "Focus"
        }
        if dotColor == nil, decision.phase != .dayOff,
           !model.settings.garmin.connected, !model.state.settings.showDemoData {
            dotColor = NSColor.daylineWarm
        }
        button.title = title.isEmpty ? "" : " " + title
        button.contentTintColor = .labelColor
        button.toolTip = decision.isDue
            ? "\(decision.exercise?.displayTitle ?? "Break") — \(decision.why)"
            : decision.why

        if let dot = statusDot {
            if let color = dotColor {
                dot.isHidden = false
                dot.layer?.backgroundColor = color.cgColor
                dot.frame = NSRect(x: 12,
                                   y: max(0, button.bounds.maxY - 8),
                                   width: 5, height: 5)
                dot.autoresizingMask = [.maxXMargin, .minYMargin]
            } else {
                dot.isHidden = true
            }
        }
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Dayline", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(withTitle: "Journal…", action: #selector(menuJournal), keyEquivalent: "j")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Dayline", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        window.addItem(withTitle: "Today's plan", action: #selector(menuPlan), keyEquivalent: "p").target = self
        window.addItem(withTitle: "Summaries", action: #selector(menuSummaries), keyEquivalent: "y").target = self
        windowItem.submenu = window
        NSApp.mainMenu = main
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Dayline"
        alert.informativeText = "A workday coach that gets you out of the chair.\n\nLocal-first. Calendar and idle signals stay on this Mac."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func menuSettings() { show(.settings) }
    @objc private func menuJournal() { show(.journal) }
    @objc private func menuPlan() { show(.plan) }
    @objc private func menuSummaries() { show(.summaries) }

    // MARK: - Model wiring

    private func wireModel() {
        model.requestWindow = { [weak self] route in
            self?.show(route)
        }
        model.closePopover = { [weak self] in
            self?.closePopover()
        }
        model.onDecisionChanged = { [weak self] in
            self?.updateStatusItem()
        }
        NotificationCenter.default.addObserver(forName: .daylineShowOverlay, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.showOverlay() }
        }
        NotificationCenter.default.addObserver(forName: .daylineHideOverlay, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.hideOverlay() }
        }
    }

    // Screenshot hooks for development builds only (scripts/build.sh --debug).
    #if DEBUG
    private func handleShow(_ value: String) {
        defer { scheduleCapture(value) }
        if value.hasPrefix("settings-") {
            let name = String(value.dropFirst("settings-".count))
            if let tab = SettingsTab.allCases.first(where: { $0.rawValue.lowercased() == name }) {
                model.settingsTab = tab
            }
            show(.settings)
            return
        }
        switch value {
        case "settings": show(.settings)
        case "journal": show(.journal)
        case "summaries": show(.summaries)
        case "year": model.summaryTab = .year; show(.summaries)
        case "week": model.summaryTab = .week; show(.summaries)
        case "plan": show(.plan)
        case "reflection": model.openReflection()
        case "checkin": show(.checkIn)
        case "popover": togglePopover()
        case "overlay": showOverlay()
        case "session": model.startBreakNow()
        default: togglePopover()
        }
    }

    // MARK: - Debug capture

    private func scheduleCapture(_ value: String) {
        guard let path = ProcessInfo.processInfo.environment["DAYLINE_CAPTURE"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            let view: NSView?
            if value == "popover" {
                view = self.popover.contentViewController?.view
            } else if value == "overlay" {
                view = self.overlayWindows.first?.contentView
            } else if let window = self.windows[value] {
                view = window.contentView
            } else {
                view = NSApp.keyWindow?.contentView
                    ?? self.windows.values.first(where: { $0.isVisible })?.contentView
                    ?? NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil })?.contentView
            }
            guard let view else { return }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            if let data = rep.representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
    #endif

    // MARK: - Windows

    private func show(_ route: WindowRoute) {
        if route == .session { openSessionWindow(); return }
        closePopover()
        let key = route.rawValue
        if route == .checkIn, let existing = windows[key] {
            // A check-in window left open shows the previous, already saved
            // check-in. Each request gets a fresh form.
            existing.contentView = NSHostingView(rootView: checkInView())
        }
        if let existing = windows[key] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window: NSWindow
        switch route {
        case .journal:
            window = makeWindow(title: "Journal", size: NSSize(width: 860, height: 640), route: route)
            window.contentView = NSHostingView(rootView: JournalView().environmentObject(model).daylineTheme())
        case .reflection:
            window = makeWindow(title: "End of day", size: NSSize(width: 820, height: 760), route: route)
            window.contentView = NSHostingView(rootView: ReflectionView().environmentObject(model).daylineTheme())
        case .summaries:
            window = makeWindow(title: "Summaries", size: NSSize(width: 1020, height: 760), route: route)
            window.contentView = NSHostingView(rootView: SummariesView().environmentObject(model).daylineTheme())
        case .settings:
            window = makeWindow(title: "Dayline Settings", size: NSSize(width: 900, height: 700), route: route)
            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(model).daylineTheme())
        case .plan:
            window = makeWindow(title: "Today's plan", size: NSSize(width: 760, height: 720), route: route)
            window.contentView = NSHostingView(rootView: PlanView().environmentObject(model).daylineTheme())
        case .checkIn:
            window = makeWindow(title: "How are you doing?", size: NSSize(width: 520, height: 680), route: route)
            window.contentView = NSHostingView(rootView: checkInView())
        case .insight:
            window = makeWindow(title: "Insights", size: NSSize(width: 760, height: 600), route: route)
            window.contentView = NSHostingView(rootView: SummariesView().environmentObject(model).daylineTheme())
        case .session:
            return
        }
        windows[key] = window
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func checkInView() -> some View {
        let source = model.nextCheckInSource
        model.nextCheckInSource = .manual
        return CheckInView(source: source).environmentObject(model).daylineTheme()
    }

    private func makeWindow(title: String, size: NSSize, route: WindowRoute) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = title
        window.identifier = NSUserInterfaceItemIdentifier("dayline." + route.rawValue)
        window.minSize = NSSize(width: 480, height: 420)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor.daylineCanvas
        window.titlebarAppearsTransparent = false
        return window
    }

    private func openSessionWindow() {
        guard let session = model.session else { return }
        if let existing = windows["session"] {
            if sessionWindowEventID == session.id {
                // Same session: bring its window forward instead of replacing it.
                existing.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            // A different session: closing the old window must not abandon the new one.
            sessionWindowEventID = nil
            existing.close()
        }
        sessionWindowEventID = session.id
        let window = makeWindow(title: session.exercise.name, size: NSSize(width: 560, height: 660), route: .session)
        window.styleMask = [.titled, .closable]
        window.identifier = NSUserInterfaceItemIdentifier("dayline.session")
        window.contentView = NSHostingView(rootView: SessionView().environmentObject(model).daylineTheme())
        window.delegate = self
        windows["session"] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        for (key, value) in windows where value === window {
            windows.removeValue(forKey: key)
        }
        if window.identifier?.rawValue == "dayline.session",
           let current = model.session, current.id == sessionWindowEventID {
            sessionWindowEventID = nil
            model.abandonSession()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        model.isPopoverOpen = false
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    // MARK: - Overlay

    private func showOverlay() {
        guard overlayWindows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless],
                                       backing: .buffered, defer: false)
            window.isOpaque = false
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = false
            window.contentView = NSHostingView(rootView: BreakOverlayView().environmentObject(model).daylineTheme())
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKey()
    }

    private func hideOverlay() {
        for window in overlayWindows {
            window.orderOut(nil)
            window.close()
        }
        overlayWindows.removeAll()
    }
}

/// A borderless window cannot take keyboard focus by default, which would leave
/// the break overlay unusable without a mouse (no Tab, Return or Escape).
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
