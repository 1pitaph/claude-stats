import Foundation

extension String {
    var gitCommitMessageNilIfEmpty: String? {
        isEmpty ? nil : self
    }

    func gitCommitMessageTruncated(to maxLength: Int) -> String {
        guard count > maxLength else { return self }
        return String(prefix(max(0, maxLength - 12))) + "\n[truncated]"
    }
}
