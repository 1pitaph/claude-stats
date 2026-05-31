import SwiftUI

struct NetworkSidebarColumn: View {
    @Bindable var store: NetworkDebuggerStore
    @Binding var section: NetworkSection
    var onExit: () -> Void

    @State private var favoritesExpanded = true
    @State private var appsExpanded = true
    @State private var domainsExpanded = true
    @State private var methodsExpanded = false
    @State private var statusesExpanded = false
    @State private var protocolsExpanded = false
    @State private var trafficFiltersHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 44)
            sidebarDeck
        }
        .padding(.bottom, 10)
    }

    private var sidebarDeck: some View {
        HStack(alignment: .top, spacing: 0) {
            sectionsSidebar
                .frame(width: Self.sidebarWidth, alignment: .topLeading)
                .allowsHitTesting(store.trafficSidebarLayer == .sections)
                .accessibilityHidden(store.trafficSidebarLayer != .sections)
            filtersSidebar
                .frame(width: Self.sidebarWidth, alignment: .topLeading)
                .allowsHitTesting(store.trafficSidebarLayer == .filters)
                .accessibilityHidden(store.trafficSidebarLayer != .filters)
        }
        .frame(width: Self.sidebarWidth * 2, alignment: .leading)
        .offset(x: store.trafficSidebarLayer == .filters ? -Self.sidebarWidth : 0)
        .frame(width: Self.sidebarWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .animation(MainWindowMotion.modeSwitchAnimation, value: store.trafficSidebarLayer)
    }

    private var sectionsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarRow(title: "Back to App",
                       symbol: AppIcon.Navigation.back,
                       isSelected: false,
                       action: onExit)

            captureControls
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 10)

            trafficSplitRow

            ForEach(NetworkSection.allCases.filter { $0 != .traffic }) { item in
                SidebarRow(title: item.title,
                           symbol: item.symbol,
                           isSelected: section == item) {
                    section = item
                }
            }
        }
    }

    private var filtersSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarRow(title: "Back",
                       symbol: AppIcon.Navigation.back,
                       isSelected: false) {
                withAnimation(MainWindowMotion.modeSwitchAnimation) {
                    store.trafficSidebarLayer = .sections
                }
            }

            filterField
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

            if !store.trafficFilter.isEmpty {
                Button {
                    store.resetTrafficFilters()
                } label: {
                    Label("Clear Filters", systemImage: AppIcon.Action.cancel)
                        .font(.sora(11, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8)
            }

            AppScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    filterGroup(title: "Favorites", isExpanded: $favoritesExpanded) {
                        filterLeaf(
                            title: "Pinned",
                            symbol: AppIcon.Action.pinFilled,
                            count: store.pinnedTrafficCount,
                            selected: store.trafficFilter.pinnedOnly,
                            action: store.togglePinnedFilter
                        )
                        filterLeaf(
                            title: "Saved",
                            symbol: AppIcon.Action.downloadTray,
                            count: store.savedTrafficCount,
                            selected: store.trafficFilter.savedOnly,
                            action: store.toggleSavedFilter
                        )
                    }

                    filterGroup(title: "Apps", isExpanded: $appsExpanded) {
                        ForEach(store.trafficApps.prefix(20)) { item in
                            filterLeaf(
                                title: item.title,
                                symbol: item.symbol,
                                count: item.count,
                                selected: store.trafficFilter.apps.contains(item.title)
                            ) {
                                store.toggleAppFilter(item.title)
                            }
                        }
                    }

                    filterGroup(title: "Domains", isExpanded: $domainsExpanded) {
                        ForEach(store.trafficDomains.prefix(30)) { item in
                            filterLeaf(
                                title: item.title,
                                symbol: item.symbol,
                                count: item.count,
                                selected: store.trafficFilter.domains.contains(item.title)
                            ) {
                                store.toggleDomainFilter(item.title)
                            }
                        }
                    }

                    filterGroup(title: "Methods", isExpanded: $methodsExpanded) {
                        ForEach(store.trafficMethods) { item in
                            filterLeaf(
                                title: item.title,
                                symbol: item.symbol,
                                count: item.count,
                                selected: store.trafficFilter.methods.contains(item.title)
                            ) {
                                store.toggleMethodFilter(item.title)
                            }
                        }
                    }

                    filterGroup(title: "Status", isExpanded: $statusesExpanded) {
                        ForEach(NetworkTrafficStatusFilter.allCases) { status in
                            filterLeaf(
                                title: status.title,
                                symbol: AppIcon.Metric.number,
                                count: store.statusCount(for: status),
                                selected: store.trafficFilter.statuses.contains(status)
                            ) {
                                store.toggleStatusFilter(status)
                            }
                        }
                    }

                    filterGroup(title: "Protocols", isExpanded: $protocolsExpanded) {
                        ForEach(NetworkFlowProtocol.allCases) { proto in
                            filterLeaf(
                                title: proto.rawValue,
                                symbol: AppIcon.Network.webSocket,
                                count: store.protocolCount(for: proto),
                                selected: store.trafficFilter.protocols.contains(proto)
                            ) {
                                store.toggleProtocolFilter(proto)
                            }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var trafficSplitRow: some View {
        HStack(spacing: 4) {
            Button {
                section = .traffic
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: NetworkSection.traffic.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 18)
                        .foregroundStyle(section == .traffic ? Color.stxAccent : Color.stxMuted)
                    Text(NetworkSection.traffic.title)
                        .font(.sora(13))
                        .foregroundStyle(section == .traffic ? .primary : Color.stxMuted)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: Self.trafficChipHeight)
                .background {
                    if section == .traffic {
                        RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.10))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                section = .traffic
                withAnimation(MainWindowMotion.modeSwitchAnimation) {
                    store.trafficSidebarLayer = .filters
                }
            } label: {
                Image(systemName: AppIcon.Navigation.disclosure)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(trafficFiltersHover ? Color.stxAccent : Color.stxMuted)
                    .frame(width: Self.trafficChipHeight, height: Self.trafficChipHeight)
                    .background(trafficFiltersHover ? Color.stxAccent.opacity(0.16) : Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(trafficFiltersHover ? Color.stxAccent.opacity(0.38) : Color.clear, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .help("Open traffic filters")
            .onHover { trafficFiltersHover = $0 }
            .animation(.easeOut(duration: 0.12), value: trafficFiltersHover)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 1)
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            statusPill

            HStack(spacing: 8) {
                Button {
                    if store.captureStatus.isListening {
                        store.stopCapture()
                    } else {
                        store.startCapture()
                    }
                } label: {
                    Image(systemName: store.captureStatus.isListening ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.bordered)
                .help(store.captureStatus.isListening ? "Stop capture" : "Start capture")

                Button {
                    store.clearFlows()
                } label: {
                    Image(systemName: AppIcon.Action.delete)
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.bordered)
                .disabled(store.flows.isEmpty)
                .help("Clear traffic")
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.045))
        }
    }

    private var statusPill: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(store.captureStatus.isListening ? Color.green : Color.stxMuted.opacity(0.5))
                .frame(width: 8, height: 8)
            Text(store.statusMessage)
                .font(.sora(11, weight: .medium))
                .foregroundStyle(store.captureStatus.isListening ? .primary : Color.stxMuted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var filterField: some View {
        HStack(spacing: 6) {
            Image(systemName: AppIcon.Action.search)
                .font(.system(size: 11))
                .foregroundStyle(Color.stxMuted)
            TextField("Filter", text: $store.searchText)
                .textFieldStyle(.plain)
                .font(.sora(11))
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: AppIcon.Action.clear)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.stxMuted)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.06)))
    }

    private func filterGroup<Content: View>(
        title: String,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                isExpanded.wrappedValue.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: AppIcon.Navigation.disclosure)
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 90 : 0))
                        .foregroundStyle(Color.stxMuted)
                        .frame(width: 10)
                    Text(title)
                        .font(.sora(11, weight: .semibold))
                        .foregroundStyle(Color.stxMuted)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
            }
        }
    }

    private func filterLeaf(
        title: String,
        symbol: String,
        count: Int,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Color.stxAccent : Color.stxMuted)
                Text(title)
                    .font(.sora(12, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(selected ? .primary : Color.stxMuted)
                Spacer(minLength: 6)
                Text("\(count)")
                    .font(.sora(10).monospacedDigit())
                    .foregroundStyle(Color.stxMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

private extension NetworkSidebarColumn {
    static let sidebarWidth = MainWindowMotion.networkSidebarWidth
    static let trafficChipHeight: CGFloat = 32
}

#if DEBUG
#Preview("Network sidebar") {
    @Previewable @State var section: NetworkSection = .traffic
    @Previewable @State var store = NetworkDebuggerStore()
    return NetworkSidebarColumn(store: store, section: $section, onExit: {})
        .frame(width: 240, height: 620)
        .background(VisualEffectBackground())
}
#endif
