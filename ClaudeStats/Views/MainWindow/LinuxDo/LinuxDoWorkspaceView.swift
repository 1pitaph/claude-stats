import SwiftUI

private enum LinuxDoPaneMetrics {
    static let listMinWidth: CGFloat = 340
    static let detailMinWidth: CGFloat = 430
    static let listDefaultFraction: CGFloat = 0.1
    static let detailConfiguration = HoverableSplitViewConfiguration(
        primaryMinimumPaneLength: listMinWidth,
        secondaryMinimumPaneLength: detailMinWidth
    )
}

private enum LinuxDoTopPeriodDisclosurePhase: Equatable, Sendable {
    case hidden
    case waitingToReveal
    case revealing
    case visible
    case hiding

    var mountsBar: Bool {
        self != .hidden
    }

    var showsButtons: Bool {
        switch self {
        case .revealing, .visible, .hiding:
            true
        case .hidden, .waitingToReveal:
            false
        }
    }

    var buttonOpacity: Double {
        self == .hiding ? 0 : (showsButtons ? 1 : 0)
    }

    var buttonYOffset: CGFloat {
        showsButtons ? 0 : -4
    }
}

private enum LinuxDoTopPeriodDisclosureMotion {
    static let expand: Animation = .easeOut(duration: 0.18)
    static let collapse: Animation = .easeOut(duration: 0.16)
    static let revealInitialDelay: TimeInterval = 0.08
    static let revealDuration: TimeInterval = 0.16
    static let revealDelayStep: TimeInterval = 0.035
    static let hideFadeDuration: TimeInterval = 0.10

    static func revealDelay(for index: Int) -> TimeInterval {
        TimeInterval(index) * revealDelayStep
    }

    static func buttonAnimation(for phase: LinuxDoTopPeriodDisclosurePhase, index: Int) -> Animation {
        switch phase {
        case .revealing:
            .easeOut(duration: revealDuration).delay(revealDelay(for: index))
        case .hiding:
            .easeOut(duration: hideFadeDuration)
        case .hidden, .waitingToReveal, .visible:
            .easeOut(duration: revealDuration)
        }
    }

    static var totalRevealDuration: TimeInterval {
        guard !LinuxDoTopPeriod.allCases.isEmpty else {
            return revealDuration
        }
        return revealDelay(for: LinuxDoTopPeriod.allCases.count - 1) + revealDuration
    }

    static func nanoseconds(for interval: TimeInterval) -> UInt64 {
        UInt64((interval * 1_000_000_000).rounded())
    }
}

struct LinuxDoWorkspaceView: View {
    @Bindable var store: LinuxDoStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LinuxDoHeader(store: store)
            StxRule()
            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            await store.loadInitialIfNeeded()
        }
    }

    private var workspace: some View {
        HoverableSplitView(
            axis: .vertical,
            primaryFraction: LinuxDoPaneMetrics.listDefaultFraction,
            configuration: LinuxDoPaneMetrics.detailConfiguration
        ) {
            LinuxDoTopicListView(store: store)
                .frame(
                    minWidth: 0,
                    idealWidth: LinuxDoPaneMetrics.listMinWidth,
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        } secondary: {
            LinuxDoTopicDetailView(store: store)
                .frame(minWidth: 0, idealWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct LinuxDoHeader: View {
    @Bindable var store: LinuxDoStore
    @State private var topPeriodPhase: LinuxDoTopPeriodDisclosurePhase = .hidden
    @State private var topPeriodTransitionTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COMMUNITY")
                        .font(.sora(11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.stxMuted)
                    Text("LinuxDo")
                        .font(.sora(24, weight: .semibold))
                    Text("Browse Linux.do topics with a native macOS reader.")
                        .font(.sora(12))
                        .foregroundStyle(Color.stxMuted)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                Button {
                    store.presentNewTopicComposer()
                } label: {
                    Label("New Topic", systemImage: AppIcon.Action.compose)
                }
                .controlSize(.small)
                .help(store.canWriteForum ? "Create a LinuxDo topic" : "Sign in with a browser session to create topics")
            }

            if topPeriodPhase.mountsBar {
                LinuxDoTopPeriodBar(store: store, phase: topPeriodPhase)
                    .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(.horizontal, LinuxDoLayout.contentInset)
        .padding(.top, 50)
        .padding(.bottom, 16)
        .onChange(of: isTopFeedSelected, initial: true) { _, isSelected in
            updateTopPeriodDisclosure(isSelected)
        }
        .onDisappear {
            topPeriodTransitionTask?.cancel()
            topPeriodTransitionTask = nil
        }
        .sheet(isPresented: newTopicPresented) {
            LinuxDoNewTopicSheet(store: store)
        }
    }

    private var newTopicPresented: Binding<Bool> {
        Binding(
            get: { store.newTopicComposer.isPresented },
            set: { isPresented in
                if isPresented {
                    store.presentNewTopicComposer()
                } else {
                    store.cancelNewTopicComposer()
                }
            }
        )
    }

    private var isTopFeedSelected: Bool {
        if case .top = store.selectedFeed {
            true
        } else {
            false
        }
    }

    private func updateTopPeriodDisclosure(_ shouldShow: Bool) {
        topPeriodTransitionTask?.cancel()
        topPeriodTransitionTask = Task { @MainActor in
            if shouldShow {
                guard topPeriodPhase != .visible, topPeriodPhase != .revealing else { return }
                withAnimation(LinuxDoTopPeriodDisclosureMotion.expand) {
                    topPeriodPhase = .waitingToReveal
                }
                try? await Task.sleep(
                    nanoseconds: LinuxDoTopPeriodDisclosureMotion.nanoseconds(
                        for: LinuxDoTopPeriodDisclosureMotion.revealInitialDelay
                    )
                )
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: LinuxDoTopPeriodDisclosureMotion.revealDuration)) {
                    topPeriodPhase = .revealing
                }
                try? await Task.sleep(
                    nanoseconds: LinuxDoTopPeriodDisclosureMotion.nanoseconds(
                        for: LinuxDoTopPeriodDisclosureMotion.totalRevealDuration
                    )
                )
                guard !Task.isCancelled else { return }
                topPeriodPhase = .visible
            } else {
                guard topPeriodPhase != .hidden else { return }
                withAnimation(.easeOut(duration: LinuxDoTopPeriodDisclosureMotion.hideFadeDuration)) {
                    topPeriodPhase = .hiding
                }
                try? await Task.sleep(
                    nanoseconds: LinuxDoTopPeriodDisclosureMotion.nanoseconds(
                        for: LinuxDoTopPeriodDisclosureMotion.hideFadeDuration
                    )
                )
                guard !Task.isCancelled else { return }
                withAnimation(LinuxDoTopPeriodDisclosureMotion.collapse) {
                    topPeriodPhase = .hidden
                }
            }
        }
    }
}

private struct LinuxDoNewTopicSheet: View {
    @Bindable var store: LinuxDoStore
    @FocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("New LinuxDo Topic")
                    .font(.sora(16, weight: .semibold))
                Spacer(minLength: 0)
                Button("Cancel") {
                    store.cancelNewTopicComposer()
                }
                .controlSize(.small)
            }

            TextField("Title", text: $store.newTopicComposer.title)
                .textFieldStyle(.roundedBorder)
                .font(.sora(12))
                .focused($titleFocused)
                .onSubmit {
                    Task { await store.submitNewTopic() }
                }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.newTopicComposer.raw)
                    .font(.sora(12))
                    .frame(minHeight: 180)
                    .scrollContentBackground(.hidden)
                if store.newTopicComposer.raw.isEmpty {
                    Text("Write the topic body")
                        .font(.sora(12))
                        .foregroundStyle(Color.stxMuted)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .padding(6)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }

            if let error = store.newTopicComposer.error {
                LinuxDoInlineError(message: error)
            }

            HStack {
                Spacer(minLength: 0)
                Button {
                    Task { await store.submitNewTopic() }
                } label: {
                    if store.newTopicComposer.isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Create Topic", systemImage: AppIcon.Action.send)
                    }
                }
                .controlSize(.small)
                .disabled(!store.newTopicComposer.canSubmitTopic)
            }
        }
        .padding(22)
        .frame(width: 520)
        .onAppear {
            titleFocused = true
        }
    }
}

private struct LinuxDoTopPeriodBar: View {
    @Bindable var store: LinuxDoStore
    let phase: LinuxDoTopPeriodDisclosurePhase

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(LinuxDoTopPeriod.allCases.enumerated()), id: \.element.id) { index, period in
                Button {
                    store.selectTopPeriod(period)
                } label: {
                    Label(period.displayName, systemImage: period.symbolName)
                        .font(.sora(11, weight: store.topPeriod == period ? .semibold : .medium))
                        .foregroundStyle(store.topPeriod == period ? Color.stxAccent : Color.stxMuted)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background {
                            if store.topPeriod == period {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.stxAccent.opacity(0.13))
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Top \(period.displayName)")
                .opacity(phase.buttonOpacity)
                .offset(y: phase.buttonYOffset)
                .animation(LinuxDoTopPeriodDisclosureMotion.buttonAnimation(for: phase, index: index), value: phase)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private extension LinuxDoTopPeriod {
    var symbolName: String {
        switch self {
        case .daily:
            AppIcon.Leaderboard.day
        case .weekly:
            AppIcon.Leaderboard.week
        case .monthly:
            AppIcon.Leaderboard.month
        case .quarterly:
            AppIcon.Workspace.usage
        case .yearly:
            AppIcon.Leaderboard.year
        case .all:
            AppIcon.Leaderboard.allTime
        }
    }
}

#if DEBUG
#Preview("LinuxDo workspace") {
    LinuxDoWorkspaceView(store: AppEnvironment.preview().linuxDo)
        .environment(AppEnvironment.preview())
        .frame(width: 1040, height: 720)
}
#endif
