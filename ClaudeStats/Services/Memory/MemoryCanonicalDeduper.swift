import Foundation

enum MemoryCanonicalDeduper {
    static func deduplicate(_ memories: [CodeMemoryMemory]) -> [CodeMemoryMemory] {
        var orderedKeys: [String] = []
        var memoriesByKey: [String: CodeMemoryMemory] = [:]

        for memory in memories {
            let key = canonicalKey(for: memory)
            if let existing = memoriesByKey[key] {
                memoriesByKey[key] = merged(existing, memory)
            } else {
                orderedKeys.append(key)
                memoriesByKey[key] = memory
            }
        }

        return orderedKeys.compactMap { memoriesByKey[$0] }
    }

    private static func canonicalKey(for memory: CodeMemoryMemory) -> String {
        [
            normalizedToken(memory.projectID),
            normalizedToken(memory.type),
            normalizedClaim(for: memory),
        ].joined(separator: "|")
    }

    private static func normalizedClaim(for memory: CodeMemoryMemory) -> String {
        let claim = memory.normalizedClaim.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = claim.isEmpty ? memory.body : claim
        return normalizedToken(text)
    }

    private static func normalizedToken(_ value: String) -> String {
        value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func merged(_ lhs: CodeMemoryMemory, _ rhs: CodeMemoryMemory) -> CodeMemoryMemory {
        let base = isBetter(rhs, than: lhs) ? rhs : lhs
        let other = base.id == lhs.id ? rhs : lhs
        var merged = base
        merged.sourceRefs = mergedSourceRefs(base.sourceRefs, other.sourceRefs)
        merged.scopes = mergedScopes(base.scopes, other.scopes)
        merged.metadata = mergedMetadata(base.metadata, other.metadata, aliasIDs: [lhs.id, rhs.id], canonicalID: base.id)
        return merged
    }

    private static func isBetter(_ candidate: CodeMemoryMemory, than current: CodeMemoryMemory) -> Bool {
        if candidate.importance != current.importance {
            return candidate.importance > current.importance
        }
        if candidate.confidence != current.confidence {
            return candidate.confidence > current.confidence
        }
        return candidate.updatedAt > current.updatedAt
    }

    private static func mergedSourceRefs(
        _ lhs: [CodeMemorySourceRef],
        _ rhs: [CodeMemorySourceRef]
    ) -> [CodeMemorySourceRef] {
        var seen = Set<String>()
        var merged: [CodeMemorySourceRef] = []
        for ref in lhs + rhs where seen.insert(ref.id).inserted {
            merged.append(ref)
        }
        return merged
    }

    private static func mergedScopes(_ lhs: [CodeMemoryScope], _ rhs: [CodeMemoryScope]) -> [CodeMemoryScope] {
        var seen = Set<String>()
        var merged: [CodeMemoryScope] = []
        for scope in lhs + rhs where seen.insert(scope.id).inserted {
            merged.append(scope)
        }
        return merged
    }

    private static func mergedMetadata(
        _ lhs: [String: String]?,
        _ rhs: [String: String]?,
        aliasIDs: [String],
        canonicalID: String
    ) -> [String: String] {
        var metadata = rhs ?? [:]
        metadata.merge(lhs ?? [:]) { _, new in new }
        var aliases = Set(
            aliasIDs
                .filter { !$0.isEmpty && $0 != canonicalID }
        )
        for existingAliases in [lhs?["canonical_alias_ids"], rhs?["canonical_alias_ids"]] {
            guard let existingAliases else { continue }
            aliases.formUnion(
                existingAliases
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0 != canonicalID }
            )
        }
        let sortedAliases = aliases
            .filter { !$0.isEmpty && $0 != canonicalID }
            .sorted()
        if !sortedAliases.isEmpty {
            metadata["canonical_alias_ids"] = sortedAliases.joined(separator: ",")
        }
        return metadata
    }
}
