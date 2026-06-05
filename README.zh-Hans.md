<p align="center">
  <img src="docs/assets/claude-stats-icon.png" alt="Claude Stats 应用图标" width="128" height="128">
</p>

<h1 align="center">Claude Stats</h1>

<p align="center">
  面向 AI 编程工作的原生 macOS 菜单栏统计、Dashboard、iOS companion 同步、Notch Island、终端与网络调试工具。
</p>

<p align="center">
  <a href="#功能">功能</a> ·
  <a href="#截图">截图</a> ·
  <a href="#安装">安装</a> ·
  <a href="#ios-companion">iOS Companion</a> ·
  <a href="#隐私与数据">隐私与数据</a> ·
  <a href="#从源码构建">从源码构建</a> ·
  <a href="#开源与第三方模块">开源</a> ·
  <a href="#贡献">贡献</a> ·
  <a href="README.md">English</a>
</p>

Claude Stats 是一个开源的原生 macOS 应用，适合每天长时间使用 AI 编程工具的人。它常驻菜单栏，读取本地用量与活动数据，并把会话、token、成本、额度、仓库活动、本机状态、服务状态和调试上下文整理成可以快速查看的信息。

这个项目最初是开源项目 [Claude Statistics](https://github.com/sj719045032/claude-statistics) 的 macOS 原生版本。现在它已经扩展为一个多 provider 基础的工作台，包含 Dashboard、面向 iOS companion 的 CloudKit 同步、可选公开排行榜、Warp 驱动的终端界面、Atoll 支持的 Notch Island，以及 Rockxy 支持的网络调试器，同时继续保留 **Claude Stats** 这个主产品名。

Claude Stats 有两个 macOS 版本：完整应用和 **Claude Stats Lite**。Lite 保留核心菜单栏统计、Git 视图、每日报告、Gantt、排行榜和 iCloud 快照同步，但去掉 Dictionary、Linux.do、Warp、Config、Ops、Network、Local AI、Memory 和 Notch Island 等较重的集成。两个应用使用不同的 bundle identifier 和 Sparkle 更新源，因此可以并排安装。

## 功能

- 原生菜单栏用量统计，支持 AI 编程会话、token、预估成本、cache reads、最近活动、provider 切换、刷新、分享导出、更新、设置和快速退出。
- 支持解析 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) 和 OpenAI Codex 会话日志；Gemini、Kimi、MiniMax 已在 UI 中识别，但它们的本地会话解析仍是未来工作。
- Dashboard 和 Usage 视图包含摘要卡片、模型拆分、token 构成、cache hit rate、成本模式、按日导航、图表、Claude/OpenAI 状态卡、GitHub 热力图，以及 AI/GitHub 活动重叠分析。
- 支持 provider 的用量额度视图与预测，包括 Claude Desktop bridge 流程和 OpenAI/Codex 状态数据。
- Sessions、transcript analysis 与技术术语词典工具，用于理解本地 AI 编程对话。
- Daily Report 和 Gantt 工作区会按天汇总 AI 活跃项目，并可视化工作块、provider、token 强度、专注重叠、额度与提交记录。
- Git 和 GitHub 活动视图，包括仓库摘要、diff、图谱/详情视图、release build 可选内置 Git 工具，以及 commit message 辅助。
- iPhone 和 iPad 上的只读 iOS companion，可读取 Mac 应用发布到私有 iCloud/CloudKit 的统计快照。
- CloudKit 排行榜是可选的隐私保护聚合分数同步，支持公开昵称、Beam 头像、状态文字和趋势历史。
- System Monitor 和 Ops 工作区可查看 CPU、内存、磁盘、网络、电源、温度、监听端口、Homebrew 包、Launch Services 和开发环境检查。
- Config、Skills、LLM、Local AI 和 Memory 工作区覆盖 provider 配置、本地/插件 skills、应用级模型设置、本地模型管理，以及可选 Code Agent memory sidecar。
- Linux.do 原生阅读器集成，支持浏览器辅助登录、主题列表、主题详情阅读、缓存和通知。
- 完整版内置 Warp 驱动的终端工作区，并提供 runtime 和外观设置。
- Atoll 支持的 Notch Island，可选模块包括媒体、统计、计时器、剪贴板、取色器、日历、Shelf、隐私、录制、专注、电池、蓝牙、下载、OSD、锁屏小组件、extension bridge、screen assistant 和终端界面。
- Rockxy 支持的网络调试器，包含流量捕获、HTTP/HTTPS/WebSocket/tunnel 元数据、过滤、检查器、重放、拦截/自动化流程、代理控制、上游代理、证书、规则、插件和断点。
- Lite 版本适合只想要菜单栏统计、Git、每日报告、Gantt、排行榜和 iCloud companion 同步，而不需要较重集成的用户。
- 两个打包的 macOS 版本都使用 Sparkle 自动更新，并拥有独立的完整/Lite 更新源。

## 截图

截图和 GIF 演示位于 [`docs/assets/screens`](docs/assets/screens)，下面按产品区域分组。

<details open>
<summary><strong>菜单栏面板</strong></summary>

<table>
  <tr>
    <th align="left" width="33%">用量面板</th>
    <th align="left" width="33%">活动面板</th>
    <th align="left" width="33%">Git 面板</th>
  </tr>
  <tr>
    <td valign="top" width="33%">
      <img src="docs/assets/screens/menubar-usage.gif" alt="菜单栏用量面板" width="100%">
    </td>
    <td valign="top" width="33%">
      <img src="docs/assets/screens/menubar-activity.gif" alt="菜单栏活动面板" width="100%">
    </td>
    <td valign="top" width="33%">
      <img src="docs/assets/screens/menubar-git.gif" alt="菜单栏 Git 面板" width="100%">
    </td>
  </tr>
</table>

<details>
<summary><strong>分享统计导出</strong></summary>

<img src="docs/assets/screens/menubar-share-stats.gif" alt="菜单栏分享统计导出流程">

</details>

</details>

<details open>
<summary><strong>统计与活动</strong></summary>

<p><strong>Dashboard 概览</strong></p>
<img src="docs/assets/screens/dashboard-overview.png" alt="Claude Stats Dashboard 概览">

<p><strong>Sessions 概览</strong></p>
<img src="docs/assets/screens/sessions-overview.png" alt="Claude 会话统计概览">

<p><strong>Token 用量与额度</strong></p>
<img src="docs/assets/screens/usage-token-limits.png" alt="Token 用量和用量额度">

<p><strong>AI 辅助专注时间线</strong></p>
<img src="docs/assets/screens/activity-focus-timeline.png" alt="AI 辅助专注时间线">

<p><strong>每周排行榜</strong></p>
<img src="docs/assets/screens/leaderboards-weekly.png" alt="每周用量排行榜">

</details>

<details>
<summary><strong>社区与本地知识</strong></summary>

<p><strong>LinuxDo 原生阅读器</strong></p>
<img src="docs/assets/screens/linuxdo-reader.png" alt="LinuxDo 原生主题阅读器">

<p><strong>Plans 与配置浏览器</strong></p>
<img src="docs/assets/screens/configs-plans-browser.png" alt="Plans 与配置浏览器">

<p><strong>Skills 库</strong></p>
<img src="docs/assets/screens/skills-library.png" alt="本地与插件 skills 库">

</details>

<details>
<summary><strong>开发者工具</strong></summary>

<p><strong>API provider 切换器</strong></p>
<img src="docs/assets/screens/provider-switcher.png" alt="API provider 切换器">

<p><strong>仓库工作区</strong></p>
<img src="docs/assets/screens/git-repository-workspace.png" alt="Git 仓库工作区">

</details>

<details>
<summary><strong>Ops、网络与终端</strong></summary>

<p><strong>监听端口</strong></p>
<img src="docs/assets/screens/ops-listening-ports.png" alt="监听端口检查器">

<p><strong>Homebrew 包</strong></p>
<img src="docs/assets/screens/ops-homebrew-packages.png" alt="Homebrew 包检查器">

<p><strong>开发环境检查</strong></p>
<img src="docs/assets/screens/ops-environment-check.png" alt="开发环境检查">

<p><strong>网络流量</strong></p>
<img src="docs/assets/screens/network-traffic.png" alt="网络流量调试器">

<p><strong>内置终端</strong></p>
<img src="docs/assets/screens/terminal-session.png" alt="内置终端会话">

</details>

<details>
<summary><strong>设置</strong></summary>

<p><strong>功能开关</strong></p>
<img src="docs/assets/screens/settings-features.png" alt="功能设置">

<p><strong>终端外观</strong></p>
<img src="docs/assets/screens/settings-terminal-appearance.png" alt="终端外观设置">

</details>

当前截图集中还没有 iOS companion 截图。它的行为在下方说明，也可以从生成的 Xcode project 运行。

## 安装

打包的 macOS 构建由本仓库发布：

- [Latest release](https://github.com/1pitaph/claude-stats/releases/latest)
- [All GitHub Releases](https://github.com/1pitaph/claude-stats/releases)
- [Sparkle appcast](https://1pitaph.github.io/claude-stats/appcast.xml)
- [Sparkle Lite appcast](https://1pitaph.github.io/claude-stats/appcast-lite.xml)

每个 tag release 都会发布两个 macOS 应用版本：

| 版本 | Release asset | Sparkle feed | 说明 |
| --- | --- | --- | --- |
| Claude Stats | `ClaudeStats-<version>.dmg` | `appcast.xml` | 完整应用，包含 Dictionary、Linux.do、Warp、Config、Ops、Network、Local AI、Memory 和 Notch Island。 |
| Claude Stats Lite | `ClaudeStatsLite-<version>.dmg` | `appcast-lite.xml` | Lite 应用，包含核心统计、Git、每日报告、Gantt、排行榜和 iCloud companion 同步。 |

Release 打包支持签名/公证构建，也支持未签名 fallback 构建。如果使用未签名构建，macOS Gatekeeper 可能要求右键点击应用，然后选择 **Open**。

完整应用和 Lite 应用通过 Sparkle 独立更新。即使某次功能只影响其中一个版本，release 也可能同时包含两个包，因为共享代码、版本元数据、安全修复和 release notes 会一起前进。Settings > About 中提供另一个版本的下载入口，但切换版本是安装层面的选择，不是 Sparkle 原地转换。

### 兼容性

当前打包的 macOS release 支持运行 macOS 15 或更高版本的 Apple Silicon Mac。主 app shell 仍保留 macOS 14 deployment target，但打包 release 中包含的 runtime 组件实际最低要求是 macOS 15。

当前 release 不支持 Intel Mac。最后一个同时包含 `x86_64` 和 `arm64` slices 的公开 universal build 是 [v1.3.9](https://github.com/1pitaph/claude-stats/releases/tag/v1.3.9)；从 v1.3.11 起，release 的主可执行文件是 `arm64`。

iOS companion target 支持 iOS 17 或更高版本的 iPhone 和 iPad。它目前通过 `ClaudeStats iOS` Xcode scheme 从源码构建，而不是由本仓库发布公开 App Store/TestFlight 包。

## iOS Companion

Claude Stats 包含一个只读 iOS companion app，用于在 iPhone 或 iPad 上查看 Mac 端聚合统计。它不会扫描 iOS 文件，也不会在设备上收集编程活动。相反，Mac 上的 Claude Stats 或 Claude Stats Lite 会发布一条包含最新编码 `StatsSnapshot` 的私有 CloudKit record，iOS app 会从同一个 iCloud 账号读取这条记录。

iOS app 当前有三个 tab：

- **Dashboard**：同步日期、iCloud 账号状态、token、成本、会话、项目、AI time、活跃天数、provider 状态、用量趋势、token mix、providers 和用量额度。
- **Stats**：周期用量、每日活动、用量摘要、热门模型和每日报告。
- **Tool**：Daily Report 行、同步的 Gantt 时间线，以及 Git 活动概览。

iOS 上的 provider 状态支持 OpenAI 和 Claude 汇总、状态页链接、可见状态行偏好、90 天 uptime strips、incident 和 stale-cache 信息。

要发布真实数据，请在带有 CloudKit entitlement 的 Mac 构建中打开 Settings > iCloud Sync。签名 release 可以这样做，开发构建应使用 `ClaudeStats CloudKit` 或 `ClaudeStats Lite CloudKit` scheme。普通未签名 Debug macOS 构建仍可运行应用，但没有 entitlement 时不能发布真实 CloudKit 快照。

## 隐私与数据

Claude Stats 以本地优先为原则。核心用量统计读取本地工具数据，例如 `~/.claude/projects/` 和 `~/.codex/sessions/`；可选的活动、GitHub、系统监控、桌面额度、Notch Island、终端、网络和 memory 功能只会在启用或配置后运行。某些功能可能请求 Full Disk Access、Accessibility、Screen Recording、Keychain access、iCloud 或 helper-tool approval 等 macOS 权限。

面向 iOS companion 的 CloudKit sync 写入用户的私有 CloudKit 数据库。它上传聚合 token、成本、会话数、每日摘要、用量额度快照、活动区间、Dashboard 总计、状态摘要、Git 摘要行、排行榜摘要字段，以及类似 `Project 1` 的匿名项目标签。它不会上传 prompts、transcript text、filenames、raw project paths 或 full session logs。

CloudKit leaderboards 是独立且可选的。它们发布公开聚合分数，以及昵称、生成的 Beam 头像、状态文字等 profile metadata。排行榜流程设计上不会发布 prompts、transcript content、filenames、raw paths、session titles、model names 或 full logs。

Secrets 和账号信息会通过应用配置的安全存储保存在本机，例如凭据使用 Keychain。偏好设置保存在应用存储中，缓存和索引保存在应用的 Application Support 或 Caches 位置。

网络相关功能是可选或功能特定的：Sparkle 会检查更新，provider 状态视图可能查询公开状态页，Linux.do 集成可能通过浏览器认证，GitHub 功能使用配置的 token，网络调试器只代理你主动路由给它的流量。Rockxy helper 和证书功能是强大的调试工具，启用 HTTPS interception 前请先查看源码和设置。

Local AI 和 Memory 功能默认偏本地，但它们可能根据 Settings > LLM 和对应功能开关使用已配置的在线或本地 LLM provider。

## 从源码构建

克隆并拉取 submodules：

```bash
git clone --recursive https://github.com/1pitaph/claude-stats.git
cd claude-stats
```

安装本地构建工具：

```bash
brew install xcodegen
```

如果想直接查看 Xcode project，先生成它：

```bash
bash scripts/generate.sh
open ClaudeStats.xcodeproj
```

日常 macOS 开发建议使用 helper scripts：

```bash
bash scripts/run-debug.sh  # generate + build Debug + launch the menu-bar app
bash scripts/run-lite-debug.sh  # generate + build Debug + launch Claude Stats Lite
bash scripts/run-tests.sh  # generate + build test dependencies + run macOS unit tests
```

`ClaudeStats.xcodeproj` 由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 根据 [`project.yml`](project.yml) 生成。debug launcher 会构建到固定的 `/tmp/Codex-stats-build` DerivedData 路径，并通过完整路径启动 app；这可以避免多个菜单栏 (`LSUIElement`) 构建使用同一个 bundle identifier 时造成 Launch Services 冲突。

如果开发时需要发布 CloudKit 快照，请使用 `ClaudeStats CloudKit` 或 `ClaudeStats Lite CloudKit` scheme，并配置包含 `iCloud.com.claudestats.ClaudeStats` container entitlement 的签名环境。

### 构建和测试 iOS

iOS companion 在生成的 project 中对应 `ClaudeStats iOS` scheme。生成 project 后，打开 `ClaudeStats.xcodeproj`，选择该 scheme，并在 iOS 17+ simulator 或登录同一 iCloud 账号的设备上运行。

运行 iOS unit tests：

```bash
bash scripts/run-ios-tests.sh
```

该脚本默认使用 `platform=iOS Simulator,name=iPhone 17 Pro` 和 `/tmp/Codex-stats-ios-build`。需要时可以覆盖：

```bash
IOS_TEST_DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro" bash scripts/run-ios-tests.sh
IOS_DERIVED_DATA_PATH="/tmp/Codex-stats-ios-build" bash scripts/run-ios-tests.sh
```

## 要求

- 打包的 macOS release 需要 Apple Silicon Mac 和 macOS 15+
- iOS companion 需要运行 iOS 17+ 的 iPhone 或 iPad
- Xcode 26+，使用 Swift 6 language mode
- 用于生成 project 的 XcodeGen

## 项目结构

```
ClaudeStats/
  App/          @main 入口、app environment、Info.plist、entitlements
  Features/     Notch Island 等功能集成
  Models/       Sendable value types 和生成的 release history
  Providers/    provider protocol、registry、各 provider scanner/parser
  Resources/    pricing data、Git tools placeholder、app resources
  Services/     stores、scanners、network debugging、system integrations
  ViewModels/   各屏幕和功能的 view models
  Views/        菜单栏、主窗口、设置、终端、网络、活动 UI
  Utilities/    formatters、logging、shared helpers
ClaudeStatsiOS/      iPhone/iPad companion app UI 和 snapshot store
ClaudeStatsShared/   macOS 与 iOS 共享的 stats / CloudKit sync Swift package
AtollEmbed/          Atoll/DynamicIsland 集成的 app-side wrapper
RockxyBackendEmbed/  Rockxy proxy/debugging 支持的 app-side wrapper
WarpEmbed/           embedded Warp ADE runtime 的 app-side boundary
ThirdParty/          Atoll、Rockxy、Warp、mem0、Graphiti git submodules
ClaudeStatsTests/    parser、scanner、settings、integration、feature tests
ClaudeStatsCoreTests/ shared stats 和 sync model tests
ClaudeStatsiOSTests/ iOS companion tests
docs/assets/         README images、icons、screenshots、GIFs
scripts/             project generation、local run/test、release、appcast tooling
```

## 开源与第三方模块

Claude Stats 使用 [GNU Affero General Public License v3.0](LICENSE) 发布。应用也嵌入并适配了几个重要开源项目：

| Project | License | Claude Stats 如何使用 |
| --- | --- | --- |
| [Rockxy](https://github.com/1pitaph/Rockxy) | AGPL-3.0 | 通过 `RockxyBackendEmbed` 和 `RockxyHelperTool` 集成，用于网络调试器、代理引擎、规则处理、证书和 privileged helper flow。 |
| [Atoll / DynamicIsland](https://github.com/1pitaph/Atoll) | GPL-3.0 | 通过 `AtollEmbed` 集成，用于可选 Notch Island 界面和模块。其 [`NOTICE`](ThirdParty/Atoll/NOTICE) 和 [`COPYRIGHT_ASSETS`](ThirdParty/Atoll/COPYRIGHT_ASSETS) 文件仍是 attribution trail 的一部分。 |
| [Warp](https://github.com/1pitaph/Warp) | AGPL-3.0 / `warpui_core` 和 `warpui` 为 MIT | 作为当前 in-window ADE/terminal embedding boundary，通过 `WarpEmbed` vendored。 |
| [mem0](https://github.com/1pitaph/mem0) | Apache-2.0 | 作为 fork submodule vendored，用于可选 Code Agent memory sidecar。默认本地模式会保持 adapter disabled，直到配置 embedding/LLM provider。 |
| [Graphiti](https://github.com/1pitaph/graphiti) | Apache-2.0 | 作为 fork submodule vendored，用于 Code Agent memory sidecar 的可选 temporal graph projection。第一个本地 backend 目标是 embedded Kuzu。 |

其他 Swift Package Manager 依赖包括 Sparkle、SwiftNIO、SwiftNIOSSL、Swift Certificates、Swift Crypto、Defaults、KeyboardShortcuts、SwiftUIIntrospect、Lottie、MacroVisionKit、SkyLightWindow、AtollExtensionKit、Swift Collections 和 SwiftSoup。这些 package 保留其上游 license 和 notices。

## 贡献

欢迎提交 issues 和 pull requests。打开 PR 前，请运行：

```bash
bash scripts/run-tests.sh
```

如果改动影响 app 行为，也请运行：

```bash
bash scripts/run-debug.sh
```

如果改动影响 iOS companion，请运行：

```bash
bash scripts/run-ios-tests.sh
```

请保持 Swift 6 strict concurrency 无警告。修改 Atoll、Rockxy 或 Warp 集成代码时，先在对应 submodule/fork 中提交源码改动，再回到本仓库更新 submodule pointer。
