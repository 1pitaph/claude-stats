import SwiftUI

public struct WarpHostView: View {
    @ObservedObject private var store: WarpSessionStore

    public init(store: WarpSessionStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: store.availability.isReady ? "checkmark.circle" : "wrench.and.screwdriver")
                    .font(.system(size: 14, weight: .semibold))
                Text(store.availability.isReady ? "Warp bridge ready" : "Warp bridge pending")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
            }

            Text(store.availability.message)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.72))
        .onAppear {
            store.ensureDefaultSession()
        }
    }
}
