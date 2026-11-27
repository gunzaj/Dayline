import AppKit
import DaylineCore
import SwiftUI

@MainActor
final class SettingsUI: ObservableObject {
    @Published var garminEmail = ""
    @Published var garminPassword = ""
    @Published var garminMFA = ""
    @Published var apiKeyDraft = ""
    @Published var hasStoredKey = false
    @Published var newEquipmentName = ""
    @Published var newEquipmentMinutes = 10
    @Published var newEquipmentStanding = false
    @Published var aiTestResult: String?
    @Published var aiTestFailed = false
    @Published var newPrompt = ""
    @Published var showKey = false
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var ui = SettingsUI()

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Divider().overlay(DL.line)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader(eyebrow: model.settingsTab.rawValue,
                               title: title,
                               subtitle: subtitle)
                    Group {
                        switch model.settingsTab {
                        case .schedule: scheduleTab
                        case .breaks: breaksTab
                        case .equipment: equipmentTab
                        case .calendar: calendarTab
                        case .garmin: garminTab
                        case .journal: journalTab
                        case .ai: aiTab
                        case .general: generalTab
                        }
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "lock")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Dayline keeps everything on this Mac. Calendar events and Garmin readings are read-only; nothing is written back.")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(DL.muted)
                    .padding(.top, 8)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: 780, alignment: .leading)
            }
            .background(DL.window)
        }
        .background(DL.window)
        .onAppear {
            ui.garminEmail = model.settings.garmin.email
            ui.hasStoredKey = model.hasStoredAPIKey()
        }
        .onChange(of: model.settings.garmin.connected) { _, connected in
            if connected { ui.garminPassword = ""; ui.garminMFA = "" }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Settings")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DL.muted)
                .padding(.horizontal, 10)
                .padding(.top, 20)
                .padding(.bottom, 8)
            ForEach(SettingsTab.allCases) { tab in
                sidebarRow(tab)
            }
            Spacer()
            Button {
                model.openPlan()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DL.accent)
                        .frame(width: 16)
                    Text("Today's plan")
                        .font(.system(size: 12.5))
                        .foregroundStyle(DL.ink)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DL.sidebar)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DL.line).frame(width: 1)
        }
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        let active = model.settingsTab == tab
        return Button {
            model.settingsTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(active ? DL.accent : DL.muted)
                    .frame(width: 16)
                Text(tab.rawValue)
                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(DL.ink)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? DL.accentSoft : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(active ? DL.accentBorder : Color.clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
    }

    private var title: String {
        switch model.settingsTab {
        case .schedule: return "When the day runs"
        case .breaks: return "How breaks work"
        case .equipment: return "What you have"
        case .calendar: return "Read-only calendar"
        case .garmin: return "Read-only Garmin"
        case .journal: return "Journal and check-ins"
        case .ai: return "AI insights"
        case .general: return "General"
        }
    }

    private var subtitle: String {
        switch model.settingsTab {
        case .schedule: return "Work hours, lunch window and wind-down. Breaks are only planned inside these hours."
        case .breaks: return "Intervals, targets, escalation and how a break is verified."
        case .equipment: return "Only exercises you can do get suggested."
        case .calendar: return "Dayline reads busy blocks to find gaps. It never edits an event."
        case .garmin: return "Stress, Body Battery and sleep set the intensity of the day."
        case .journal: return "Private notes, the 4×4 mood grid and the guided prompts."
        case .ai: return "Only the aggregates you allow leave this Mac. Keys live in the Keychain."
        case .general: return "Startup, appearance, sounds and data."
        }
    }

    // MARK: - Bindings

    private func bind<T>(_ keyPath: WritableKeyPath<AppSettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings[keyPath: keyPath] },
            set: { value in model.updateSettings { $0[keyPath: keyPath] = value } }
        )
    }

    private func timeField(_ keyPath: WritableKeyPath<AppSettings, TimeOfDay>) -> some View {
        TimeField(value: model.settings[keyPath: keyPath].display) { parsed in
            model.updateSettings { $0[keyPath: keyPath] = parsed }
        }
    }

    private func hourField(_ index: Int,
                           _ keyPath: WritableKeyPath<DayHoursSetting, TimeOfDay>) -> some View {
        TimeField(value: model.settings.dayHours.indices.contains(index)
                    ? model.settings.dayHours[index][keyPath: keyPath].display : "") { parsed in
            guard model.settings.dayHours.indices.contains(index) else { return }
            model.updateSettings { $0.dayHours[index][keyPath: keyPath] = parsed }
        }
    }

    private func numberField(_ value: Binding<Int>, width: CGFloat = 52) -> some View {
        TextField("", value: value, format: .number)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 12.5, design: .monospaced))
            .frame(width: width)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
    }


    // MARK: - Schedule

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            DlCard {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Work hours")
                    ForEach(Array(model.settings.dayHours.enumerated()), id: \.element.id) { index, day in
                        HStack(spacing: 10) {
                            Toggle("", isOn: Binding(
                                get: { day.enabled },
                                set: { value in model.updateSettings { $0.dayHours[index].enabled = value } }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                            .tint(DL.calm)
                            Text(day.name)
                                .font(.system(size: 12.5, weight: day.enabled ? .medium : .regular))
                                .foregroundStyle(day.enabled ? DL.ink : DL.muted)
                                .frame(width: 84, alignment: .leading)
                            hourField(index, \.start)
                            Text("to").font(.system(size: 11)).foregroundStyle(DL.muted)
                            hourField(index, \.end)
                            Spacer()
                            if day.enabled {
                                let hours = max(0, day.end.minutes - day.start.minutes)
                                Text("\(hours / 60) h \(hours % 60) min")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(DL.muted)
                            } else {
                                Chip(text: "Off", style: .plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Day boundaries")
                        .padding(.bottom, 4)
                    ToggleRow(title: "Start the day automatically",
                              subtitle: "When the Mac is awake at the start of work hours.",
                              isOn: bind(\.autoStartDay))
                    SettingRow("Wind-down", subtitle: "The prompt that offers to wrap up before the end.") {
                        timeField(\.windDown)
                    }
                    ToggleRow(title: "Offer to wrap up yesterday",
                              subtitle: "If yesterday has no reflection, ask once the next morning.",
                              isOn: bind(\.offerWrapUpYesterday))
                }
            }
        }
    }

    // MARK: - Breaks

    private var breaksTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Movement interval").padding(.bottom, 4)
                    SettingRow("Move every", subtitle: "A random point inside this range, timed around meetings.") {
                        HStack(spacing: 6) {
                            numberField(bind(\.moveIntervalMin))
                            Text("to").font(.system(size: 11)).foregroundStyle(DL.muted)
                            numberField(bind(\.moveIntervalMax))
                            Text("min").font(.system(size: 11)).foregroundStyle(DL.muted)
                        }
                    }
                    SettingRow("Longest seated stretch", subtitle: "The engine escalates once this is exceeded.") {
                        HStack(spacing: 6) {
                            Text("\(model.settings.moveIntervalMax + model.settings.escalationOverlayAfter) min")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(DL.muted)
                        }
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Daily targets").padding(.bottom, 4)
                    HStack(spacing: 10) {
                        targetBox("Standing / walking", value: bind(\.standingTargetMinutes), unit: "min")
                        targetBox("Breaks", value: bind(\.breaksTarget), unit: "taken")
                        targetBox("Breathing", value: bind(\.breathingTarget), unit: "sessions")
                        targetBox("Lunch", value: bind(\.lunchTargetMinutes), unit: "min")
                    }
                    .padding(.vertical, 6)
                    SettingRow("Lunch window", subtitle: "No break is booked over this window.") {
                        HStack(spacing: 6) {
                            timeField(\.lunchWindowStart)
                            Text("to").font(.system(size: 11)).foregroundStyle(DL.muted)
                            timeField(\.lunchWindowEnd)
                        }
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Escalation").padding(.bottom, 4)
                    SettingRow("Notification after", subtitle: "A quiet banner when the break first comes due.") {
                        HStack(spacing: 6) {
                            numberField(bind(\.escalationNotificationAfter))
                            Text("min late").font(.system(size: 11)).foregroundStyle(DL.muted)
                        }
                    }
                    SettingRow("Overlay after", subtitle: "A full-screen prompt on every display, every Space.") {
                        HStack(spacing: 6) {
                            numberField(bind(\.escalationOverlayAfter))
                            Text("min late").font(.system(size: 11)).foregroundStyle(DL.muted)
                        }
                    }
                    SettingRow("Snoozes", subtitle: "After this many, the only choices are start or skip.") {
                        HStack(spacing: 6) {
                            numberField(bind(\.snoozeLimit))
                            Text("×").font(.system(size: 11)).foregroundStyle(DL.muted)
                            numberField(bind(\.snoozeMinutes))
                            Text("min").font(.system(size: 11)).foregroundStyle(DL.muted)
                        }
                    }
                    SettingRow("Verification", subtitle: "Honor system credits the timer; auto + confirm waits for a signal.") {
                        SegmentedPicker(options: VerificationMode.allCases.map { ($0, $0.rawValue) },
                                        selection: bind(\.verification))
                            .frame(width: 230)
                    }
                    ToggleRow(title: "Pause while media plays",
                              subtitle: "Escalation stops while audio or video is playing. The time still counts.",
                              isOn: bind(\.pauseOnMedia))
                    SettingRow("Ignore microphones", subtitle: "Bundle IDs that do not count as a call.") {
                        Text("\(model.settings.micIgnoreBundleIDs.count) ignored")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DL.muted)
                    }
                    SettingRow("Open-mic cap", subtitle: "Never escalate to an overlay after this long on a call.") {
                        HStack(spacing: 6) {
                            numberField(bind(\.openMicCapMinutes))
                            Text("min").font(.system(size: 11)).foregroundStyle(DL.muted)
                        }
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Eyebrow(text: "Focus lengths")
                        Spacer()
                        Text("Shown in the popover")
                            .font(.system(size: 10)).foregroundStyle(DL.muted)
                    }
                    HStack(spacing: 8) {
                        ForEach(model.settings.focusLengths, id: \.self) { minutes in
                            Chip(text: minutes >= 60 ? "\(minutes / 60) h" : "\(minutes) min", style: .calm)
                        }
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Eyebrow(text: "Exercises")
                        Spacer()
                        Text("\(ExerciseLibrary.available(settings: model.settings).count) of \(ExerciseLibrary.everything(settings: model.settings).count) available")
                            .font(.system(size: 10.5)).foregroundStyle(DL.muted)
                    }
                    ForEach(ExerciseLibrary.everything(settings: model.settings)) { exercise in
                        HStack(spacing: 8) {
                            Toggle("", isOn: Binding(
                                get: { !model.settings.disabledExerciseIDs.contains(exercise.id) },
                                set: { on in
                                    model.updateSettings { settings in
                                        if on {
                                            settings.disabledExerciseIDs.removeAll { $0 == exercise.id }
                                        } else if !settings.disabledExerciseIDs.contains(exercise.id) {
                                            settings.disabledExerciseIDs.append(exercise.id)
                                        }
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .tint(DL.calm)
                            Text(exercise.name)
                                .font(.system(size: 12))
                            if let equipment = exercise.equipment {
                                Chip(text: equipment.title, style: .plain)
                            }
                            if exercise.kind == .custom {
                                Chip(text: "Your equipment", style: .plain)
                            }
                            Spacer()
                            Text("\(exercise.minutesLow)–\(exercise.minutesHigh) min")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(DL.muted)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func targetBox(_ label: String, value: Binding<Int>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10.5)).foregroundStyle(DL.muted)
            HStack(spacing: 4) {
                numberField(value, width: 46)
                Text(unit).font(.system(size: 10.5)).foregroundStyle(DL.muted)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(DL.field))
    }

    // MARK: - Equipment

    private var equipmentTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            DlCard {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "At your desk")
                    if model.settings.equipment.isEmpty && model.settings.customEquipment.isEmpty {
                        Text("No equipment. Bodyweight breaks and breathing are still suggested.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DL.muted)
                    }
                    ForEach(model.settings.equipment) { item in
                        builtInEquipmentRow(item)
                    }
                    ForEach(model.settings.customEquipment) { item in
                        customEquipmentRow(item)
                    }
                }
            }
            DlCard {
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: "Add equipment")
                    if !model.settings.missingBuiltInEquipment.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(model.settings.missingBuiltInEquipment) { kind in
                                Button {
                                    model.updateSettings { $0.addEquipment(kind) }
                                } label: {
                                    Label(kind.title, systemImage: "plus")
                                }
                                .buttonStyle(SecondaryButtonStyle())
                            }
                            Spacer()
                        }
                    }
                    Text("Something else? Give it a name and a session length. It gets a timed activity of its own.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("Name, for example Pull-up bar", text: $ui.newEquipmentName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                            .frame(width: 230)
                            .onSubmit { addNewEquipment() }
                        numberField($ui.newEquipmentMinutes, width: 46)
                        Text("min").font(.system(size: 11)).foregroundStyle(DL.muted)
                        Toggle("Counts as standing", isOn: $ui.newEquipmentStanding)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11.5))
                        Spacer()
                        Button("Add") { addNewEquipment() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(ui.newEquipmentName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            NoticeCard(title: "Why this matters",
                       message: "Switching off or removing a piece of equipment takes every exercise that needs it out of the picker. Activities you already logged stay in your history. Bodyweight breaks and breathing stay available.")
        }
    }

    private func addNewEquipment() {
        model.addCustomEquipment(name: ui.newEquipmentName,
                                 minutes: max(1, min(240, ui.newEquipmentMinutes)),
                                 countsAsStanding: ui.newEquipmentStanding)
        ui.newEquipmentName = ""
        ui.newEquipmentMinutes = 10
        ui.newEquipmentStanding = false
    }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "trash").font(.system(size: 11))
        }
        .buttonStyle(.plain)
        .foregroundStyle(DL.muted)
        .accessibilityLabel(label)
        .help(label)
    }

    private func builtInEquipmentRow(_ item: Equipment) -> some View {
        let kind = item.id
        return HStack(alignment: .top, spacing: 10) {
            Toggle(kind.title, isOn: Binding(
                get: { model.settings.isEquipmentEnabled(kind) },
                set: { value in model.updateSettings { $0.setEquipment(kind, enabled: value) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(DL.calm)
            VStack(alignment: .leading, spacing: 1) {
                Text(kind.title).font(.system(size: 12.5, weight: .medium))
                Text(kind.defaultNote)
                    .font(.system(size: 11))
                    .foregroundStyle(DL.muted)
            }
            Spacer()
            if item.enabled {
                CategoryPill(title: kind.breakKind.shortTitle)
            } else {
                Chip(text: "Off", style: .plain)
            }
            removeButton("Remove \(kind.title)") {
                model.updateSettings { $0.removeEquipment(kind) }
            }
        }
        .padding(.vertical, 5)
    }

    private func customEquipmentRow(_ item: CustomEquipment) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Toggle(item.name, isOn: Binding(
                get: { item.enabled },
                set: { value in model.updateCustomEquipment(id: item.id) { $0.enabled = value } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
            .tint(DL.calm)
            TextField("Name", text: Binding(
                get: { item.name },
                set: { value in model.updateCustomEquipment(id: item.id) { $0.name = value } }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 12.5, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
            .frame(width: 200)
            numberField(Binding(
                get: { item.minutes },
                set: { value in model.updateCustomEquipment(id: item.id) { $0.minutes = value } }
            ), width: 46)
            Text("min").font(.system(size: 11)).foregroundStyle(DL.muted)
            Toggle("Counts as standing", isOn: Binding(
                get: { item.countsAsStanding },
                set: { value in model.updateCustomEquipment(id: item.id) { $0.countsAsStanding = value } }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11.5))
            Spacer()
            if !item.enabled {
                Chip(text: "Off", style: .plain)
            }
            removeButton("Remove \(item.name)") {
                model.removeCustomEquipment(id: item.id)
            }
        }
        .padding(.vertical, 5)
    }

    // MARK: - Calendar

    private var calendarTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            DlCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Eyebrow(text: "Access")
                        Spacer()
                        Chip(text: model.calendarService.authorized ? "Read-only access" : (model.calendarService.accessDenied ? "Denied" : "Not requested"),
                             style: model.calendarService.authorized ? .calm : (model.calendarService.accessDenied ? .crit : .warn))
                    }
                    Text("Dayline reads event times, titles and attendee counts to find gaps. It never creates, edits or deletes an event.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Request access") { model.requestCalendarAccess() }
                            .buttonStyle(PrimaryButtonStyle())
                        Button("Refresh now") { model.refreshCalendar(force: true) }
                            .buttonStyle(SecondaryButtonStyle())
                        if let error = model.calendarService.lastError {
                            Text(error).font(.system(size: 10.5)).foregroundStyle(DL.crit)
                        }
                        Spacer()
                        Text(model.lastSyncedText)
                            .font(.system(size: 10.5)).foregroundStyle(DL.muted)
                    }
                }
            }

            if !model.calendarService.calendars.isEmpty {
                DlCard {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Eyebrow(text: "Calendars")
                            Spacer()
                            Text("None selected means all")
                                .font(.system(size: 10)).foregroundStyle(DL.muted)
                        }
                        ForEach(model.calendarService.calendars, id: \.id) { calendar in
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(Color(nsColor: calendar.color))
                                    .frame(width: 8, height: 8)
                                Text(calendar.title).font(.system(size: 12))
                                Text(calendar.source)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(DL.muted)
                                Spacer()
                                Toggle("", isOn: Binding(
                                    get: {
                                        model.settings.selectedCalendarIDs.isEmpty
                                            || model.settings.selectedCalendarIDs.contains(calendar.id)
                                    },
                                    set: { on in
                                        model.updateSettings { settings in
                                            if settings.selectedCalendarIDs.isEmpty {
                                                settings.selectedCalendarIDs = model.calendarService.calendars.map(\.id)
                                                    .filter { $0 != calendar.id }
                                            } else if on {
                                                if !settings.selectedCalendarIDs.contains(calendar.id) {
                                                    settings.selectedCalendarIDs.append(calendar.id)
                                                }
                                            } else {
                                                settings.selectedCalendarIDs.removeAll { $0 == calendar.id }
                                                if settings.selectedCalendarIDs.isEmpty {
                                                    settings.selectedCalendarIDs = [""]
                                                }
                                            }
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                .tint(DL.calm)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Meeting rules").padding(.bottom, 4)
                    SettingRow("Long meeting", subtitle: "A meeting at least this long asks for a break in the next gap.") {
                        HStack(spacing: 6) {
                            numberField(bind(\.longMeetingMinutes))
                            Text("min").font(.system(size: 11)).foregroundStyle(DL.muted)
                        }
                    }
                    SettingRow("Back-to-back run", subtitle: "A run of meetings at least this long is treated as one block.") {
                        HStack(spacing: 6) {
                            numberField(bind(\.backToBackMinutes))
                            Text("min").font(.system(size: 11)).foregroundStyle(DL.muted)
                        }
                    }
                    ToggleRow(title: "Ignore all-day events",
                              subtitle: "All-day entries do not make the day busy.",
                              isOn: bind(\.ignoreAllDay))
                }
            }

            standingRulesCard
        }
    }

    private var standingRulesCard: some View {
        DlCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow(text: "Standing-call rules")
                    Spacer()
                    Text("Include and exclude match on title, length, attendees or recurrence.")
                        .font(.system(size: 10)).foregroundStyle(DL.muted)
                }
                ForEach(Array(model.settings.standingRules.enumerated()), id: \.element.id) { index, rule in
                    HStack(spacing: 7) {
                        Toggle("", isOn: Binding(
                            get: { rule.enabled },
                            set: { value in model.updateSettings { if $0.standingRules.indices.contains(index) { $0.standingRules[index].enabled = value } } }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.mini)
                        .tint(DL.calm)
                        Toggle("Exclude", isOn: Binding(
                            get: { rule.isExclude },
                            set: { value in model.updateSettings { if $0.standingRules.indices.contains(index) { $0.standingRules[index].isExclude = value } } }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.system(size: 10.5))
                        .tint(DL.calm)
                        Text(rule.kind.title)
                            .font(.system(size: 11.5))
                            .frame(width: 100, alignment: .leading)
                        if rule.kind == .titleContains {
                            TextField("Title contains", text: Binding(
                                get: { rule.textValue },
                                set: { value in model.updateSettings { if $0.standingRules.indices.contains(index) { $0.standingRules[index].textValue = value } } }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                            .frame(width: 150)
                        } else if rule.kind == .recurring {
                            Text(rule.numberValue == 0 ? "Any recurrence" : "At least \(rule.numberValue)×")
                                .font(.system(size: 10.5)).foregroundStyle(DL.muted)
                        } else {
                            numberField(Binding(
                                get: { rule.numberValue },
                                set: { value in model.updateSettings { if $0.standingRules.indices.contains(index) { $0.standingRules[index].numberValue = value } } }
                            ), width: 44)
                            Text(rule.kind == .minimumLength ? "min" : "people")
                                .font(.system(size: 10.5)).foregroundStyle(DL.muted)
                        }
                        Spacer()
                        Text(rule.summary)
                            .font(.system(size: 9.5))
                            .foregroundStyle(DL.muted)
                            .lineLimit(1)
                        Button {
                            model.updateSettings { if $0.standingRules.indices.contains(index) { $0.standingRules.remove(at: index) } }
                        } label: {
                            Image(systemName: "trash").font(.system(size: 9.5))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DL.muted)
                    }
                    .padding(.vertical, 3)
                }
                HStack {
                    Menu("Add rule") {
                        ForEach(StandingRuleKind.allCases) { kind in
                            Button(kind.title) {
                                model.updateSettings { $0.standingRules.append(StandingRule(kind: kind)) }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 90)
                    Spacer()
                    Text("\(model.settings.standingRules.filter(\.enabled).count) active")
                        .font(.system(size: 10.5)).foregroundStyle(DL.muted)
                }
            }
        }
    }

    // MARK: - Garmin

    private var garminTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            DlCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Eyebrow(text: "Connection")
                        Spacer()
                        Chip(text: model.settings.garmin.connected ? model.relativeSyncText() : "Not connected",
                             style: model.settings.garmin.connected ? .accent : .plain)
                    }
                    if model.settings.garmin.connected {
                        Text(model.settings.garmin.email.isEmpty ? "Signed in." : "Signed in as \(model.settings.garmin.email).")
                            .font(.system(size: 12))
                        HStack {
                            Button(model.garminBusy ? "Syncing…" : "Sync now") {
                                model.syncGarminIfPossible(force: true)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(model.garminBusy)
                            Button("Sign out") { model.disconnectGarmin() }
                                .buttonStyle(SecondaryButtonStyle())
                            Spacer()
                            if let last = model.settings.garmin.lastLoginAt {
                                Text("Since \(Fmt.dayMonthYear.string(from: last))")
                                    .font(.system(size: 10.5)).foregroundStyle(DL.muted)
                            }
                        }
                    } else {
                        Text("The password goes straight to Garmin through the bundled helper. Only the session token is kept, in the Keychain.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(DL.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            TextField("Garmin email", text: $ui.garminEmail)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                                .frame(width: 210)
                            SecureField("Password", text: $ui.garminPassword)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                                .frame(width: 170)
                            Button(model.garminBusy ? "Signing in…" : "Connect") {
                                model.connectGarmin(email: ui.garminEmail, password: ui.garminPassword)
                                // The password is handed to the helper once and not kept.
                                ui.garminPassword = ""
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(model.garminBusy || model.garminMFA != nil
                                      || ui.garminEmail.isEmpty || ui.garminPassword.isEmpty)
                        }
                        if model.garminMFA != nil {
                            HStack(spacing: 8) {
                                Text("Two-factor code").font(.system(size: 12))
                                TextField("123456", text: $ui.garminMFA)
                                    .textFieldStyle(.plain)
                                    .frame(width: 90)
                                    .padding(.horizontal, 8).padding(.vertical, 5)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                                Button("Submit") {
                                    model.submitGarminMFA(code: ui.garminMFA, email: ui.garminEmail)
                                    ui.garminMFA = ""
                                }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(model.garminBusy || ui.garminMFA.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        if let error = model.garminError ?? model.settings.garmin.lastError {
                            Text(error).font(.system(size: 11)).foregroundStyle(DL.crit)
                        }
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Sync and thresholds").padding(.bottom, 4)
                    SettingRow("Sync every", subtitle: "Stress and Body Battery refresh in the background.") {
                        HStack(spacing: 6) {
                            numberField(bind(\.garmin.syncMinutes))
                            Text("min").font(.system(size: 11)).foregroundStyle(DL.muted)
                        }
                    }
                    SettingRow("High stress", subtitle: "At or above this, breathing is offered before movement.") {
                        numberField(bind(\.garmin.stressHigh))
                    }
                    SettingRow("Low Body Battery", subtitle: "At or below this, lighter breaks are preferred.") {
                        numberField(bind(\.garmin.batteryLow))
                    }
                    ToggleRow(title: "Use sleep and HRV",
                              subtitle: "A short night lightens the day's first break.",
                              isOn: bind(\.garmin.useSleepAndHRV))
                }
            }

            NoticeCard(title: "Read-only, and optional",
                       message: "Without Garmin the engine still times breaks from the calendar and Mac activity. Garmin only adds stress, Body Battery and sleep context.")
        }
    }

    // MARK: - Journal

    private var journalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Check-ins").padding(.bottom, 4)
                    ToggleRow(title: "Morning", subtitle: "One tap on the 4×4 grid when the day starts.", isOn: bind(\.checkInMorning))
                    ToggleRow(title: "After lunch", subtitle: "A ten-second read on the afternoon.", isOn: bind(\.checkInAfterLunch))
                    ToggleRow(title: "End of day", subtitle: "Part of the reflection.", isOn: bind(\.checkInEndOfDay))
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Eyebrow(text: "Reflection prompts")
                        Spacer()
                        Text("One answer is enough to save.")
                            .font(.system(size: 10)).foregroundStyle(DL.muted)
                    }
                    ForEach(Array(model.settings.prompts.enumerated()), id: \.offset) { index, prompt in
                        HStack(spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(DL.muted)
                                .frame(width: 16, height: 16)
                                .background(Circle().stroke(DL.line, lineWidth: 1))
                            TextField("Prompt", text: Binding(
                                get: { prompt },
                                set: { value in model.updateSettings { if $0.prompts.indices.contains(index) { $0.prompts[index] = value } } }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                            Button {
                                model.updateSettings { if $0.prompts.indices.contains(index) { $0.prompts.remove(at: index) } }
                            } label: {
                                Image(systemName: "trash").font(.system(size: 9.5))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DL.muted)
                        }
                    }
                    HStack(spacing: 6) {
                        TextField("New prompt", text: $ui.newPrompt)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                            .frame(width: 260)
                        Button("Add") {
                            let trimmed = ui.newPrompt.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            model.updateSettings { $0.prompts.append(trimmed) }
                            ui.newPrompt = ""
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                        Button("Restore defaults") {
                            model.updateSettings { $0.prompts = AppSettings.defaultPrompts }
                        }
                        .buttonStyle(LinkButtonStyle())
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Capture").padding(.bottom, 4)
                    SettingRow("Global hotkey", subtitle: "Opens a new journal entry from any app.") {
                        Chip(text: model.settings.hotkey.display, style: .plain)
                    }
                    SettingRow("Export", subtitle: "One Markdown file per day plus a JSON dump.") {
                        Button("Export…") { model.exportJournal() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    ToggleRow(title: "Sounds", subtitle: "A quiet cue when a break starts and ends.", isOn: bind(\.sounds))
                }
            }
        }
    }

    // MARK: - AI

    private var aiTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Provider").padding(.bottom, 4)
                    SettingRow("Provider", subtitle: "Bring your own key. Nothing routes through a Dayline server.") {
                        SegmentedPicker(options: AIProvider.allCases.map { ($0, $0.shortTitle) },
                                        selection: Binding(
                                            get: { model.settings.ai.provider },
                                            set: { value in
                                                model.updateSettings { settings in
                                                    settings.ai.provider = value
                                                    settings.ai.model = value.defaultModel
                                                }
                                                ui.apiKeyDraft = ""
                                                ui.showKey = false
                                                ui.hasStoredKey = model.hasStoredAPIKey()
                                                ui.aiTestResult = nil
                                            }
                                        ))
                            .frame(width: 300)
                    }
                    SettingRow("Model", subtitle: "Any model ID the provider accepts.") {
                        TextField("Model", text: bind(\.ai.model))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                            .frame(width: 210)
                    }
                    if model.settings.ai.provider == .custom {
                        SettingRow("Base URL", subtitle: "OpenAI-compatible endpoint, for example http://localhost:11434/v1") {
                            TextField("https://…/v1", text: bind(\.ai.baseURL))
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5, design: .monospaced))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                                .frame(width: 240)
                        }
                    }
                    SettingRow("API key", subtitle: "Stored in the macOS Keychain, never in the state file.") {
                        HStack(spacing: 8) {
                            Group {
                                // The stored key is never read back into the field.
                                if ui.showKey {
                                    TextField(ui.hasStoredKey ? "Saved in Keychain" : "sk-…", text: $ui.apiKeyDraft)
                                } else {
                                    SecureField(ui.hasStoredKey ? "Saved in Keychain" : "sk-…", text: $ui.apiKeyDraft)
                                }
                            }
                            .textFieldStyle(.plain)
                            .font(.system(size: 11.5, design: .monospaced))
                            .frame(width: 170)
                            Button(ui.showKey ? "Hide" : "Show") { ui.showKey.toggle() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5))
                                .foregroundStyle(DL.muted)
                            Button("Save") {
                                let saved = model.saveAPIKey(ui.apiKeyDraft)
                                ui.aiTestResult = saved ? "Key saved." : "The Keychain did not accept the key."
                                ui.aiTestFailed = !saved
                                if saved {
                                    ui.apiKeyDraft = ""
                                    ui.showKey = false
                                }
                                ui.hasStoredKey = model.hasStoredAPIKey()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(DL.accent)
                            .fixedSize()
                            .disabled(ui.apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if ui.hasStoredKey {
                                Button("Remove") {
                                    model.removeAPIKey()
                                    ui.hasStoredKey = model.hasStoredAPIKey()
                                    ui.aiTestResult = "Key removed."
                                    ui.aiTestFailed = false
                                }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5))
                                .foregroundStyle(DL.muted)
                                .fixedSize()
                            }
                        }
                    }
                    HStack(spacing: 8) {
                        Button(model.aiBusy ? "Testing…" : "Test connection") {
                            model.testAIConnection(draftKey: ui.apiKeyDraft) { message in
                                ui.aiTestResult = message ?? model.aiError ?? "Failed."
                                ui.aiTestFailed = message == nil
                            }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(model.aiBusy)
                        if let result = ui.aiTestResult {
                            Text(result)
                                .font(.system(size: 10.5))
                                .foregroundStyle(ui.aiTestFailed ? DL.crit : DL.accent)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "What leaves this Mac").padding(.bottom, 4)
                    ToggleRow(title: "Journal text",
                              subtitle: "Include the words you wrote in prompts and entries.",
                              isOn: bind(\.ai.shareJournalText))
                    ToggleRow(title: "Calendar titles",
                              subtitle: "Off by default. Durations and counts are always shared.",
                              isOn: bind(\.ai.shareCalendarTitles))
                    ToggleRow(title: "Weekly insight",
                              subtitle: "One automatic summary at the end of the week.",
                              isOn: bind(\.ai.weeklyInsights))
                }
            }

            NoticeCard(title: "Never sent",
                       message: "Calendar contents, event attendees, Garmin raw samples and your journal stay local unless one of the toggles above says otherwise. Daily aggregates are all an insight needs.",
                       tint: DL.calm, background: DL.calmSoft)
        }
    }

    // MARK: - General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Startup").padding(.bottom, 4)
                    ToggleRow(title: "Launch at login",
                              subtitle: "Dayline opens its window and stays in the menu bar.",
                              isOn: Binding(
                                get: { model.settings.launchAtLogin },
                                set: { model.setLaunchAtLogin($0) }
                              ))
                    SettingRow("Menu bar", subtitle: "The icon shows a countdown in the last hour and a small dot when a break is due or running.") {
                        Text("Always running")
                            .font(.system(size: 11)).foregroundStyle(DL.muted)
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 0) {
                    Eyebrow(text: "Appearance").padding(.bottom, 4)
                    SettingRow("Theme", subtitle: "Dayline is light mode only.") {
                        Text("Light")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(DL.muted)
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Data")
                    Text("State lives in \((model.store.directory.path as NSString).abbreviatingWithTildeInPath). Exports are plain Markdown and JSON.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.muted)
                    HStack(spacing: 8) {
                        Button("Export journal…") { model.exportJournal() }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Reveal data folder") {
                            NSWorkspace.shared.activateFileViewerSelecting([model.store.directory])
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        Spacer()
                    }
                    Divider().overlay(DL.line)
                    HStack(spacing: 8) {
                        Button("Load sample year") { model.seedDemoData() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(model.state.settings.showDemoData)
                        Button("Clear sample data") { model.clearSampleData() }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(!model.state.settings.showDemoData)
                        Spacer()
                        Text("\(model.state.days.count) days · \(model.state.journal.count) entries · \(model.state.checkIns.count) check-ins")
                            .font(.system(size: 10.5))
                            .foregroundStyle(DL.muted)
                    }
                }
            }

            DlCard {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "About")
                    Text("Dayline")
                        .font(.system(size: 16, weight: .semibold))
                    Text("A workday coach that gets you out of the chair.\nLocal-first. No account. Calendar and Garmin stay read-only.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(DL.muted)
                    HStack(spacing: 8) {
                        Chip(text: "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")", style: .plain)
                        Chip(text: "macOS 14+", style: .plain)
                        Chip(text: "Dock and menu bar", style: .plain)
                    }
                }
            }
        }
    }
}


// MARK: - Inline time field

@MainActor
final class TimeFieldUI: ObservableObject {
    @Published var text = ""
}

/// A compact 24-hour field that commits as soon as the text is a valid time,
/// and never rewrites the user's keystrokes mid-edit.
struct TimeField: View {
    var value: String
    var onCommit: (TimeOfDay) -> Void

    @StateObject private var ui = TimeFieldUI()

    var body: some View {
        TextField("09:00", text: $ui.text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.system(size: 12.5, design: .monospaced))
            .frame(width: 56)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
            .onAppear { ui.text = value }
            .onChange(of: value) { _, next in
                if next != ui.text { ui.text = next }
            }
            .onChange(of: ui.text) { _, next in
                // Commit only a complete HH:MM while typing; "10:3" is still
                // being typed, not 10:03. Shorter forms commit on Return.
                guard next.count == 5, let parsed = TimeOfDay(next) else { return }
                onCommit(parsed)
            }
            .onSubmit {
                if let parsed = TimeOfDay(ui.text) {
                    onCommit(parsed)
                    ui.text = parsed.display
                } else {
                    ui.text = value
                }
            }
    }
}
