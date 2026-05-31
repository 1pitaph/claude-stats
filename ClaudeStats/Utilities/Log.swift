import Foundation
import os

/// Subsystem-scoped loggers. Use these instead of `print`.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.claudestats.ClaudeStats"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let scanner = Logger(subsystem: subsystem, category: "scanner")
    static let parser = Logger(subsystem: subsystem, category: "parser")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let git = Logger(subsystem: subsystem, category: "git")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let notch = Logger(subsystem: subsystem, category: "notch")
    static let updater = Logger(subsystem: subsystem, category: "updater")
    static let analysis = Logger(subsystem: subsystem, category: "analysis")
    static let overlay = Logger(subsystem: subsystem, category: "overlay")
}
