import Foundation
import Observation

@MainActor
@Observable
final class CursorCommandOverlayState {
    var isExpanded = false
    var isLoading = false
    var summaries: [SessionCommandSummary] = []
    var copiedCommand: String?
    var lastError: String?
}
