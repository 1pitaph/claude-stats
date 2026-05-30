import Foundation

public enum WarpRuntimeAvailability: Equatable, Sendable {
    case sourceCheckoutMissing(URL)
    case bridgeUnavailable
    case ready(WarpRuntimeManifest)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .sourceCheckoutMissing(let url):
            "Warp source checkout was not found at \(url.path)."
        case .bridgeUnavailable:
            "Warp source is present, but the in-process app bridge has not been built yet."
        case .ready(let manifest):
            "Warp embed bridge is ready at \(manifest.sourceRoot.path)."
        }
    }
}

public struct WarpRuntimeManifest: Equatable, Sendable {
    public let sourceRoot: URL
    public let commit: String?

    public init(sourceRoot: URL, commit: String? = nil) {
        self.sourceRoot = sourceRoot
        self.commit = commit
    }
}

public struct WarpRuntime: Sendable {
    public let sourceRoot: URL
    public let bridgeLibraryURL: URL?

    public init(sourceRoot: URL = Self.defaultSourceRoot(), bridgeLibraryURL: URL? = nil) {
        self.sourceRoot = sourceRoot
        self.bridgeLibraryURL = bridgeLibraryURL
    }

    public func availability(fileManager: FileManager = .default) -> WarpRuntimeAvailability {
        guard fileManager.fileExists(atPath: sourceRoot.appendingPathComponent("Cargo.toml").path) else {
            return .sourceCheckoutMissing(sourceRoot)
        }

        guard let bridgeLibraryURL,
              fileManager.fileExists(atPath: bridgeLibraryURL.path) else {
            return .bridgeUnavailable
        }

        return .ready(WarpRuntimeManifest(sourceRoot: sourceRoot))
    }

    public static func defaultSourceRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["WARP_EMBED_SOURCE_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("ThirdParty", isDirectory: true)
            .appendingPathComponent("Warp", isDirectory: true)
    }
}
