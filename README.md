<p align="center">
  <img src="docs/assets/claude-stats-icon.png" alt="Claude Stats app icon" width="128" height="128">
</p>

<h1 align="center">Claude Stats</h1>

<p align="center">
  Native macOS menu-bar stats, dashboards, iOS companion sync, Notch Island, terminal, and network debugging for AI coding work.
</p>

<p align="center">
  <a href="#features">Features</a> ·
  <a href="#screens">Screens</a> ·
  <a href="#install">Install</a> ·
  <a href="#ios-companion">iOS Companion</a> ·
  <a href="#privacy--data">Privacy & Data</a> ·
  <a href="#build-from-source">Build From Source</a> ·
  <a href="#open-source--third-party-modules">Open Source</a> ·
  <a href="#contributing">Contributing</a> ·
  <a href="README.zh-Hans.md">简体中文</a>
</p>

Claude Stats is an open-source native macOS app for people who work in AI coding tools all day. It runs from the menu bar, reads local usage and activity data, and turns it into quick answers about sessions, tokens, cost, limits, repository activity, local system state, provider status, and debugging context.

The app began as a focused macOS take on the open-source [Claude Statistics](https://github.com/sj719045032/claude-statistics) project. It now includes a multi-provider foundation, a dashboard workspace, CloudKit sync for an iOS companion, optional public leaderboards, a Warp-powered terminal surface, an Atoll-backed Notch Island, and a Rockxy-backed network debugger while keeping the main product name **Claude Stats**.

Claude Stats ships in two macOS variants: the full app and **Claude Stats Lite**. Lite keeps the core menu-bar stats, Git views, daily reports, Gantt, leaderboards, and iCloud snapshot sync while omitting heavier integrations such as Dictionary, Linux.do, Warp, Config, Ops, Network, Local AI, Memory, and Notch Island. The two apps use separate bundle identifiers and Sparkle update feeds, so they can be installed side by side.

## Features

- Native menu-bar usage stats for AI coding sessions, tokens, estimated cost, cache reads, recent activity, provider switching, refresh, share export, updates, settings, and quick quit.
- Provider support for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and OpenAI Codex session logs; Gemini, Kimi, and MiniMax are recognized in the UI while their on-disk session parsers are still future work.
- Dashboard and Usage views with summary cards, model breakdowns, token composition, cache hit rate, cost modes, daily navigation, charts, Claude/OpenAI status cards, GitHub heatmaps, and AI/GitHub overlap.
- Usage-limit views and forecasts for supported providers, including Claude Desktop bridge flows and OpenAI/Codex status data.
- Sessions, transcript analysis, and technical-term dictionary tools for understanding local AI coding conversations.
- Daily Report and Gantt workspaces that summarize AI-active projects by day and visualize synced work blocks, providers, token intensity, focus overlap, limits, and commits.
- Git and GitHub activity views, including repository summaries, diffs, graph/detail views, optional bundled Git tooling for release builds, and commit-message assistance.
- A read-only iOS companion for iPhone and iPad that reads private iCloud/CloudKit snapshots published by the Mac app.
- CloudKit leaderboards for opt-in, privacy-preserving aggregate scores, public nicknames, Beam avatars, status text, and trend history.
- System Monitor and Ops workspaces for CPU, memory, disk, network, power, thermal, listening ports, Homebrew packages, launch services, and developer environment checks.
- Config, Skills, LLM, Local AI, and Memory workspaces for provider configuration, local/plugin skills, app-level model settings, local model management, and the optional Code Agent memory sidecar.
- Linux.do native reader integration with browser-assisted sign-in, topic lists, topic detail reading, cache, and notifications.
- A Warp-powered embedded terminal workspace for full builds, with runtime and appearance settings.
- An Atoll-backed Notch Island surface with optional modules for media, stats, timer, clipboard, color picker, calendar, shelf, privacy, recording, focus, battery, Bluetooth, downloads, OSD, lock widgets, extension bridge, screen assistant, and terminal surfaces.
- A Rockxy-backed network debugger with traffic capture, HTTP/HTTPS/WebSocket/tunnel metadata, filters, inspectors, replay, intercept/automate workflows, proxy controls, upstream chaining, certificates, rules, plugins, and breakpoints.
- A Lite build for users who want the menu-bar stats, Git, daily reports, Gantt, leaderboards, and iCloud companion sync without the heavier integrations.
- Sparkle-based automatic updates for both packaged macOS variants, with separate full and Lite feeds.

## Screens

Screenshots and GIF demos live in [`docs/assets/screens`](docs/assets/screens), grouped here by product area.

<details open>
<summary><strong>Menu-bar extra</strong></summary>

<table>
  <tr>
    <th align="left" width="33%">Usage panel</th>
    <th align="left" width="33%">Activity panel</th>
    <th align="left" width="33%">Git panel</th>
  </tr>
  <tr>
    <td valign="top" width="33%">
      <img src="docs/assets/screens/menubar-usage.gif" alt="Menu-bar extra usage panel" width="100%">
    </td>
    <td valign="top" width="33%">
      <img src="docs/assets/screens/menubar-activity.gif" alt="Menu-bar extra activity panel" width="100%">
    </td>
    <td valign="top" width="33%">
      <img src="docs/assets/screens/menubar-git.gif" alt="Menu-bar extra Git panel" width="100%">
    </td>
  </tr>
</table>

<details>
<summary><strong>Share stats export</strong></summary>

<img src="docs/assets/screens/menubar-share-stats.gif" alt="Menu-bar share stats export flow">

</details>

</details>

<details open>
<summary><strong>Stats and activity</strong></summary>

<p><strong>Dashboard overview</strong></p>
<img src="docs/assets/screens/dashboard-overview.png" alt="Claude Stats dashboard overview">

<p><strong>Sessions overview</strong></p>
<img src="docs/assets/screens/sessions-overview.png" alt="Claude session statistics overview">

<p><strong>Token usage and limits</strong></p>
<img src="docs/assets/screens/usage-token-limits.png" alt="Token usage and usage limits">

<p><strong>AI-assisted focus timeline</strong></p>
<img src="docs/assets/screens/activity-focus-timeline.png" alt="AI-assisted focus timeline">

<p><strong>Weekly leaderboards</strong></p>
<img src="docs/assets/screens/leaderboards-weekly.png" alt="Weekly usage leaderboard">

</details>

<details>
<summary><strong>Community and local knowledge</strong></summary>

<p><strong>LinuxDo native reader</strong></p>
<img src="docs/assets/screens/linuxdo-reader.png" alt="LinuxDo native topic reader">

<p><strong>Plans and config browser</strong></p>
<img src="docs/assets/screens/configs-plans-browser.png" alt="Plans and config browser">

<p><strong>Skills library</strong></p>
<img src="docs/assets/screens/skills-library.png" alt="Local and plugin skills library">

</details>

<details>
<summary><strong>Developer tools</strong></summary>

<p><strong>API provider switcher</strong></p>
<img src="docs/assets/screens/provider-switcher.png" alt="API provider switcher">

<p><strong>Repository workspace</strong></p>
<img src="docs/assets/screens/git-repository-workspace.png" alt="Git repository workspace">

</details>

<details>
<summary><strong>Ops, network, and terminal</strong></summary>

<p><strong>Listening ports</strong></p>
<img src="docs/assets/screens/ops-listening-ports.png" alt="Listening ports inspector">

<p><strong>Homebrew packages</strong></p>
<img src="docs/assets/screens/ops-homebrew-packages.png" alt="Homebrew package inspector">

<p><strong>Developer environment check</strong></p>
<img src="docs/assets/screens/ops-environment-check.png" alt="Developer environment check">

<p><strong>Network traffic</strong></p>
<img src="docs/assets/screens/network-traffic.png" alt="Network traffic debugger">

<p><strong>Embedded terminal</strong></p>
<img src="docs/assets/screens/terminal-session.png" alt="Embedded terminal session">

</details>

<details>
<summary><strong>Settings</strong></summary>

<p><strong>Feature toggles</strong></p>
<img src="docs/assets/screens/settings-features.png" alt="Feature settings">

<p><strong>Terminal appearance</strong></p>
<img src="docs/assets/screens/settings-terminal-appearance.png" alt="Terminal appearance settings">

</details>

The iOS companion is not shown in the current screenshot set yet. It is documented below and can be run from the generated Xcode project.

## Install

Packaged macOS builds are published from this repository:

- [Latest release](https://github.com/1pitaph/claude-stats/releases/latest)
- [All GitHub Releases](https://github.com/1pitaph/claude-stats/releases)
- [Sparkle appcast](https://1pitaph.github.io/claude-stats/appcast.xml)
- [Sparkle Lite appcast](https://1pitaph.github.io/claude-stats/appcast-lite.xml)

Each tagged release publishes both macOS app variants:

| Variant | Release asset | Sparkle feed | Notes |
| --- | --- | --- | --- |
| Claude Stats | `ClaudeStats-<version>.dmg` | `appcast.xml` | Full app with Dictionary, Linux.do, Warp, Config, Ops, Network, Local AI, Memory, and Notch Island. |
| Claude Stats Lite | `ClaudeStatsLite-<version>.dmg` | `appcast-lite.xml` | Lite app with core stats, Git, daily reports, Gantt, leaderboards, and iCloud companion sync. |

Release packaging supports both signed/notarized builds and unsigned fallback builds. If you use an unsigned build, macOS Gatekeeper may require opening it with right-click, then **Open**.

The full and Lite apps update independently through Sparkle. A release may contain both packages even when a feature change only affects one variant, because shared code, version metadata, security fixes, and release notes still move together. Settings > About includes a download entry for the other variant, but switching variants is an install-side choice rather than an in-place Sparkle conversion.

### Compatibility

Current packaged macOS releases support Apple Silicon Macs running macOS 15 or later. The app bundle still carries a macOS 14 deployment target for the main app shell, but packaged releases include runtime components whose practical floor is macOS 15.

Intel Macs are not supported by current releases. The last public universal build with both `x86_64` and `arm64` slices was [v1.3.9](https://github.com/1pitaph/claude-stats/releases/tag/v1.3.9); releases from v1.3.11 onward ship an `arm64` main executable.

The iOS companion target supports iOS 17 or later on iPhone and iPad. It is currently built from source through the `ClaudeStats iOS` Xcode scheme rather than distributed as a public App Store/TestFlight package from this repository.

## iOS Companion

Claude Stats includes a read-only iOS companion app for checking Mac-side aggregate stats on iPhone or iPad. It does not scan iOS files or collect coding activity on the device. Instead, Claude Stats or Claude Stats Lite on the Mac publishes one private CloudKit record containing the latest encoded `StatsSnapshot`, and the iOS app reads that record from the same iCloud account.

The iOS app currently has three tabs:

- **Dashboard**: synced date, iCloud account state, tokens, cost, sessions, projects, AI time, active days, provider status, usage trend, token mix, providers, and usage limits.
- **Stats**: period usage, daily activity, usage summaries, top models, and daily reports.
- **Tool**: Daily Report rows, synced Gantt timeline, and Git activity overview.

Provider status on iOS supports OpenAI and Claude rollups, status page links, visible status row preferences, 90-day uptime strips, incidents, and stale-cache messages.

To publish real data, open Settings > iCloud Sync in a Mac build that has the CloudKit entitlement. Signed releases can do this, and development builds should use the `ClaudeStats CloudKit` or `ClaudeStats Lite CloudKit` schemes. The regular unsigned Debug macOS build can still run the app, but it cannot publish a real CloudKit snapshot without the entitlement.

## Privacy & Data

Claude Stats is local-first. Core usage stats are read from local tool data such as `~/.claude/projects/` and `~/.codex/sessions/`; optional activity, GitHub, system-monitoring, desktop-limit, Notch Island, terminal, network, and memory features only run when enabled or configured. Some features may request macOS permissions such as Full Disk Access, Accessibility, Screen Recording, Keychain access, iCloud, or helper-tool approval.

CloudKit sync for the iOS companion writes to the user's private CloudKit database. It uploads aggregate tokens, costs, session counts, daily summaries, usage-limit snapshots, activity intervals, dashboard totals, status summaries, Git summary rows, leaderboards summary fields, and anonymized project labels such as `Project 1`. It does not upload prompts, transcript text, filenames, raw project paths, or full session logs.

CloudKit leaderboards are separate and opt-in. They publish aggregate public scores plus profile metadata such as nickname, generated Beam avatar, and status text. The leaderboard flow is designed not to publish prompts, transcript content, filenames, raw paths, session titles, model names, or full logs.

Secrets and accounts are stored locally through the app's configured secure stores, such as Keychain for credentials. Preferences live in app storage, and caches/indexes live under the app's Application Support or Caches locations.

Network-facing features are opt-in or feature-specific: Sparkle checks for updates, provider status views may query public status pages, Linux.do integration may authenticate through the browser, GitHub features use a configured token, and the network debugger proxies only the traffic you route through it. The Rockxy helper and certificate features are powerful debugging tools, so review the source and settings before enabling HTTPS interception.

Local AI and Memory features are local by default, but they may use a configured online or local LLM provider depending on Settings > LLM and the feature-specific switches you enable.

## Build From Source

Clone with submodules:

```bash
git clone --recursive https://github.com/1pitaph/claude-stats.git
cd claude-stats
```

Install local build tools:

```bash
brew install xcodegen
```

Generate the Xcode project if you want to inspect it directly:

```bash
bash scripts/generate.sh
open ClaudeStats.xcodeproj
```

For normal macOS development, prefer the helper scripts:

```bash
bash scripts/run-debug.sh  # generate + build Debug + launch the menu-bar app
bash scripts/run-lite-debug.sh  # generate + build Debug + launch Claude Stats Lite
bash scripts/run-tests.sh  # generate + build test dependencies + run macOS unit tests
```

`ClaudeStats.xcodeproj` is generated from [`project.yml`](project.yml) with [XcodeGen](https://github.com/yonaskolb/XcodeGen). The debug launcher builds into the canonical `/tmp/Codex-stats-build` DerivedData path and launches the app by full path; this avoids Launch Services conflicts with menu-bar (`LSUIElement`) builds that share the same bundle identifier.

For CloudKit snapshot publishing during development, use the `ClaudeStats CloudKit` or `ClaudeStats Lite CloudKit` scheme and a signing setup that includes the `iCloud.com.claudestats.ClaudeStats` container entitlement.

### Build and Test iOS

The iOS companion lives in the generated project as the `ClaudeStats iOS` scheme. After generating the project, open `ClaudeStats.xcodeproj`, choose that scheme, and run it on an iOS 17+ simulator or device signed into the same iCloud account you use for the Mac app.

Run iOS unit tests with:

```bash
bash scripts/run-ios-tests.sh
```

The script defaults to `platform=iOS Simulator,name=iPhone 17 Pro` and `/tmp/Codex-stats-ios-build`. Override those when needed:

```bash
IOS_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro" bash scripts/run-ios-tests.sh
IOS_DERIVED_DATA_PATH="/tmp/Codex-stats-ios-build" bash scripts/run-ios-tests.sh
```

## Requirements

- Apple Silicon Mac with macOS 15+ for packaged macOS releases
- iPhone or iPad with iOS 17+ for the companion app
- Xcode 26+ with Swift 6 language mode
- XcodeGen for project generation

## Project Layout

```
ClaudeStats/
  App/          @main entry point, app environment, Info.plist, entitlements
  Features/     feature-specific app integrations such as Notch Island
  Models/       Sendable value types and generated release history
  Providers/    provider protocol, registry, and per-provider scanners/parsers
  Resources/    pricing data, Git tools placeholder, app resources
  Services/     stores, scanners, network debugging, system integrations
  ViewModels/   per-screen and feature view models
  Views/        menu bar, main window, settings, terminal, network, activity UI
  Utilities/    formatters, logging, shared helpers
ClaudeStatsiOS/      iPhone/iPad companion app UI and snapshot store
ClaudeStatsShared/   Swift package shared by macOS and iOS for stats and CloudKit sync
AtollEmbed/          app-side wrapper for the Atoll/DynamicIsland integration
RockxyBackendEmbed/  app-side wrapper for Rockxy proxy/debugging support
WarpEmbed/           app-side boundary for the embedded Warp ADE runtime
ThirdParty/          git submodules for Atoll, Rockxy, Warp, mem0, and Graphiti
ClaudeStatsTests/    parser, scanner, settings, integration, and feature tests
ClaudeStatsCoreTests/ shared stats and sync model tests
ClaudeStatsiOSTests/ iOS companion tests
docs/assets/         README images, icons, screenshots, and GIFs
scripts/             project generation, local run/test, release, appcast tooling
```

## Open Source & Third-Party Modules

Claude Stats is released under the [GNU Affero General Public License v3.0](LICENSE). The app also embeds and adapts several major open-source projects:

| Project | License | How Claude Stats uses it |
| --- | --- | --- |
| [Rockxy](https://github.com/1pitaph/Rockxy) | AGPL-3.0 | Integrated through `RockxyBackendEmbed` and `RockxyHelperTool` for the network debugger, proxy engine, rule handling, certificates, and privileged helper flow. |
| [Atoll / DynamicIsland](https://github.com/1pitaph/Atoll) | GPL-3.0 | Integrated through `AtollEmbed` for the optional Notch Island surface and modules. Its [`NOTICE`](ThirdParty/Atoll/NOTICE) and [`COPYRIGHT_ASSETS`](ThirdParty/Atoll/COPYRIGHT_ASSETS) files remain part of the attribution trail. |
| [Warp](https://github.com/1pitaph/Warp) | AGPL-3.0 / MIT for `warpui_core` and `warpui` | Vendored as the active in-window ADE/terminal embedding boundary through `WarpEmbed`. |
| [mem0](https://github.com/1pitaph/mem0) | Apache-2.0 | Vendored as a fork submodule for the optional Code Agent memory sidecar. The default local mode keeps the adapter disabled until an embedding/LLM provider is configured. |
| [Graphiti](https://github.com/1pitaph/graphiti) | Apache-2.0 | Vendored as a fork submodule for the optional temporal graph projection in the Code Agent memory sidecar. The first local backend targets embedded Kuzu. |

Additional Swift Package Manager dependencies include Sparkle, SwiftNIO, SwiftNIOSSL, Swift Certificates, Swift Crypto, Defaults, KeyboardShortcuts, SwiftUIIntrospect, Lottie, MacroVisionKit, SkyLightWindow, AtollExtensionKit, Swift Collections, and SwiftSoup. Those packages keep their upstream licenses and notices.

## Contributing

Issues and pull requests are welcome. Before opening a PR, run:

```bash
bash scripts/run-tests.sh
```

For app behavior changes, also run:

```bash
bash scripts/run-debug.sh
```

For iOS companion changes, run:

```bash
bash scripts/run-ios-tests.sh
```

Keep Swift 6 strict concurrency warning-free. When changing Atoll, Rockxy, or Warp integration code, make the source changes in the relevant submodule/fork first, then update the submodule pointer in this repo.
