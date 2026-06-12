import Foundation
import Observation

struct AppNotice: Identifiable, Sendable, Hashable {
    enum Severity: Sendable, Hashable {
        case info
        case success
        case warning
        case error
    }

    enum Action: Sendable, Hashable {
        case openSettings(SettingsSection)
    }

    let id: UUID
    let title: String
    let message: String
    let severity: Severity
    let actionTitle: String?
    let action: Action?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        severity: Severity,
        actionTitle: String? = nil,
        action: Action? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.severity = severity
        self.actionTitle = actionTitle
        self.action = action
        self.createdAt = createdAt
    }
}

@MainActor
@Observable
final class AppNoticeStore {
    private(set) var current: AppNotice?
    @ObservationIgnored private var autoDismissTask: Task<Void, Never>?

    func show(
        title: String,
        message: String,
        severity: AppNotice.Severity,
        actionTitle: String? = nil,
        action: AppNotice.Action? = nil
    ) {
        let notice = AppNotice(
            title: title,
            message: message,
            severity: severity,
            actionTitle: actionTitle,
            action: action
        )
        current = notice
        autoDismissTask?.cancel()
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.dismiss(id: notice.id)
            }
        }
    }

    func showGitFailure(_ failure: GitOperationFailureNotice) {
        show(
            title: failure.title,
            message: failure.message,
            severity: .error,
            actionTitle: "View Logs",
            action: .openSettings(.logs)
        )
    }

    func dismiss(id: UUID? = nil) {
        guard id == nil || current?.id == id else { return }
        current = nil
        autoDismissTask?.cancel()
        autoDismissTask = nil
    }
}
