import AppKit
import SwiftUI

struct GitCommitMessageCard: View {
    @Environment(AppEnvironment.self) private var env

    let repo: GitRepo
    let target: GitCommitMessageTarget

    @State private var vm = GitCommitMessageViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .padding(12)
        .appSurface(.compactCard(radius: 10))
        .task(id: cacheLoadID) {
            await loadCached()
        }
        .onChange(of: target.identity) { _, _ in
            vm.reset()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("COMMIT MESSAGE")
                .font(.sora(10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color.stxMuted)
            if case .loaded(let result) = vm.state {
                GitCommitMessageCopyButton(
                    text: result.copyText,
                    label: "Copy commit message"
                )
            }
            Spacer(minLength: 0)
            switch vm.state {
            case .loading:
                ProgressView()
                    .controlSize(.mini)
            case .loaded(let result):
                StatusSeverityBadge(
                    label: result.isCached ? "cached" : "generated",
                    indicatorTint: result.isCached ? Color.stxMuted : Color.stxAccent
                )
            default:
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle:
            VStack(alignment: .leading, spacing: 9) {
                Text("Generate a cached commit message for this diff.")
                    .font(.sora(10))
                    .foregroundStyle(Color.stxMuted)
                controls(result: nil)
            }
        case .loading:
            Text("Generating commit message with \(env.appLLMSettings.mode.title)...")
                .font(.sora(10))
                .foregroundStyle(Color.stxMuted)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 9) {
                Text(message)
                    .font(.sora(10))
                    .foregroundStyle(Color.red)
                    .fixedSize(horizontal: false, vertical: true)
                controls(result: nil)
            }
        case .loaded(let result):
            VStack(alignment: .leading, spacing: 10) {
                Text(result.commitMessage)
                    .font(.sora(10).monospaced())
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                controls(result: result)
            }
        }
    }

    private func controls(result: GitCommitMessageResult?) -> some View {
        HStack(spacing: 7) {
            Button {
                generate(forceRefresh: false)
            } label: {
                Label(result == nil ? "Generate" : "Regenerate", systemImage: AppIcon.Feature.ai)
            }
            .controlSize(.small)
            .disabled(isLoading)

            if result != nil {
                Button {
                    generate(forceRefresh: true)
                } label: {
                    Label("Refresh", systemImage: AppIcon.Action.refresh)
                }
                .controlSize(.small)
                .disabled(isLoading)
            }

        }
    }

    private var isLoading: Bool {
        if case .loading = vm.state { return true }
        return false
    }

    private func generate(forceRefresh: Bool) {
        Task {
            await env.appLLMSettings.loadIfNeeded()
            do {
                let endpoint = try env.generationEndpoint()
                await vm.generate(
                    repo: repo,
                    target: target,
                    endpoint: endpoint,
                    language: outputLanguage,
                    algorithmPreference: env.appLLMSettings.gitCommitMessageAlgorithmPreference,
                    forceRefresh: forceRefresh
                )
            } catch {
                vm.fail(error.localizedDescription)
            }
        }
    }

    private func loadCached() async {
        await env.appLLMSettings.loadIfNeeded()
        do {
            let endpoint = try env.generationEndpoint()
            await vm.loadCached(
                repo: repo,
                target: target,
                endpoint: endpoint,
                language: outputLanguage,
                algorithmPreference: env.appLLMSettings.gitCommitMessageAlgorithmPreference
            )
        } catch {
            if case .loaded = vm.state {
                vm.reset()
            }
        }
    }

    private var cacheLoadID: String {
        [
            repo.cacheKey,
            target.kind,
            target.identity,
            env.appLLMSettings.mode.rawValue,
            env.appLLMSettings.gitCommitMessageAlgorithmPreference.rawValue,
            env.preferences.appLanguagePreference.rawValue,
        ].joined(separator: "|")
    }

    private var outputLanguage: String {
        switch env.preferences.appLanguagePreference {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "Simplified Chinese"
        case .system:
            let identifier = Locale.autoupdatingCurrent.identifier.lowercased()
            return identifier.hasPrefix("zh") ? "Simplified Chinese" : "English"
        }
    }

}

private struct GitCommitMessageCopyButton: View {
    let text: String
    let label: String

    var body: some View {
        Button {
            GitCommitMessageClipboard.copy(text)
        } label: {
            Image(systemName: AppIcon.Action.copy)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .foregroundStyle(text.isEmpty ? Color.stxMuted.opacity(0.45) : Color.stxMuted)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.stxStroke.opacity(0.55), lineWidth: 1)
        )
        .help(label)
        .accessibilityLabel(label)
    }
}

private enum GitCommitMessageClipboard {
    static func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
