import AppKit
import DaylineCore
import SwiftUI

@MainActor
final class CheckInUI: ObservableObject {
    @Published var selection: MoodSelection?
    @Published var note = ""
    @Published var saved = false
}

struct CheckInView: View {
    @EnvironmentObject private var model: AppModel
    let source: CheckInSource

    @StateObject private var ui = CheckInUI()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Kicker(text: titleEyebrow)
                    Text(title)
                        .font(.system(size: 26, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(DL.ink)
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundStyle(DL.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    close()
                } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(DL.muted)
            }

            if let last = model.latestCheckIn(), !ui.saved {
                HStack(spacing: 6) {
                    QuadrantDot(quadrant: last.quadrant)
                    Text("Last check-in \(Fmt.time.string(from: last.at)): \(last.word.lowercased()).")
                        .font(.system(size: 11))
                        .foregroundStyle(DL.muted)
                }
            }

            if ui.saved {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(DL.calm)
                    Text("Check-in saved")
                        .font(.system(size: 18, weight: .semibold))
                    Text("It sits next to today's calendar, breaks and Garmin data.")
                        .font(.system(size: 12))
                        .foregroundStyle(DL.muted)
                    Button("Close") { close() }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
            } else {
                DlCard {
                    MoodGridView(selection: $ui.selection)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("One line, optional")
                        .font(.system(size: 11.5, weight: .semibold))
                    TextField("What is on your mind?", text: $ui.note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(2...4)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DL.field))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(DL.line, lineWidth: 1))
                }

            }
            Spacer(minLength: 0)
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if !ui.saved {
                footer
            }
        }
        .frame(minWidth: 500, minHeight: 600)
        .background(DL.window)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if ui.selection?.word.isEmpty == false {
                Text("\(ui.selection!.quadrant.name) · \(ui.selection!.word)")
                    .font(.system(size: 13))
                    .foregroundStyle(DL.ink)
            } else {
                HStack(spacing: 6) {
                    Circle().fill(DL.warnFill).frame(width: 7, height: 7)
                    Text("Pick a square and a word to save.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DL.warn)
                }
            }
            Spacer()
            Button("Skip") { close() }
                .buttonStyle(SecondaryButtonStyle())
            Button("Save") {
                guard let selection = ui.selection, !selection.word.isEmpty else { return }
                model.saveCheckIn(selection, note: ui.note, source: source)
                ui.saved = true
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(ui.selection?.word.isEmpty != false)
        }
        .padding(.horizontal, 22)
        .frame(height: 64)
        .background(DL.titlebar)
        .overlay(alignment: .top) {
            Rectangle().fill(DL.line).frame(height: 1)
        }
    }

    private var titleEyebrow: String {
        switch source {
        case .morning: return "Morning check-in"
        case .afterLunch: return "After lunch"
        case .reflection: return "End of day"
        case .manual: return "Quick check-in"
        }
    }

    private var title: String {
        switch source {
        case .morning: return "How did you wake up?"
        case .afterLunch: return "How is the afternoon going?"
        case .reflection: return "How did the day feel?"
        case .manual: return "How are you, right now?"
        }
    }

    private var subtitle: String {
        switch source {
        case .morning: return "No middle, no default. Energy and pleasantness, one tap each."
        case .afterLunch: return "A ten-second read on the afternoon, before it runs away."
        case .reflection: return "This is the mood the day's summary will use."
        case .manual: return "Ten seconds. It lands next to today's calendar and Garmin data."
        }
    }

    private func close() {
        NSApp.windows.first { $0.identifier?.rawValue == "dayline.checkIn" }?.close()
    }
}
