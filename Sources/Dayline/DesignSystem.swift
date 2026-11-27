import AppKit
import DaylineCore
import SwiftUI

// MARK: - Palette

/// Design-system aliases. Every value comes from Theme.swift; views never
/// spell a hex. `warn` is the text-safe amber, `warnFill` the dot/fill amber.
enum DL {
    static let ink = Color.textPrimary
    static let muted = Color.textSecondary
    static let faint = Color.textMuted
    static let line = Color.borderHairline
    static let lineStrong = Color.borderStrong
    static let panel = Color.bgCard
    static let window = Color.bgCanvas
    static let sidebar = Color.bgSidebar
    static let titlebar = Color.bgTitlebar
    static let field = Color.bgInput

    static let accent = Color.accentPrimary
    static let accentHover = Color.accentPrimaryHover
    static let accentInk = Color.textOnAccent
    static let accentSoft = Color.accentPrimaryTint
    static let accentBorder = Color.accentPrimaryBorder

    static let calm = Color.semanticCalm
    static let calmText = Color.semanticCalmText
    static let calmSoft = Color.semanticCalmTint
    static let calmBorder = Color.semanticCalmBorder

    static let warn = Color.semanticWarmText
    static let warnFill = Color.semanticWarm
    static let warnSoft = Color.semanticWarmTint
    static let warnBorder = Color.semanticWarmBorder

    static let crit = Color.semanticAlert
    static let critSoft = Color.semanticAlertTint
    static let critBorder = Color.semanticAlertBorder

    static let cool = Color.semanticCool
    static let coolSoft = Color.semanticCoolTint

    static func quadrant(_ q: MoodQuadrant) -> Color {
        switch q {
        case .tenseWired: return Color.semanticAlert
        case .energizedFocused: return Color.accentPrimary
        case .drainedFlat: return Color.semanticCool
        case .calmContent: return Color.semanticCalm
        }
    }

    static func quadrantSoft(_ q: MoodQuadrant) -> Color {
        switch q {
        case .tenseWired: return Color.semanticAlertTint
        case .energizedFocused: return Color.accentPrimaryTint
        case .drainedFlat: return Color.semanticCoolTint
        case .calmContent: return Color.semanticCalmTint
        }
    }
}

// MARK: - Building blocks

/// Card header: "AT YOUR DESK".
struct Eyebrow: View {
    var text: String
    var color: Color = .textSecondary

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(color)
    }
}

/// Page kicker: "EQUIPMENT". One per screen, in Sun Orange.
struct Kicker: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Color.accentPrimary)
    }
}

enum ChipStyle {
    case accent, warn, calm, plain, crit

    var background: Color {
        switch self {
        case .accent: return Color.accentPrimaryTint
        case .warn: return Color.semanticWarmTint
        case .calm: return Color.semanticCalmTint
        case .plain: return Color.bgCard
        case .crit: return Color.semanticAlertTint
        }
    }

    var foreground: Color {
        switch self {
        case .accent: return Color.accentPrimary
        case .warn: return Color.semanticWarmText
        case .calm: return Color.semanticCalmText
        case .plain: return Color.textSecondary
        case .crit: return Color.semanticAlert
        }
    }

    var border: Color {
        switch self {
        case .accent: return Color.accentPrimaryBorder
        case .warn: return Color.semanticWarmBorder
        case .calm: return Color.semanticCalmBorder
        case .plain: return Color.borderHairline
        case .crit: return Color.semanticAlertBorder
        }
    }
}

struct Chip: View {
    var text: String
    var style: ChipStyle = .accent
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold))
            }
            Text(text)
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(style.foreground)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(Capsule().fill(style.background))
        .overlay(Capsule().strokeBorder(style.border, lineWidth: 1))
        .fixedSize()
    }
}

struct DlCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .daylineCard()
    }
}

struct StatCard: View {
    var value: String
    var label: String
    var tint: Color = Color.textPrimary
    var mono: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .daylineCard()
    }
}

struct LinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? Color.accentPrimaryHover : Color.textPrimary)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
    }
}

struct Ring: View {
    var progress: Double
    var value: String
    var label: String
    var tint: Color = Color.accentPrimary
    var size: CGFloat = 46

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.borderHairline, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, progress)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(value)
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
            }
            .frame(width: size, height: size)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct Meter: View {
    var progress: Double
    var tint: Color = Color.accentPrimary
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.borderHairline)
                Capsule().fill(tint)
                    .frame(width: max(0, min(1, progress)) * proxy.size.width)
            }
        }
        .frame(height: height)
    }
}

struct ToggleRow: View {
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(Color.semanticCalm)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.borderHairline).frame(height: 1) }
    }
}

struct SettingRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let subtitle {
                    Text(subtitle).font(.system(size: 12.5)).foregroundStyle(Color.textSecondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.borderHairline).frame(height: 1) }
    }
}

struct SegmentedPicker<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option in
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 12.5, weight: selection == option.0 ? .semibold : .regular))
                        .foregroundStyle(selection == option.0 ? Color.textOnAccent : Color.textPrimary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(selection == option.0 ? Color.semanticCalm : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Color.bgCard))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            .strokeBorder(Color.borderHairline, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct NoticeCard: View {
    var title: String
    var message: String
    var tint: Color = Color.semanticWarmText
    var background: Color = Color.semanticWarmTint
    var action: (String, () -> Void)?
    var secondary: (String, () -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.textPrimary)
            }
            Text(message)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.textCallout)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                HStack(spacing: 8) {
                    Button(action.0, action: action.1).buttonStyle(PrimaryButtonStyle())
                    if let secondary {
                        Button(secondary.0, action: secondary.1).buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.top, 3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(background))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
            .strokeBorder(tint.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Mood grid

struct MoodSelection: Equatable {
    var energy: Int
    var mood: Int
    var word: String
    var quadrant: MoodQuadrant { .quadrant(energy: energy, mood: mood) }
}

@MainActor
final class MoodGridUI: ObservableObject {
    @Published var hover: MoodPoint?
    @Published var keyboardFocus: MoodPoint?
    @Published var keyboardActive = false
}

struct MoodPoint: Equatable {
    var energy: Int
    var mood: Int
}

struct MoodGridView: View {
    @Binding var selection: MoodSelection?
    var disabled = false

    @StateObject private var ui = MoodGridUI()

    private let side = MoodGrid.tileSize * 4 + MoodGrid.tileGap * 2 + MoodGrid.quadrantGap

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .trailing) {
                    Text("High").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.textPrimary)
                    Spacer()
                    Text("Low").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.textPrimary)
                }
                .frame(height: side)

                VStack(spacing: MoodGrid.quadrantGap) {
                    quadrantRow(energies: [4, 3])
                    quadrantRow(energies: [2, 1])
                }
            }

            HStack {
                Text("Unpleasant").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.textPrimary)
                Spacer()
                Text("Pleasant").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.textPrimary)
            }
            .frame(width: side)
            .padding(.leading, 36)

            if let selection {
                wordPicker(selection)
                    .padding(.top, 2)
                    .transition(.opacity)
            }
        }
        .opacity(disabled ? 0.6 : 1)
        .allowsHitTesting(!disabled)
        .focusable(!disabled, onFocusChange: { focused in
            if !focused { ui.keyboardActive = false }
        })
        .onMoveCommand { direction in
            moveFocus(direction)
        }
        .onKeyPress(.space) {
            selectFocused()
            return .handled
        }
        .onKeyPress(.return) {
            selectFocused()
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mood and energy grid")
    }

    private func quadrantRow(energies: [Int]) -> some View {
        HStack(spacing: MoodGrid.quadrantGap) {
            quadrant(energies: energies, moods: [1, 2])
            quadrant(energies: energies, moods: [3, 4])
        }
    }

    private func quadrant(energies: [Int], moods: [Int]) -> some View {
        VStack(spacing: MoodGrid.tileGap) {
            ForEach(energies, id: \.self) { energy in
                HStack(spacing: MoodGrid.tileGap) {
                    ForEach(moods, id: \.self) { mood in
                        tile(energy: energy, mood: mood)
                    }
                }
            }
        }
    }

    private func tile(energy: Int, mood: Int) -> some View {
        let point = MoodPoint(energy: energy, mood: mood)
        let selected = selection?.energy == energy && selection?.mood == mood
        let hovered = ui.hover == point
        let focused = ui.keyboardActive && ui.keyboardFocus == point
        return Button {
            select(point)
        } label: {
            RoundedRectangle(cornerRadius: MoodGrid.tileRadius, style: .continuous)
                .fill(MoodGrid.color(energy: energy, mood: mood))
                .frame(width: MoodGrid.tileSize, height: MoodGrid.tileSize)
                .overlay(
                    RoundedRectangle(cornerRadius: MoodGrid.tileRadius, style: .continuous)
                        .strokeBorder(Color.textPrimary.opacity(hovered ? 0.20 : 0.08), lineWidth: 1)
                )
                .overlay {
                    if selected || focused {
                        RoundedRectangle(cornerRadius: MoodGrid.tileRadius + 2, style: .continuous)
                            .strokeBorder(Color.bgCard, lineWidth: 2)
                            .padding(-2)
                    }
                }
                .overlay {
                    if selected || focused {
                        RoundedRectangle(cornerRadius: MoodGrid.tileRadius + 4, style: .continuous)
                            .strokeBorder(Color.textPrimary.opacity(selected ? 1 : 0.5), lineWidth: 2)
                            .padding(-4)
                    }
                }
                .scaleEffect(selected ? 1.06 : (hovered ? 1.04 : 1))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.12), value: selected)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .onHover { inside in
            ui.hover = inside ? point : nil
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .help("Energy \(energy) of 4, pleasantness \(mood) of 4, \(MoodQuadrant.quadrant(energy: energy, mood: mood).name)")
    }

    private func select(_ point: MoodPoint) {
        guard !disabled else { return }
        let word = selection?.energy == point.energy && selection?.mood == point.mood ? (selection?.word ?? "") : ""
        selection = MoodSelection(energy: point.energy, mood: point.mood, word: word)
        ui.keyboardFocus = point
    }

    private func selectFocused() {
        guard let point = ui.keyboardFocus else { return }
        select(point)
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        let current = ui.keyboardFocus ?? MoodPoint(energy: 4, mood: 1)
        var energy = current.energy
        var mood = current.mood
        switch direction {
        case .up: energy = min(4, energy + 1)
        case .down: energy = max(1, energy - 1)
        case .left: mood = max(1, mood - 1)
        case .right: mood = min(4, mood + 1)
        default: return
        }
        ui.keyboardFocus = MoodPoint(energy: energy, mood: mood)
        ui.keyboardActive = true
    }

    private func wordPicker(_ selection: MoodSelection) -> some View {
        let q = selection.quadrant
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(DL.quadrant(q)).frame(width: 8, height: 8)
                Text(q.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                Text("energy \(selection.energy) of 4 · pleasantness \(selection.mood) of 4")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.textSecondary)
            }
            Text("Which word fits best?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimary)
            let columns = [GridItem(.adaptive(minimum: 76), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(q.words, id: \.self) { word in
                    Button {
                        self.selection = MoodSelection(energy: selection.energy, mood: selection.mood, word: word)
                    } label: {
                        Text(word)
                            .font(.system(size: 12, weight: selection.word == word ? .semibold : .regular))
                            .foregroundStyle(selection.word == word ? Color.textOnAccent : Color.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(selection.word == word ? Color.semanticCalm : Color.bgCard))
                            .overlay(Capsule().strokeBorder(selection.word == word ? Color.clear : Color.borderHairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct QuadrantDot: View {
    var quadrant: MoodQuadrant

    var body: some View {
        Circle().fill(DL.quadrant(quadrant)).frame(width: 8, height: 8)
    }
}

// MARK: - Layout helpers

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 600
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct PageHeader: View {
    var eyebrow: String
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Kicker(text: eyebrow)
            Text(title)
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Color.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EmptyStateView: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26)).foregroundStyle(Color.textSecondary.opacity(0.7))
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(message).font(.system(size: 12)).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
