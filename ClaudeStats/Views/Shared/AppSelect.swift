import AppKit
import SwiftUI

enum AppSelectText: Hashable {
    case localized(String)
    case verbatim(String)

    var text: Text {
        switch self {
        case .localized(let value):
            Text(LocalizedStringKey(value))
        case .verbatim(let value):
            Text(verbatim: value)
        }
    }

    var accessibilityValue: String {
        switch self {
        case .localized(let value), .verbatim(let value):
            value
        }
    }
}

struct AppSelectOption<Value: Hashable>: Identifiable, Hashable {
    let value: Value
    let title: AppSelectText
    var subtitle: AppSelectText?
    var systemImage: String?
    var isDisabled: Bool

    var id: Value { value }

    init(
        value: Value,
        title: AppSelectText,
        subtitle: AppSelectText? = nil,
        systemImage: String? = nil,
        isDisabled: Bool = false
    ) {
        self.value = value
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.isDisabled = isDisabled
    }
}

enum AppSelectSize {
    case regular
    case small

    var triggerHeight: CGFloat {
        switch self {
        case .regular: 32
        case .small: 28
        }
    }

    var triggerCornerRadius: CGFloat {
        switch self {
        case .regular: 9
        case .small: 8
        }
    }

    var triggerHorizontalPadding: CGFloat {
        switch self {
        case .regular: 12
        case .small: 10
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .regular: 38
        case .small: 34
        }
    }

    var titleFont: Font {
        switch self {
        case .regular: .sora(12, weight: .semibold)
        case .small: .sora(11, weight: .semibold)
        }
    }

    var subtitleFont: Font {
        switch self {
        case .regular: .sora(10)
        case .small: .sora(9)
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .regular: 13
        case .small: 12
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .regular: 128
        case .small: 104
        }
    }
}

struct AppSelect<Value: Hashable>: View {
    private let title: AppSelectText?
    @Binding private var selection: Value
    private let options: [AppSelectOption<Value>]
    private let placeholder: AppSelectText
    private let width: CGFloat?
    private let menuMaxHeight: CGFloat
    private let size: AppSelectSize
    private let isLoading: Bool
    private let emptyTitle: AppSelectText
    private let onSelectionChange: ((Value) -> Void)?

    @Environment(\.isEnabled) private var isEnvironmentEnabled
    @State private var isPresented = false
    @State private var anchorBox = AppSelectAnchorBox()

    init(
        _ title: AppSelectText?,
        selection: Binding<Value>,
        options: [AppSelectOption<Value>],
        placeholder: AppSelectText = .localized("Select"),
        width: CGFloat? = nil,
        menuMaxHeight: CGFloat = 260,
        size: AppSelectSize = .regular,
        isLoading: Bool = false,
        emptyTitle: AppSelectText = .localized("No options"),
        onSelectionChange: ((Value) -> Void)? = nil
    ) {
        self.title = title
        _selection = selection
        self.options = options
        self.placeholder = placeholder
        self.width = width
        self.menuMaxHeight = menuMaxHeight
        self.size = size
        self.isLoading = isLoading
        self.emptyTitle = emptyTitle
        self.onSelectionChange = onSelectionChange
    }

    var body: some View {
        Button {
            togglePanel()
        } label: {
            triggerLabel
        }
        .buttonStyle(.plain)
        .disabled(isEffectivelyDisabled)
        .frame(width: width)
        .frame(minWidth: width == nil ? size.minimumWidth : nil)
        .background(AppSelectAnchorReader(anchorBox: anchorBox))
        .opacity(isEnvironmentEnabled ? 1 : 0.48)
        .accessibilityLabel(Text(title?.accessibilityValue ?? selectedText.accessibilityValue))
        .accessibilityValue(Text(selectedText.accessibilityValue))
        .accessibilityAddTraits(.isButton)
        .onDisappear {
            if isPresented {
                AppSelectPanelPresenter.shared.close()
            }
        }
    }

    private var triggerLabel: some View {
        HStack(spacing: 8) {
            if let symbol = selectedOption?.systemImage {
                Image(systemName: symbol)
                    .font(.system(size: size.iconSize, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .frame(width: 16)
            }

            selectedText.text
                .font(size.titleFont)
                .foregroundStyle(isEffectivelyDisabled ? Color.stxMuted.opacity(0.55) : Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            if isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 14, height: 14)
            } else {
                Image(systemName: AppIcon.Navigation.down)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.stxMuted)
                    .rotationEffect(.degrees(isPresented ? 180 : 0))
            }
        }
        .padding(.horizontal, size.triggerHorizontalPadding)
        .frame(height: size.triggerHeight)
        .frame(maxWidth: width == nil ? nil : .infinity)
        .background(triggerFill, in: RoundedRectangle(cornerRadius: size.triggerCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size.triggerCornerRadius, style: .continuous)
                .strokeBorder(isPresented ? Color.stxAccent.opacity(0.48) : Color.stxStroke, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: size.triggerCornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.14), value: isPresented)
    }

    private var triggerFill: Color {
        if isPresented {
            return AppSurface.pillFill.opacity(0.95)
        }
        return AppSurface.pillFill
    }

    private var selectedOption: AppSelectOption<Value>? {
        options.first { $0.value == selection }
    }

    private var selectedText: AppSelectText {
        selectedOption?.title ?? placeholder
    }

    private var isEffectivelyDisabled: Bool {
        !isEnvironmentEnabled || isLoading
    }

    private func togglePanel() {
        guard !isEffectivelyDisabled else { return }
        guard let anchorView = anchorBox.view else { return }
        if AppSelectPanelPresenter.shared.consumeRecentClose(for: anchorView) {
            return
        }
        if isPresented {
            AppSelectPanelPresenter.shared.close()
            return
        }

        isPresented = true
        let panelWidth = max(width ?? anchorView.bounds.width, size.minimumWidth)
        let panelHeight = AppSelectPanelContent.estimatedHeight(
            options: options,
            rowHeight: size.rowHeight,
            maxHeight: menuMaxHeight,
            isLoading: isLoading
        )

        AppSelectPanelPresenter.shared.present(
            from: anchorView,
            size: CGSize(width: panelWidth, height: panelHeight),
            onDismiss: { isPresented = false },
            content: AnyView(
                AppSelectPanelContent(
                    selection: $selection,
                    options: options,
                    size: size,
                    maxHeight: menuMaxHeight,
                    isLoading: isLoading,
                    emptyTitle: emptyTitle,
                    onSelectionChange: onSelectionChange
                )
            )
        )
    }
}

private struct AppSelectPanelContent<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [AppSelectOption<Value>]
    let size: AppSelectSize
    let maxHeight: CGFloat
    let isLoading: Bool
    let emptyTitle: AppSelectText
    let onSelectionChange: ((Value) -> Void)?

    @State private var activeValue: Value?

    static func estimatedHeight(
        options: [AppSelectOption<Value>],
        rowHeight: CGFloat,
        maxHeight: CGFloat,
        isLoading: Bool
    ) -> CGFloat {
        if isLoading || options.isEmpty {
            return min(maxHeight, 54)
        }
        let rowsHeight = CGFloat(options.count) * rowHeight
        return min(maxHeight, rowsHeight + 12)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        Group {
            if isLoading {
                loadingBody
            } else if options.isEmpty {
                emptyBody
            } else if estimatedContentHeight > maxHeight {
                AppScrollView {
                    optionsBody
                }
                .frame(height: maxHeight)
                .background(AppSelectScrollBackgroundClearer())
            } else {
                optionsBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppSurface.panelFill)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(Color.stxStroke, lineWidth: 1)
        }
        .background(AppSelectKeyCapture { event in
            handleKeyDown(event)
        })
        .onAppear {
            activeValue = enabledOptions.first(where: { $0.value == selection })?.value ?? enabledOptions.first?.value
        }
    }

    private var optionsBody: some View {
        VStack(spacing: 2) {
            ForEach(options) { option in
                optionRow(option)
            }
        }
        .padding(6)
    }

    private var loadingBody: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(LocalizedStringKey("Loading"))
                .font(size.titleFont)
                .foregroundStyle(Color.stxMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyBody: some View {
        emptyTitle.text
            .font(size.titleFont)
            .foregroundStyle(Color.stxMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var estimatedContentHeight: CGFloat {
        CGFloat(options.count) * size.rowHeight + 12
    }

    private var enabledOptions: [AppSelectOption<Value>] {
        options.filter { !$0.isDisabled }
    }

    private func optionRow(_ option: AppSelectOption<Value>) -> some View {
        let isSelected = option.value == selection
        let isActive = option.value == activeValue
        return Button {
            select(option)
        } label: {
            HStack(spacing: 10) {
                if let symbol = option.systemImage {
                    Image(systemName: symbol)
                        .font(.system(size: size.iconSize, weight: .semibold))
                        .foregroundStyle(option.isDisabled ? Color.stxMuted.opacity(0.35) : Color.stxMuted)
                        .frame(width: 16)
                }

                VStack(alignment: .leading, spacing: 2) {
                    option.title.text
                        .font(size.titleFont)
                        .foregroundStyle(option.isDisabled ? Color.stxMuted.opacity(0.38) : Color.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let subtitle = option.subtitle {
                        subtitle.text
                            .font(size.subtitleFont)
                            .foregroundStyle(Color.stxMuted)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 10)

                Image(systemName: AppIcon.Action.confirm)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary.opacity(0.78) : Color.clear)
                    .frame(width: 16)
            }
            .padding(.horizontal, 18)
            .frame(height: size.rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Color.primary.opacity(0.075) : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(option.isDisabled)
        .onHover { hovering in
            if hovering, !option.isDisabled {
                activeValue = option.value
            }
        }
        .accessibilityLabel(option.title.text)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func select(_ option: AppSelectOption<Value>) {
        guard !option.isDisabled else { return }
        selection = option.value
        onSelectionChange?(option.value)
        AppSelectPanelPresenter.shared.close()
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            AppSelectPanelPresenter.shared.close()
            return true
        case 36, 49, 76:
            chooseActiveOption()
            return true
        case 125:
            moveActiveOption(by: 1)
            return true
        case 126:
            moveActiveOption(by: -1)
            return true
        case 48:
            AppSelectPanelPresenter.shared.close()
            return false
        default:
            return false
        }
    }

    private func moveActiveOption(by delta: Int) {
        let enabled = enabledOptions
        guard !enabled.isEmpty else { return }
        let currentIndex = activeValue.flatMap { value in enabled.firstIndex { $0.value == value } }
            ?? enabled.firstIndex { $0.value == selection }
            ?? 0
        let nextIndex = (currentIndex + delta + enabled.count) % enabled.count
        activeValue = enabled[nextIndex].value
    }

    private func chooseActiveOption() {
        guard let option = activeValue.flatMap({ value in enabledOptions.first { $0.value == value } })
            ?? enabledOptions.first(where: { $0.value == selection })
            ?? enabledOptions.first
        else { return }
        select(option)
    }
}

private final class AppSelectAnchorBox {
    weak var view: NSView?
}

private struct AppSelectAnchorReader: NSViewRepresentable {
    let anchorBox: AppSelectAnchorBox

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        anchorBox.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchorBox.view = nsView
    }
}

private struct AppSelectKeyCapture: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyView {
        KeyView(onKeyDown: onKeyDown)
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.window?.makeFirstResponder(nsView)
    }

    final class KeyView: NSView {
        var onKeyDown: (NSEvent) -> Bool

        init(onKeyDown: @escaping (NSEvent) -> Bool) {
            self.onKeyDown = onKeyDown
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            if !onKeyDown(event) {
                super.keyDown(with: event)
            }
        }
    }
}

private struct AppSelectScrollBackgroundClearer: NSViewRepresentable {
    func makeNSView(context: Context) -> ClearerView {
        ClearerView()
    }

    func updateNSView(_ nsView: ClearerView, context: Context) {
        nsView.clearScrollBackground()
    }

    final class ClearerView: NSView {
        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            clearScrollBackground()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearScrollBackground()
        }

        override func layout() {
            super.layout()
            clearScrollBackground()
        }

        func clearScrollBackground() {
            guard let scrollView = enclosingNativeScrollView else { return }
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.contentView.drawsBackground = false
        }

        private var enclosingNativeScrollView: NSScrollView? {
            if let scrollView = enclosingScrollView {
                return scrollView
            }

            var candidate = superview
            while let view = candidate {
                if let scrollView = view as? NSScrollView {
                    return scrollView
                }
                candidate = view.superview
            }
            return nil
        }
    }
}

@MainActor
private final class AppSelectPanelPresenter {
    static let shared = AppSelectPanelPresenter()

    private var panel: AppSelectPanel?
    private var onDismiss: (() -> Void)?
    private weak var presentedAnchorView: NSView?
    private weak var recentlyClosedAnchorView: NSView?
    private var recentlyClosedAt: Date?
    private var isClosing = false

    func present(from anchorView: NSView, size: CGSize, onDismiss: @escaping () -> Void, content: AnyView) {
        close()

        guard let window = anchorView.window else { return }

        self.onDismiss = onDismiss
        presentedAnchorView = anchorView
        let panel = AppSelectPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.presenter = self
        panel.appearance = anchorView.effectiveAppearance
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.transient, .ignoresCycle]
        panel.level = .popUpMenu
        panel.contentView = AppSelectHostingView(rootView: content)
        panel.setFrame(frame(for: anchorView, in: window, size: size), display: true)

        self.panel = panel
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func close() {
        guard let panel else { return }
        isClosing = true
        panel.orderOut(nil)
        self.panel = nil
        recentlyClosedAnchorView = presentedAnchorView
        recentlyClosedAt = Date()
        presentedAnchorView = nil
        let dismiss = onDismiss
        onDismiss = nil
        isClosing = false
        dismiss?()
    }

    func consumeRecentClose(for anchorView: NSView) -> Bool {
        guard recentlyClosedAnchorView === anchorView,
              let recentlyClosedAt,
              Date().timeIntervalSince(recentlyClosedAt) < 0.35
        else {
            return false
        }
        recentlyClosedAnchorView = nil
        self.recentlyClosedAt = nil
        return true
    }

    fileprivate func panelDidResignKey() {
        guard !isClosing else { return }
        close()
    }

    private func frame(for anchorView: NSView, in window: NSWindow, size: CGSize) -> NSRect {
        let anchorRect = window.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
        let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame ?? anchorRect
        let spacing: CGFloat = 4
        let margin: CGFloat = 8
        var origin = NSPoint(x: anchorRect.minX, y: anchorRect.minY - size.height - spacing)

        if origin.y < screenFrame.minY + margin {
            origin.y = anchorRect.maxY + spacing
        }
        if origin.x + size.width > screenFrame.maxX - margin {
            origin.x = screenFrame.maxX - size.width - margin
        }
        if origin.x < screenFrame.minX + margin {
            origin.x = screenFrame.minX + margin
        }

        return NSRect(origin: origin, size: size)
    }
}

private final class AppSelectHostingView: NSHostingView<AnyView> {
    override var isOpaque: Bool { false }

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configure()
    }

    override func layout() {
        super.layout()
        configure()
    }

    private func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private final class AppSelectPanel: NSPanel {
    weak var presenter: AppSelectPanelPresenter?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        presenter?.panelDidResignKey()
    }
}

#if DEBUG
private enum AppSelectPreviewMode: String, CaseIterable, Identifiable {
    case never
    case focused
    case always

    var id: String { rawValue }
    var title: String {
        switch self {
        case .never: "从不"
        case .focused: "仅当应用失焦时"
        case .always: "始终"
        }
    }
}

#Preview("AppSelect") {
    struct AppSelectPreview: View {
        @State private var mode: AppSelectPreviewMode = .focused
        @State private var emptyMode: AppSelectPreviewMode = .focused

        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                AppSelect(
                    .localized("Notification behavior"),
                    selection: $mode,
                    options: AppSelectPreviewMode.allCases.map {
                        AppSelectOption(value: $0, title: .verbatim($0.title))
                    },
                    width: 220
                )
                AppSelect(
                    .localized("Small select"),
                    selection: $mode,
                    options: AppSelectPreviewMode.allCases.map {
                        AppSelectOption(value: $0, title: .verbatim($0.title))
                    },
                    width: 180,
                    size: .small
                )
                AppSelect(
                    .localized("Disabled select"),
                    selection: $mode,
                    options: AppSelectPreviewMode.allCases.map {
                        AppSelectOption(value: $0, title: .verbatim($0.title))
                    },
                    width: 220
                )
                .disabled(true)
                AppSelect(
                    .localized("Empty select"),
                    selection: $emptyMode,
                    options: [],
                    width: 220
                )
            }
            .padding(24)
            .background(AppSurface.backgroundFill)
        }
    }

    return AppSelectPreview()
}
#endif
