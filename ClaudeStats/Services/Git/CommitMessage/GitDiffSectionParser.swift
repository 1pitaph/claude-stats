import Foundation

enum GitDiffSectionParser {
    static func splitDiffSections(_ diffText: String) -> [String] {
        var sections: [String] = []
        var current: [String] = []
        for line in diffText.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git "), !current.isEmpty {
                sections.append(current.joined(separator: "\n"))
                current = []
            }
            current.append(line)
        }
        if !current.isEmpty {
            sections.append(current.joined(separator: "\n"))
        }
        return sections.filter { $0.hasPrefix("diff --git ") }
    }

    static func parseDiffGitPaths(_ line: String) -> (old: String, new: String) {
        let parts = line.split(separator: " ")
        guard parts.count >= 4 else { return ("", "") }
        return (stripGitPrefix(String(parts[2])), stripGitPrefix(String(parts[3])))
    }

    static func path(for section: String) -> String {
        guard let first = section.components(separatedBy: "\n").first else { return "" }
        let paths = parseDiffGitPaths(first)
        for line in section.components(separatedBy: "\n") where line.hasPrefix("rename to ") {
            return String(line.dropFirst("rename to ".count))
        }
        return paths.new
    }

    private static func stripGitPrefix(_ path: String) -> String {
        var output = path
        if output.hasPrefix("\""), output.hasSuffix("\""), output.count >= 2 {
            output = String(output.dropFirst().dropLast())
        }
        if output.hasPrefix("a/") || output.hasPrefix("b/") {
            output = String(output.dropFirst(2))
        }
        return output
    }
}
