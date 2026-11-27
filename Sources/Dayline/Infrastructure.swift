import AppKit
import AVFoundation
import Carbon.HIToolbox
import CoreAudio
import CoreMediaIO
import EventKit
import DaylineCore
import IOKit
import ServiceManagement
import SwiftUI
import UserNotifications

// MARK: - Idle time

final class IdleMonitor {
    init() {}

    /// Seconds since the last HID input (keyboard, mouse, trackpad).
    func idleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return 0 }
        defer { IOObjectRelease(service) }

        guard let property = IORegistryEntryCreateCFProperty(service, "HIDIdleTime" as CFString,
                                                             kCFAllocatorDefault, 0)?.takeRetainedValue(),
              let number = property as? NSNumber else { return 0 }
        return number.doubleValue / 1_000_000_000
    }
}

// MARK: - Media activity (camera, microphone, screen sharing)

final class MediaMonitor {
    private var micStartedAt: Date?

    func sample(now: Date, hasCalendarEvent: Bool) -> MediaState {
        let mic = microphoneInUse()
        let ignored = mic.ignoredOnly
        let camera = cameraInUse()
        let sharing = screenSharingLikely()

        // The open-microphone cap is about a mic left on with no meeting, so
        // time inside a calendar event does not count towards it.
        if mic.running && !ignored && !hasCalendarEvent {
            if micStartedAt == nil { micStartedAt = now }
        } else {
            micStartedAt = nil
        }
        let openMinutes = micStartedAt.map { max(0, Int(now.timeIntervalSince($0) / 60)) } ?? 0

        return MediaState(cameraInUse: camera,
                          microphoneInUse: mic.running,
                          screenSharing: sharing,
                          openMicrophoneMinutes: openMinutes,
                          microphoneIgnored: ignored)
    }

    // MARK: Microphone

    private func microphoneInUse() -> (running: Bool, ignoredOnly: Bool) {
        guard let device = defaultInputDevice() else { return (false, false) }
        guard deviceIsRunning(device) else { return (false, false) }

        let ignoreList = SettingsRef.ignoreBundleIDs
        let users = audioInputUsers()
        if users.isEmpty {
            // Without per-process detail, a running input device is a real signal.
            return (true, false)
        }
        let ignoredUsers = users.filter { bundleID in
            guard let bundleID else { return false }
            return ignoreList.contains(bundleID)
        }
        let realUsers = users.filter { bundleID in
            guard let bundleID else { return true }
            return !ignoreList.contains(bundleID)
        }
        if realUsers.isEmpty && !ignoredUsers.isEmpty { return (true, true) }
        return (true, false)
    }

    private func defaultInputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                0, nil, &size, &device)
        return status == noErr ? device : nil
    }

    private func deviceIsRunning(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
    }

    /// Bundle identifiers of processes currently capturing input.
    private func audioInputUsers() -> [String?] {
        if #available(macOS 14.4, *) {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyProcessObjectList,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            var size: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address,
                                                 0, nil, &size) == noErr, size > 0 else { return [] }
            let count = Int(size) / MemoryLayout<AudioObjectID>.size
            var objects = [AudioObjectID](repeating: 0, count: count)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                             0, nil, &size, &objects) == noErr else { return [] }

            var result: [String?] = []
            for object in objects {
                var runningAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioProcessPropertyIsRunningInput,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                var running: UInt32 = 0
                var runningSize = UInt32(MemoryLayout<UInt32>.size)
                guard AudioObjectGetPropertyData(object, &runningAddress, 0, nil,
                                                 &runningSize, &running) == noErr, running != 0 else { continue }

                var pidAddress = AudioObjectPropertyAddress(
                    mSelector: kAudioProcessPropertyPID,
                    mScope: kAudioObjectPropertyScopeGlobal,
                    mElement: kAudioObjectPropertyElementMain)
                var pid: pid_t = 0
                var pidSize = UInt32(MemoryLayout<pid_t>.size)
                guard AudioObjectGetPropertyData(object, &pidAddress, 0, nil, &pidSize, &pid) == noErr else { continue }

                var bundleID: String?
                if let app = NSRunningApplication(processIdentifier: pid) {
                    bundleID = app.bundleIdentifier
                }
                result.append(bundleID)
            }
            return result
        }
        return []
    }

    // MARK: Camera

    private func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address,
                                            UInt32(MemoryLayout<CMIOObjectPropertyAddress>.size),
                                            nil, &size) == noErr, size > 0 else { return false }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address,
                                        UInt32(MemoryLayout<CMIOObjectPropertyAddress>.size),
                                        nil, size, &size, &devices) == noErr else { return false }

        for device in devices {
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &runningAddress,
                                         UInt32(MemoryLayout<CMIOObjectPropertyAddress>.size),
                                         nil, runningSize, &runningSize, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }

    // MARK: Screen sharing

    /// Screen sharing without the Screen Recording permission can only be
    /// inferred. Remote-control and dedicated sharing apps are reliable; browser
    /// tab sharing is covered by the microphone/camera checks while unmuted.
    private func screenSharingLikely() -> Bool {
        let sharingBundleIDs: Set<String> = [
            "com.apple.ScreenSharing", "com.apple.RemoteDesktop",
            "com.teamviewer.TeamViewer", "com.anydesk.AnyDesk",
            "com.parsecgaming.parsec", "com.realvnc.vncviewer",
            "com.jumpdesktop.JumpDesktop", "com.microsoft.rdc.macos",
            "com.zoom.xos.share", "us.zoom.xos",
        ]
        return NSWorkspace.shared.runningApplications.contains { app in
            guard let id = app.bundleIdentifier else { return false }
            return sharingBundleIDs.contains(id) && app.isActive
        }
    }
}

/// The media monitor reads the ignore list without reaching back into the model.
enum SettingsRef {
    nonisolated(unsafe) static var ignoreBundleIDs: [String] = []
}

// MARK: - Calendar

struct CalendarInfo: Identifiable, Hashable {
    var id: String
    var title: String
    var source: String
    var color: NSColor
}

@MainActor
final class CalendarService: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var calendars: [CalendarInfo] = []
    @Published private(set) var lastError: String?
    @Published private(set) var accessDenied = false

    private let store = EKEventStore()
    private var observer: NSObjectProtocol?
    var onChange: (() -> Void)?

    init() {
        refreshStatus()
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func refreshStatus() {
        let status = EKEventStore.authorizationStatus(for: .event)
        authorized = status == .fullAccess
        accessDenied = status == .denied || status == .restricted
        if authorized { loadCalendars() }
    }

    func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            await MainActor.run {
                self.authorized = granted
                self.accessDenied = !granted
                if granted { self.loadCalendars() }
            }
        } catch {
            await MainActor.run {
                self.lastError = error.localizedDescription
                self.accessDenied = true
            }
        }
    }

    private func loadCalendars() {
        calendars = store.calendars(for: .event).map { cal in
            CalendarInfo(id: cal.calendarIdentifier, title: cal.title,
                         source: cal.source.title, color: cal.color)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func fetch(from start: Date, to end: Date, selectedIDs: [String]) -> [CalendarEvent] {
        guard authorized else { return [] }
        let all = store.calendars(for: .event)
        let chosen = selectedIDs.isEmpty ? all : all.filter { selectedIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: chosen)
        let events = store.events(matching: predicate)
        return events.compactMap { event -> CalendarEvent? in
            guard let startDate = event.startDate, let endDate = event.endDate else { return nil }
            let declined = event.attendees?.contains { attendee in
                attendee.isCurrentUser && attendee.participantStatus == .declined
            } ?? false
            let busy = event.availability != .free
            return CalendarEvent(
                id: event.eventIdentifier ?? UUID().uuidString,
                title: event.title ?? "Untitled",
                start: startDate,
                end: endDate,
                isAllDay: event.isAllDay,
                isBusy: busy,
                isDeclined: declined,
                attendeeCount: event.attendees?.count,
                isRecurring: (event.recurrenceRules?.count ?? 0) > 0,
                calendarID: event.calendar.calendarIdentifier,
                calendarTitle: event.calendar.title
            )
        }
    }
}

// MARK: - Notifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let breakCategory = "DAYLINE_BREAK"
    static let windDownCategory = "DAYLINE_WINDDOWN"
    static let standingCategory = "DAYLINE_STANDING"

    var onStartBreak: (() -> Void)?
    var onSnooze: (() -> Void)?
    var onSkip: (() -> Void)?
    var onOpenReflection: (() -> Void)?
    var onWindDownLater: (() -> Void)?
    var onTakeStandingCall: (() -> Void)?
    private var didRequestAuthorization = false

    private var configuredSnoozeMinutes: Int?

    func configure(snoozeMinutes: Int) {
        guard configuredSnoozeMinutes != snoozeMinutes else { return }
        configuredSnoozeMinutes = snoozeMinutes
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: "START", title: "Start", options: [.foreground])
        let snooze = UNNotificationAction(identifier: "SNOOZE", title: "Snooze \(snoozeMinutes) min", options: [])
        let skip = UNNotificationAction(identifier: "SKIP", title: "Skip", options: [.foreground])
        let breakCategory = UNNotificationCategory(identifier: Self.breakCategory,
                                                   actions: [start, snooze, skip],
                                                   intentIdentifiers: [], options: [])
        let reflect = UNNotificationAction(identifier: "REFLECT", title: "Reflect now", options: [.foreground])
        let later = UNNotificationAction(identifier: "LATER", title: "In 15 min", options: [])
        let windDown = UNNotificationCategory(identifier: Self.windDownCategory,
                                              actions: [reflect, later], intentIdentifiers: [], options: [])
        let stand = UNNotificationAction(identifier: "STAND", title: "Take it standing", options: [.foreground])
        let dismiss = UNNotificationAction(identifier: "DISMISS", title: "Not this time", options: [])
        let standing = UNNotificationCategory(identifier: Self.standingCategory,
                                              actions: [stand, dismiss], intentIdentifiers: [], options: [])
        center.setNotificationCategories([breakCategory, windDown, standing])
    }

    /// Asks the first time a notification is actually needed, not at launch,
    /// then posts. Posting before the answer would drop that first notification.
    private func post(_ request: UNNotificationRequest) {
        let center = UNUserNotificationCenter.current()
        guard !didRequestAuthorization else {
            center.add(request)
            return
        }
        didRequestAuthorization = true
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            try? await center.add(request)
        }
    }

    func postBreak(title: String, body: String, dueAt: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.breakCategory
        content.threadIdentifier = "dayline-break"
        post(UNNotificationRequest(identifier: "break-\(Int(dueAt.timeIntervalSince1970))",
                                   content: content, trigger: nil))
    }

    func postWindDown(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Time to wind down"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = Self.windDownCategory
        post(UNNotificationRequest(identifier: "winddown-\(DayKey.make(Date()))",
                                   content: content, trigger: nil))
    }

    func postStandingCall(eventID: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil
        content.categoryIdentifier = Self.standingCategory
        post(UNNotificationRequest(identifier: "standing-\(eventID)", content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        Task { @MainActor in
            switch action {
            case "START": self.onStartBreak?()
            case "SNOOZE": self.onSnooze?()
            case "SKIP": self.onSkip?()
            case "REFLECT": self.onOpenReflection?()
            case "STAND": self.onTakeStandingCall?()
            case "LATER": self.onWindDownLater?()
            case UNNotificationDefaultActionIdentifier:
                NSApp.activate(ignoringOtherApps: true)
            default:
                break   // "Not this time" and a dismissed banner need no action.
            }
            completionHandler()
        }
    }
}

// MARK: - Global hotkey

final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    var onPress: (() -> Void)?

    func register(_ setting: HotkeySetting) -> Bool {
        unregister()
        installHandlerIfNeeded()

        var modifiers: UInt32 = 0
        if setting.command { modifiers |= UInt32(cmdKey) }
        if setting.option { modifiers |= UInt32(optionKey) }
        if setting.control { modifiers |= UInt32(controlKey) }
        if setting.shift { modifiers |= UInt32(shiftKey) }
        let hotKeyID = EventHotKeyID(signature: OSType(0x444C4E45), id: 1) // 'DLNE'
        let status = RegisterEventHotKey(UInt32(setting.keyCode), modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    /// The handler is installed once; re-registering only swaps the key.
    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onPress?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    deinit {
        unregister()
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    static func describe(_ setting: HotkeySetting) -> String {
        var out = ""
        if setting.control { out += "⌃" }
        if setting.option { out += "⌥" }
        if setting.shift { out += "⇧" }
        if setting.command { out += "⌘" }
        let names: [UInt32: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
                                       8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
                                       16: "Y", 17: "T", 32: "U", 34: "I", 31: "O", 35: "P",
                                       37: "L", 38: "J", 40: "K", 45: "N", 46: "M"]
        out += names[setting.keyCode] ?? "?"
        return out
    }
}

// MARK: - Launch at login

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - Sounds

enum SoundPlayer {
    static func play(_ name: String, enabled: Bool) {
        guard enabled else { return }
        NSSound(named: name)?.play()
    }

    static func breakStart(enabled: Bool) { play("Glass", enabled: enabled) }
    static func breakEnd(enabled: Bool) { play("Pop", enabled: enabled) }
    static func tick(enabled: Bool) { play("Tink", enabled: enabled) }
}
