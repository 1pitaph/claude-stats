import AppKit
import Foundation

enum NotchIslandDisplayMode: String, CaseIterable, Sendable, Identifiable {
    case primaryDisplay
    case pointerDisplay
    case allDisplays

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .primaryDisplay: "Primary Display"
        case .pointerDisplay: "Pointer Display"
        case .allDisplays: "All Displays"
        }
    }

    var description: String {
        switch self {
        case .primaryDisplay: "Pin the island to the main screen."
        case .pointerDisplay: "Move the island to the screen under the pointer."
        case .allDisplays: "Show a separate island on every connected display."
        }
    }
}

enum NotchIslandSizePreset: String, CaseIterable, Sendable, Identifiable {
    case compact
    case regular
    case large

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .compact: "Compact"
        case .regular: "Regular"
        case .large: "Large"
        }
    }

    var description: String {
        switch self {
        case .compact: "Small top pill with a focused expanded panel."
        case .regular: "Balanced size for media, stats, and utilities."
        case .large: "More room for lists, shelf items, and lock-screen widgets."
        }
    }
}

enum NotchIslandScreenStyle: String, CaseIterable, Sendable, Identifiable {
    case sameAsNotch
    case floatingIsland

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sameAsNotch: "Same as notch"
        case .floatingIsland: "Floating island"
        }
    }

    var description: String {
        switch self {
        case .sameAsNotch: "Blend into the top screen edge."
        case .floatingIsland: "Float below the top edge as a detached pill."
        }
    }
}

struct NotchIslandScreenDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let localizedName: String
    let hasPhysicalNotch: Bool
}

enum NotchIslandScreenStyleResolver {
    static func effectiveStyle(
        screenID: String,
        hasPhysicalNotch: Bool,
        storedStyles: [String: NotchIslandScreenStyle]
    ) -> NotchIslandScreenStyle {
        if hasPhysicalNotch {
            return .sameAsNotch
        }
        return storedStyles[screenID] ?? .sameAsNotch
    }

    static func effectiveStyles(
        for descriptors: [NotchIslandScreenDescriptor],
        storedStyles: [String: NotchIslandScreenStyle]
    ) -> [String: NotchIslandScreenStyle] {
        descriptors.reduce(into: [:]) { result, descriptor in
            result[descriptor.id] = effectiveStyle(
                screenID: descriptor.id,
                hasPhysicalNotch: descriptor.hasPhysicalNotch,
                storedStyles: storedStyles
            )
        }
    }
}

@MainActor
enum NotchIslandScreenCatalog {
    static let fallbackScreenID = "main"

    static func id(for screen: NSScreen) -> String {
        if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return String(screenNumber.uint32Value)
        }
        return screen.localizedName.isEmpty ? fallbackScreenID : screen.localizedName
    }

    static func shortID(for id: String) -> String {
        String(id.suffix(4))
    }

    static func descriptors() -> [NotchIslandScreenDescriptor] {
        let screens = NSScreen.screens
        let nameCounts = Dictionary(grouping: screens, by: \.localizedName)
            .mapValues(\.count)

        return screens.map { screen in
            let id = id(for: screen)
            let name = screen.localizedName.isEmpty ? "Display" : screen.localizedName
            let displayName = (nameCounts[screen.localizedName] ?? 0) > 1
                ? "\(name) (\(shortID(for: id)))"
                : name
            return NotchIslandScreenDescriptor(
                id: id,
                displayName: displayName,
                localizedName: name,
                hasPhysicalNotch: screen.safeAreaInsets.top > 0
            )
        }
    }

    static func screen(for id: String) -> NSScreen? {
        NSScreen.screens.first { Self.id(for: $0) == id }
    }

    static func mainScreenID() -> String {
        if let main = NSScreen.main ?? NSScreen.screens.first {
            return id(for: main)
        }
        return fallbackScreenID
    }

    static func pointerScreenID() -> String {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return id(for: screen)
        }
        return mainScreenID()
    }

    static func defaultSelectedScreenIDs(for legacyMode: NotchIslandDisplayMode = .primaryDisplay) -> Set<String> {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [fallbackScreenID] }

        switch legacyMode {
        case .primaryDisplay:
            return [mainScreenID()]
        case .pointerDisplay:
            return [pointerScreenID()]
        case .allDisplays:
            return Set(screens.map(id(for:)))
        }
    }

    static func selectedScreens(for ids: Set<String>) -> [NSScreen] {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return [] }
        let selected = screens.filter { ids.contains(id(for: $0)) }
        if !selected.isEmpty {
            return selected
        }
        return [NSScreen.main ?? screens[0]]
    }

    static func primaryRuntimeScreen(from screens: [NSScreen]) -> NSScreen? {
        guard !screens.isEmpty else { return nil }
        if let main = NSScreen.main, screens.contains(main) {
            return main
        }
        let selectedIDs = Set(screens.map(id(for:)))
        return NSScreen.screens.first { selectedIDs.contains(id(for: $0)) } ?? screens[0]
    }
}

enum NotchIslandModule: String, CaseIterable, Sendable, Identifiable {
    case media
    case stats
    case timer
    case clipboard
    case colorPicker
    case calendar
    case shelf
    case privacy
    case recording
    case focus
    case battery
    case bluetooth
    case downloads
    case osd
    case lockScreenWidgets
    case extensionBridge
    case screenAssistant
    case terminal

    static let defaultEnabled: Set<NotchIslandModule> = [
        .media,
        .stats,
        .clipboard,
        .colorPicker,
        .calendar,
        .shelf,
        .privacy,
        .focus,
        .battery,
        .bluetooth,
        .downloads,
        .osd
    ]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: "Media"
        case .stats: "Stats"
        case .timer: "Timer"
        case .clipboard: "Clipboard"
        case .colorPicker: "Color Picker"
        case .calendar: "Calendar"
        case .shelf: "Shelf"
        case .privacy: "Privacy"
        case .recording: "Recording"
        case .focus: "Focus"
        case .battery: "Battery"
        case .bluetooth: "Bluetooth"
        case .downloads: "Downloads"
        case .osd: "OSD"
        case .lockScreenWidgets: "Lock Widgets"
        case .extensionBridge: "Extensions"
        case .screenAssistant: "Screen Assistant"
        case .terminal: "Terminal"
        }
    }

    var symbol: String {
        switch self {
        case .media: AppIcon.NotchIsland.media
        case .stats: AppIcon.NotchIsland.stats
        case .timer: AppIcon.NotchIsland.timer
        case .clipboard: AppIcon.NotchIsland.clipboard
        case .colorPicker: AppIcon.NotchIsland.colorPicker
        case .calendar: AppIcon.NotchIsland.calendar
        case .shelf: AppIcon.NotchIsland.shelf
        case .privacy: AppIcon.NotchIsland.privacy
        case .recording: AppIcon.NotchIsland.recording
        case .focus: AppIcon.NotchIsland.focus
        case .battery: AppIcon.NotchIsland.battery
        case .bluetooth: AppIcon.NotchIsland.bluetooth
        case .downloads: AppIcon.NotchIsland.downloads
        case .osd: AppIcon.Workspace.configs
        case .lockScreenWidgets: AppIcon.NotchIsland.lockScreenWidgets
        case .extensionBridge: AppIcon.NotchIsland.extensionBridge
        case .screenAssistant: AppIcon.NotchIsland.screenAssistant
        case .terminal: AppIcon.Workspace.terminal
        }
    }

    var settingsDescription: String {
        switch self {
        case .media: "Atoll media controls, artwork, and playback live activity."
        case .stats: "CPU, memory, disk, network, battery, GPU, and thermal readouts."
        case .timer: "Inline timer controls and timer live activity."
        case .clipboard: "Clipboard history surface and popover entry point."
        case .colorPicker: "Color picker entry point and picked-colour feedback."
        case .calendar: "Calendar and reminder previews near the notch."
        case .shelf: "File shelf, AirDrop, QuickShare, and LocalSend surfaces."
        case .privacy: "Camera and microphone privacy indicators."
        case .recording: "Screen-recording live activity and indicator."
        case .focus: "Do Not Disturb and Focus live activity."
        case .battery: "Battery, charging, and power-source live activity."
        case .bluetooth: "Bluetooth audio device status and connection HUD."
        case .downloads: "Browser download live activity and progress display."
        case .osd: "Volume, brightness, keyboard backlight, and custom HUD overlays."
        case .lockScreenWidgets: "Atoll-style lock-screen panels and widgets."
        case .extensionBridge: "Atoll extension RPC/XPC event bridge."
        case .screenAssistant: "Screen assistant panels, screenshot snipping, and model chooser."
        case .terminal: "Terminal tab surface backed by the existing embedded terminal stack."
        }
    }

    var isHeavyOrExperimental: Bool {
        switch self {
        case .media, .stats, .timer, .clipboard, .colorPicker, .calendar, .privacy, .battery:
            false
        case .shelf, .recording, .focus, .bluetooth, .downloads, .osd, .lockScreenWidgets, .extensionBridge, .screenAssistant, .terminal:
            true
        }
    }

    var atollSourceHint: String {
        switch self {
        case .media: "ThirdParty/Atoll/DynamicIsland/MediaControllers"
        case .stats: "ThirdParty/Atoll/DynamicIsland/components/Stats"
        case .timer: "ThirdParty/Atoll/DynamicIsland/components/Timer"
        case .clipboard: "ThirdParty/Atoll/DynamicIsland/components/Clipboard"
        case .colorPicker: "ThirdParty/Atoll/DynamicIsland/components/ColorPicker"
        case .calendar: "ThirdParty/Atoll/DynamicIsland/components/Calendar"
        case .shelf: "ThirdParty/Atoll/DynamicIsland/components/Shelf"
        case .privacy: "ThirdParty/Atoll/DynamicIsland/components/Privacy"
        case .recording: "ThirdParty/Atoll/DynamicIsland/components/Recording"
        case .focus: "ThirdParty/Atoll/DynamicIsland/components/Focus"
        case .battery: "ThirdParty/Atoll/DynamicIsland/components/Live activities/DynamicIslandBattery.swift"
        case .bluetooth: "ThirdParty/Atoll/DynamicIsland/managers/BluetoothAudioManager.swift"
        case .downloads: "ThirdParty/Atoll/DynamicIsland/components/Downloads"
        case .osd: "ThirdParty/Atoll/DynamicIsland/components/OSD"
        case .lockScreenWidgets: "ThirdParty/Atoll/DynamicIsland/components/LockScreen"
        case .extensionBridge: "ThirdParty/Atoll/DynamicIsland/services/Extensions"
        case .screenAssistant: "ThirdParty/Atoll/DynamicIsland/components/ScreenAssistant"
        case .terminal: "ThirdParty/Atoll/DynamicIsland/managers/TerminalManager.swift"
        }
    }
}

enum NotchIslandPermissionState: Sendable, Equatable {
    case available
    case needsPermission(String)
    case disabledByDefault
    case sourceLinked

    var displayName: String {
        switch self {
        case .available: "Available"
        case .needsPermission(let permission): "Needs \(permission)"
        case .disabledByDefault: "Off by default"
        case .sourceLinked: "Source linked"
        }
    }
}
