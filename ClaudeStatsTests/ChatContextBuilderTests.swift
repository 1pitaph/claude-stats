import Foundation
import Testing
@testable import ClaudeStats

@Suite("Chat context builder")
struct ChatContextBuilderTests {
    @Test("Project prompt includes git metadata but not source contents")
    func promptUsesReadOnlyMetadata() async throws {
        let root = try TempDir.make()
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = GitCommandRunner()
        try #require(runner.isAvailable)

        #expect(runner.run(["-C", root.path, "init"]).succeeded)
        #expect(runner.run(["-C", root.path, "config", "user.email", "test@example.com"]).succeeded)
        #expect(runner.run(["-C", root.path, "config", "user.name", "Test User"]).succeeded)

        let sourceURL = root.appendingPathComponent("secret.swift")
        try "let secret = \"SECRET_SOURCE_BODY\"\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        #expect(runner.run(["-C", root.path, "add", "secret.swift"]).succeeded)
        #expect(runner.run(["-C", root.path, "commit", "-m", "Initial commit"]).succeeded)
        try "let secret = \"SECRET_SOURCE_BODY_CHANGED\"\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let builder = ChatContextBuilder()
        let snapshot = try #require(await builder.snapshot(for: root.path))
        let prompt = ChatContextBuilder.systemPrompt(context: snapshot)

        #expect(URL(fileURLWithPath: snapshot.repoRootPath).standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(snapshot.isDirty)
        #expect(snapshot.changedPaths.contains("secret.swift"))
        #expect(prompt.contains("secret.swift"))
        #expect(!prompt.contains("SECRET_SOURCE_BODY"))
        #expect(!prompt.contains("SECRET_SOURCE_BODY_CHANGED"))
    }
}
