import SwiftUI

struct MemoryReviewView: View {
    @Bindable var store: MemoryStore

    var body: some View {
        AppScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                summary
                reviewSection(title: "Proposed", symbol: AppIcon.AIConfig.plan, items: store.review.proposals) { memory in
                    proposalActions(memory)
                }
                reviewSection(title: "Conflicts", symbol: AppIcon.Status.warning, items: store.review.conflicts) { memory in
                    conflictActions(memory)
                }
                reviewSection(title: "Low Confidence", symbol: AppIcon.Metric.gauge, items: store.review.lowConfidence) { memory in
                    lowConfidenceActions(memory)
                }
                graphFactSection
            }
            .padding(18)
        }
    }

    private var summary: some View {
        HStack(spacing: 10) {
            WorkspaceMiniStat(value: "\(store.review.proposals.count)", label: "proposed")
            WorkspaceMiniStat(value: "\(store.review.conflicts.count)", label: "conflicts")
            WorkspaceMiniStat(value: "\(store.review.lowConfidence.count)", label: "low confidence")
            WorkspaceMiniStat(value: "\(store.review.graphFacts.count)", label: "graph facts")
            Spacer(minLength: 8)
            Button {
                Task { await store.loadCodeProposals() }
            } label: {
                Label("Refresh", systemImage: AppIcon.Action.refresh)
            }
            .controlSize(.small)
            .disabled(store.review.isLoading)
        }
        .padding(12)
        .appSurface(.compactCard(radius: 8, fillOpacity: 0.54, cornerStyle: .circular, maxWidth: nil), padding: nil)
    }

    private func reviewSection<Actions: View>(
        title: String,
        symbol: String,
        items: [CodeMemoryMemory],
        @ViewBuilder actions: @escaping (CodeMemoryMemory) -> Actions
    ) -> some View {
        MemorySection(title: title, count: items.count, symbol: symbol) {
            if items.isEmpty {
                MemoryMutedLine(text: "None")
                    .padding(.vertical, 8)
            } else {
                ForEach(items) { memory in
                    MemoryFactRow(memory: memory) {
                        actions(memory)
                    }
                }
            }
        }
    }

    private var graphFactSection: some View {
        MemorySection(title: "Promoted Graph Facts", count: store.review.graphFacts.count, symbol: AppIcon.Network.webSocket) {
            if store.review.graphFacts.isEmpty {
                MemoryMutedLine(text: "None")
                    .padding(.vertical, 8)
            } else {
                ForEach(store.review.graphFacts) { fact in
                    MemoryGraphFactRow(fact: fact) {
                        Task { await store.promoteGraphFact(fact) }
                    }
                }
            }
        }
    }

    private func proposalActions(_ memory: CodeMemoryMemory) -> some View {
        HStack(spacing: 6) {
            Button {
                Task { await store.acceptProposal(memory) }
            } label: {
                Label("Accept", systemImage: AppIcon.Action.confirm)
            }
            .controlSize(.small)
            .disabled(store.review.isLoading)

            Button {
                Task { await store.rejectProposal(memory) }
            } label: {
                Label("Reject", systemImage: AppIcon.Action.close)
            }
            .controlSize(.small)
            .disabled(store.review.isLoading)
        }
    }

    private func conflictActions(_ memory: CodeMemoryMemory) -> some View {
        HStack(spacing: 6) {
            Button {
                Task { await store.acceptProposal(memory) }
            } label: {
                Label("Accept", systemImage: AppIcon.Action.confirm)
            }
            .controlSize(.small)
            .disabled(store.review.isLoading)

            Button {
                Task { await store.deprecateMemory(memory) }
            } label: {
                Label("Deprecate", systemImage: AppIcon.Resource.archive)
            }
            .controlSize(.small)
            .disabled(store.review.isLoading)
        }
    }

    private func lowConfidenceActions(_ memory: CodeMemoryMemory) -> some View {
        HStack(spacing: 6) {
            Button {
                Task { await store.acceptProposal(memory) }
            } label: {
                Label("Keep", systemImage: AppIcon.Status.verified)
            }
            .controlSize(.small)
            .disabled(store.review.isLoading)

            Button {
                Task { await store.deprecateMemory(memory) }
            } label: {
                Label("Deprecate", systemImage: AppIcon.Resource.archive)
            }
            .controlSize(.small)
            .disabled(store.review.isLoading)
        }
    }
}
