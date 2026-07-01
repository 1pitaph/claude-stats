import SwiftUI

struct WorkspaceMiniStat: View {
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 3) {
            Text(value)
                .font(.sora(9, weight: .semibold))
                .monospacedDigit()
            Text(label)
                .font(.sora(9))
                .foregroundStyle(Color.stxMuted)
        }
    }
}
