import SwiftUI

/// Reusable pill-style time/date stepper with previous/next affordances and an
/// optional selected center action.
struct PillTimeStepperBar<Label: View>: View {
    let canStepBackward: Bool
    let canStepForward: Bool
    let isCenterSelected: Bool
    var style: PillTimeStepperBarStyle
    var previousHelp: String
    var nextHelp: String
    var centerHelp: String?
    var centerAccessibilityLabel: String?
    var accessibilityLabel: String?
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onCenter: (() -> Void)?
    var label: (Bool) -> Label

    init(
        canStepBackward: Bool = true,
        canStepForward: Bool = true,
        isCenterSelected: Bool = false,
        style: PillTimeStepperBarStyle = .standard,
        previousHelp: String,
        nextHelp: String,
        centerHelp: String? = nil,
        centerAccessibilityLabel: String? = nil,
        accessibilityLabel: String? = nil,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onCenter: (() -> Void)? = nil,
        @ViewBuilder label: @escaping (Bool) -> Label
    ) {
        self.canStepBackward = canStepBackward
        self.canStepForward = canStepForward
        self.isCenterSelected = isCenterSelected
        self.style = style
        self.previousHelp = previousHelp
        self.nextHelp = nextHelp
        self.centerHelp = centerHelp
        self.centerAccessibilityLabel = centerAccessibilityLabel
        self.accessibilityLabel = accessibilityLabel
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onCenter = onCenter
        self.label = label
    }

    var body: some View {
        HStack(spacing: style.itemSpacing) {
            stepButton(systemName: "chevron.left",
                       disabled: !canStepBackward,
                       help: previousHelp,
                       action: onPrevious)

            centerItem

            stepButton(systemName: "chevron.right",
                       disabled: !canStepForward,
                       help: nextHelp,
                       action: onNext)
        }
        .padding(style.outerPadding)
        .background(
            RoundedRectangle(cornerRadius: style.outerCornerRadius, style: .continuous)
                .fill(style.background)
        )
        .accessibilityElement(children: .contain)
        .pillTimeStepperAccessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var centerItem: some View {
        if let onCenter {
            Button(action: onCenter) {
                centerLabel
            }
            .buttonStyle(.plain)
            .pillTimeStepperHelp(centerHelp)
            .pillTimeStepperAccessibilityLabel(centerAccessibilityLabel)
            .accessibilityAddTraits(isCenterSelected ? .isSelected : [])
        } else {
            centerLabel
                .pillTimeStepperHelp(centerHelp)
                .pillTimeStepperAccessibilityLabel(centerAccessibilityLabel)
                .accessibilityAddTraits(isCenterSelected ? .isSelected : [])
        }
    }

    private var centerLabel: some View {
        label(isCenterSelected)
            .font(style.labelFont)
            .foregroundStyle(isCenterSelected ? style.selectedForeground : style.unselectedForeground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, style.centerHorizontalPadding)
            .frame(minWidth: style.centerMinWidth)
            .frame(height: style.centerHeight)
            .background {
                if isCenterSelected {
                    RoundedRectangle(cornerRadius: style.selectedCornerRadius, style: .continuous)
                        .fill(style.selectedBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: style.selectedCornerRadius, style: .continuous)
                                .strokeBorder(style.selectedBorder, lineWidth: style.selectedBorderWidth)
                        )
                }
            }
            .contentShape(Rectangle())
    }

    private func stepButton(
        systemName: String,
        disabled: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(style.arrowFont)
                .foregroundStyle(disabled ? style.disabledForeground : style.arrowForeground)
                .frame(width: style.arrowWidth, height: style.arrowHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct PillTimeStepperBarStyle {
    var itemSpacing: CGFloat
    var outerPadding: CGFloat
    var outerCornerRadius: CGFloat
    var selectedCornerRadius: CGFloat
    var arrowWidth: CGFloat
    var arrowHeight: CGFloat
    var centerMinWidth: CGFloat
    var centerHorizontalPadding: CGFloat
    var centerHeight: CGFloat
    var arrowFont: Font
    var labelFont: Font
    var background: Color
    var selectedBackground: Color
    var selectedBorder: Color
    var selectedBorderWidth: CGFloat
    var arrowForeground: Color
    var disabledForeground: Color
    var selectedForeground: Color
    var unselectedForeground: Color

    var totalHeight: CGFloat {
        max(arrowHeight, centerHeight) + outerPadding * 2
    }
}

extension PillTimeStepperBarStyle {
    static let standard = PillTimeStepperBarStyle(
        itemSpacing: 2,
        outerPadding: 3,
        outerCornerRadius: 8,
        selectedCornerRadius: 6,
        arrowWidth: 24,
        arrowHeight: 25,
        centerMinWidth: 70,
        centerHorizontalPadding: 8,
        centerHeight: 25,
        arrowFont: .system(size: 11, weight: .semibold),
        labelFont: .sora(12, weight: .medium).monospacedDigit(),
        background: Color.primary.opacity(0.06),
        selectedBackground: AppSurface.pillSelectedFill,
        selectedBorder: AppSurface.pillSelectedStroke,
        selectedBorderWidth: 1,
        arrowForeground: Color.stxMuted,
        disabledForeground: Color.stxMuted.opacity(0.35),
        selectedForeground: Color.primary,
        unselectedForeground: Color.stxMuted
    )

    static let compact = PillTimeStepperBarStyle(
        itemSpacing: 2,
        outerPadding: 3,
        outerCornerRadius: 8,
        selectedCornerRadius: 6,
        arrowWidth: 24,
        arrowHeight: 25,
        centerMinWidth: 52,
        centerHorizontalPadding: 7,
        centerHeight: 25,
        arrowFont: .system(size: 11, weight: .semibold),
        labelFont: .sora(12, weight: .medium).monospacedDigit(),
        background: Color.primary.opacity(0.06),
        selectedBackground: AppSurface.pillSelectedFill,
        selectedBorder: AppSurface.pillSelectedStroke,
        selectedBorderWidth: 1,
        arrowForeground: Color.stxMuted,
        disabledForeground: Color.stxMuted.opacity(0.35),
        selectedForeground: Color.primary,
        unselectedForeground: Color.stxMuted
    )
}

private extension View {
    @ViewBuilder
    func pillTimeStepperHelp(_ help: String?) -> some View {
        if let help {
            self.help(help)
        } else {
            self
        }
    }

    @ViewBuilder
    func pillTimeStepperAccessibilityLabel(_ label: String?) -> some View {
        if let label {
            self.accessibilityLabel(Text(label))
        } else {
            self
        }
    }
}

#if DEBUG
#Preview {
    PillTimeStepperBar(
        canStepForward: false,
        isCenterSelected: true,
        previousHelp: "Previous day",
        nextHelp: "Next day",
        centerHelp: "Show selected day",
        centerAccessibilityLabel: "Selected day",
        accessibilityLabel: "Day navigation",
        onPrevious: {},
        onNext: {},
        onCenter: {}
    ) { _ in
        Text("Today")
    }
    .padding(24)
    .frame(width: 360)
    .background(Color.stxBackground)
}
#endif
