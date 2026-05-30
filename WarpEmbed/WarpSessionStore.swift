import Combine
import Foundation

public struct WarpSessionTabItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let subtitle: String?
    public let needsAttention: Bool
}

@MainActor
public final class WarpSessionStore: ObservableObject {
    @Published public private(set) var tabs: [WarpSessionTabItem] = []
    @Published public var selectedTabID: UUID?
    @Published public private(set) var availability: WarpRuntimeAvailability

    private let runtime: WarpRuntime

    public init(runtime: WarpRuntime = WarpRuntime()) {
        self.runtime = runtime
        self.availability = runtime.availability()
    }

    public func refreshAvailability() {
        availability = runtime.availability()
    }

    public func ensureDefaultSession() {
        refreshAvailability()
        guard tabs.isEmpty else { return }
        let id = UUID()
        tabs = [
            WarpSessionTabItem(
                id: id,
                title: availability.isReady ? "Warp" : "Warp bridge unavailable",
                subtitle: availability.message,
                needsAttention: !availability.isReady
            )
        ]
        selectedTabID = id
    }

    @discardableResult
    public func closeSelectedSession(force: Bool) -> Bool {
        guard let selectedTabID else { return true }
        tabs.removeAll { $0.id == selectedTabID }
        self.selectedTabID = tabs.first?.id
        return true
    }
}
