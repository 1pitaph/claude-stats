import Foundation

/// Semantic names for app-owned SF Symbols.
///
/// Keep external provider logos, remote icon names, and data-driven category
/// mappings close to their domain models instead of adding them here.
enum AppIcon {
    enum Action {
        static let add = "plus"
        static let addCircle = "plus.circle"
        static let cancel = "xmark.circle"
        static let clear = "xmark.circle.fill"
        static let close = "xmark"
        static let compose = "square.and.pencil"
        static let confirm = "checkmark"
        static let copy = "doc.on.doc"
        static let delete = "trash"
        static let download = "arrow.down.circle"
        static let downloadDocument = "arrow.down.doc"
        static let downloadFilled = "arrow.down.circle.fill"
        static let downloadToLine = "arrow.down.to.line"
        static let downloadTray = "tray.and.arrow.down"
        static let duplicateNew = "plus.square.on.square"
        static let edit = "pencil"
        static let exportFile = "square.and.arrow.up"
        static let hand = "hand.raised"
        static let importFile = "square.and.arrow.down"
        static let installApp = "arrow.down.app.fill"
        static let more = "ellipsis.circle"
        static let openExternal = "arrow.up.right.square"
        static let pause = "pause.circle"
        static let pinFilled = "pin.fill"
        static let play = "play"
        static let quit = "power"
        static let refresh = "arrow.clockwise"
        static let refreshCircle = "arrow.clockwise.circle"
        static let removeCircle = "minus.circle"
        static let reply = "arrowshape.turn.up.left"
        static let reset = "arrow.counterclockwise"
        static let revealInFinder = "finder"
        static let search = "magnifyingglass"
        static let send = "paperplane"
        static let sendFilled = "paperplane.fill"
        static let start = "play.fill"
        static let stop = "stop.fill"
        static let sync = "arrow.triangle.2.circlepath"
        static let undo = "arrow.uturn.backward"
        static let undoCircle = "arrow.uturn.backward.circle"
        static let uploadTray = "tray.and.arrow.up"
        static let viewfinder = "viewfinder"
        static let zoomIn = "plus.magnifyingglass"
        static let zoomOut = "minus.magnifyingglass"
    }

    enum Navigation {
        static let arrowDown = "arrow.down"
        static let arrowForward = "arrow.forward"
        static let arrowUp = "arrow.up"
        static let back = "chevron.left"
        static let disclosure = "chevron.right"
        static let down = "chevron.down"
        static let forward = "arrow.right"
        static let forwardCircle = "arrow.right.circle"
        static let move = "arrow.up.and.down.and.arrow.left.and.right"
        static let openForward = "arrow.up.right"
        static let sidebarLeft = "sidebar.left"
        static let sidebarRight = "sidebar.right"
        static let turnUpRight = "arrow.turn.up.right"
        static let up = "chevron.up"
        static let upCircle = "arrow.up.circle"
        static let verticalResize = "arrow.up.and.down"
    }

    enum Status {
        static let badge = "seal"
        static let badgeFilled = "seal.fill"
        static let checkedTask = "checkmark.square"
        static let clock = "clock"
        static let clockFilled = "clock.fill"
        static let clockWarning = "clock.badge.exclamationmark"
        static let disabled = "nosign"
        static let error = "exclamationmark.circle"
        static let errorFilled = "exclamationmark.circle.fill"
        static let failure = "xmark.octagon"
        static let failureFilled = "xmark.octagon.fill"
        static let failureCircle = failureFilled
        static let helpBubble = "questionmark.bubble"
        static let history = "clock.arrow.circlepath"
        static let info = "info.circle"
        static let infoFilled = "info.circle.fill"
        static let lockOpen = "lock.open"
        static let lockShield = "lock.shield"
        static let maintenance = "wrench.and.screwdriver.fill"
        static let networkWarning = "wifi.exclamationmark"
        static let offline = "wifi.slash"
        static let secure = "checkmark.shield"
        static let shieldFilled = "shield.fill"
        static let success = "checkmark.circle"
        static let successFilled = "checkmark.circle.fill"
        static let uncheckedTask = "square"
        static let unknown = "questionmark.circle.fill"
        static let verified = "checkmark.seal"
        static let verifiedFilled = "checkmark.seal.fill"
        static let visible = "eye"
        static let warning = "exclamationmark.triangle"
        static let warningFilled = "exclamationmark.triangle.fill"
    }

    enum Workspace {
        static let activity = "waveform"
        static let configs = "slider.horizontal.3"
        static let dailyReport = "calendar"
        static let dashboard = "square.grid.2x2"
        static let gantt = "timeline.selection"
        static let git = "arrow.triangle.branch"
        static let leaderboards = "trophy"
        static let linuxDo = "globe.asia.australia"
        static let memory = "brain"
        static let network = "network"
        static let ops = "wrench.and.screwdriver"
        static let settings = "gearshape"
        static let system = "cpu"
        static let terminal = "terminal.fill"
        static let usage = "chart.line.uptrend.xyaxis"
        static let warp = "terminal"
    }

    enum Resource {
        static let archive = "archivebox"
        static let configuredFolder = "folder.badge.gearshape"
        static let conversation = "bubble.left.and.bubble.right"
        static let dictionary = "text.book.closed"
        static let document = "doc"
        static let documentPlainText = "doc.plaintext"
        static let documentText = "doc.text"
        static let externalDrive = "externaldrive"
        static let externalDriveReady = "externaldrive.badge.checkmark"
        static let folder = "folder"
        static let key = "key"
        static let keyFilled = "key.fill"
        static let link = "link"
        static let package = "shippingbox"
        static let plugin = "puzzlepiece.extension"
        static let quote = "quote.bubble"
        static let stack = "rectangle.stack"
        static let tag = "tag"
        static let clipboardList = "list.bullet.clipboard"
        static let textBubble = "text.bubble"
        static let textBubbleFilled = "text.bubble.fill"
        static let textSearch = "text.magnifyingglass"
        static let transcriptSearch = "doc.text.magnifyingglass"
        static let tray = "tray"
        static let trayFilled = "tray.fill"
        static let unknownFolder = "folder.badge.questionmark"
    }

    enum Feature {
        static let accessibility = "accessibility"
        static let ai = "sparkles"
        static let important = "star.circle.fill"
        static let magic = "wand.and.stars"
        static let tip = "lightbulb.fill"
    }

    enum Filter {
        static let filter = "line.3.horizontal.decrease"
        static let filterCircle = "line.3.horizontal.decrease.circle"
    }

    enum Runtime {
        static let terminal = Workspace.terminal
        static let terminalFilled = terminal
    }

    enum Settings {
        static let about = Status.info
        static let features = "switch.2"
        static let general = "gearshape.2"
        static let iCloudSync = "icloud"
        static let systemSettings = "gear"
        static let llm = "brain.head.profile"
        static let menuBar = "menubar.rectangle"
        static let notchIsland = "capsule.portrait.tophalf.filled"
        static let platforms = "square.stack.3d.up"
        static let tracking = "waveform.path.ecg"
    }

    enum AIConfig {
        static let diagnostics = Status.warning
        static let document = Resource.document
        static let instruction = Resource.documentText
        static let plan = "checklist"
        static let pluginManifest = Resource.plugin
        static let provider = "server.rack"
        static let scope = "scope"
        static let skillFiles = "sparkle.magnifyingglass"
    }

    enum Skill {
        static let curated = "star"
        static let discover = Action.search
        static let file = Resource.plugin
        static let installed = Resource.externalDriveReady
        static let market = "bag"
    }

    enum Network {
        static let automate = "slider.horizontal.below.rectangle"
        static let certificates = Status.secure
        static let direct = "arrow.forward.circle"
        static let domain = "globe"
        static let proxy = "arrow.triangle.swap"
        static let radio = "antenna.radiowaves.left.and.right"
        static let replay = "arrow.counterclockwise.circle"
        static let rules = Resource.clipboardList
        static let secureNetwork = "network.badge.shield.half.filled"
        static let traffic = "list.bullet.rectangle.portrait"
        static let webSocket = "point.3.connected.trianglepath.dotted"
    }

    enum Ops {
        static let brew = "mug"
        static let cleanup = "eraser"
        static let diagnostics = "stethoscope"
        static let docker = "externaldrive.connected.to.line.below"
        static let environment = "ellipsis.curlybraces"
        static let homebrew = "mug.fill"
        static let npm = "curlybraces.square"
        static let pnpm = "square.stack.3d.up.fill"
        static let ports = "cable.connector"
        static let processes = "list.bullet.rectangle"
        static let swiftPackage = "swift"
        static let xcode = "hammer"
        static let yarn = "tray.full"
    }

    enum Terminal {
        static let bottomChrome = "rectangle.bottomthird.inset.filled"
        static let solidBackground = "rectangle.fill"
        static let topChrome = "rectangle.topthird.inset.filled"
        static let fluidGradient = "swirl.circle.righthalf.filled"
    }

    enum SystemMonitor {
        static let battery = "battery.75percent"
        static let cpu = "cpu.fill"
        static let disk = "internaldrive"
        static let gpu = "display"
        static let memory = "memorychip"
        static let network = "wifi.router"
        static let power = "bolt.horizontal"
        static let thermal = "thermometer.medium"
    }

    enum LinuxDo {
        static let hot = "flame"
        static let like = "heart"
        static let likeFilled = "heart.fill"
    }

    enum NotchIsland {
        static let appearance = "paintpalette"
        static let battery = SystemMonitor.battery
        static let bluetooth = "headphones"
        static let calendar = "calendar"
        static let clipboard = "doc.on.clipboard"
        static let colorPicker = "eyedropper"
        static let downloads = Action.download
        static let extensionBridge = Resource.plugin
        static let focus = "moon"
        static let island = Settings.notchIsland
        static let lockScreenWidgets = "lock.display"
        static let media = "music.note"
        static let privacy = "web.camera"
        static let recording = "record.circle"
        static let screenAssistant = Action.viewfinder
        static let shelf = Action.downloadTray
        static let stats = Metric.gauge
        static let timer = "timer"
        static let previewHome = "house.fill"
        static let previewUsage = "chart.xyaxis.line"
    }

    enum Leaderboard {
        static let activityMinutes = "figure.walk.circle"
        static let allTime = "infinity"
        static let crown = "crown.fill"
        static let day = "sun.max"
        static let month = "calendar.badge.clock"
        static let tokensWithCache = "bolt.circle"
        static let tokensWithoutCacheRead = "bolt.slash.circle"
        static let trophyFilled = "trophy.fill"
        static let week = "calendar.day.timeline.left"
        static let year = "calendar.circle"
    }

    enum Code {
        static let braces = "curlybraces"
    }

    enum Git {
        static let commitCheck = "text.badge.checkmark"
        static let code = "chevron.left.forwardslash.chevron.right"
    }

    enum Session {
        static let atlas = "point.3.filled.connected.trianglepath.dotted"
        static let bubbles = "circle.grid.3x3.circle"
        static let cloud = "textformat"
        static let command = "command"
        static let framework = "books.vertical"
        static let function = "function"
        static let language = "character.book.closed"
        static let roleAssistant = Feature.magic
        static let roleSystem = "gearshape.fill"
        static let roleTool = "wrench.adjustable"
        static let roleUser = "person"
        static let typeName = Code.braces
    }

    enum Pointer {
        static let click = "cursorarrow.click"
        static let motion = "cursorarrow.motionlines"
    }

    enum People {
        static let group = "person.2"
        static let groupFilled = "person.2.fill"
        static let person = "person"
        static let profile = "person.crop.circle"
        static let profileFilled = "person.crop.circle.fill"
        static let profileStack = "person.crop.rectangle.stack"
        static let smile = "face.smiling"
        static let teamFilled = "person.3.fill"
    }

    enum Layout {
        static let compressVertical = "rectangle.compress.vertical"
        static let grid3 = "square.grid.3x3"
        static let groupedRectangles = "rectangle.3.group"
        static let overlap = "rectangle.on.rectangle"
        static let rectangle = "rectangle"
        static let rectangleGrid = "rectangle.grid.1x2"
        static let route = "point.topleft.down.curvedto.point.bottomright.up"
        static let sideBySide = "rectangle.split.2x1"
        static let stacked = "rectangle.split.1x2"
    }

    enum Text {
        static let cursor = "text.cursor"
        static let viewfinder = "text.viewfinder"
    }

    enum Window {
        static let main = "macwindow"
    }

    enum Device {
        static let keyboard = "keyboard"
        static let laptop = "laptopcomputer"
    }

    enum Location {
        static let active = "location.fill"
        static let inactive = "location.slash"
    }

    enum Metric {
        static let boltFilled = "bolt.fill"
        static let chart = "chart.bar"
        static let cost = "dollarsign.circle"
        static let gauge = "gauge.with.dots.needle.33percent"
        static let number = "number"
    }

    enum LocalAI {
        static let embedding = "circle.hexagongrid"
        static let experimentalEmbedding = "flask"
        static let model = "cube.box"
    }

    enum App {
        static let generic = "app"
        static let safari = "safari"
    }
}
