# Codex Stats — Development Guide

## Build & Run

```bash
bash scripts/run-debug.sh
```

Generates `ClaudeStats.xcodeproj` from `project.yml`, builds Debug to
`/tmp/Codex-stats-build`, refreshes Launch Services, and launches the app.

**IMPORTANT:** This is a menu-bar (`LSUIElement`) app. Do NOT `open -a "Codex Stats"`
or build to the default DerivedData path — multiple registered `.app` bundles with
the same bundle id cause Launch Services conflicts and the menu-bar item silently
fails to appear. Always use `/tmp/Codex-stats-build` as the `-derivedDataPath` and
launch by full path (the script does this).

After every round that changes code, run `bash scripts/run-debug.sh` before
responding so the latest build is compiled and launched from the canonical
DerivedData path.

## iOS Companion App

After every round that changes iOS app code (`ClaudeStatsiOS/`, shared models
used by iOS, or `project.yml` iOS target settings), rebuild and relaunch the
iOS app in the Simulator before responding. The visual Simulator state should
come from the latest build, not a still-running previous install. For test
coverage, run `bash scripts/run-ios-tests.sh`.

## Tests

```bash
bash scripts/run-tests.sh
```

## Releasing

The version number lives in `project.yml` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
`Info.plist` references those via `$(…)`, and `SettingsView`'s About row reads them back from
`Bundle.main` at runtime — so a release just needs the version baked into the build.

To cut a release, push a semver tag:

```bash
git tag v1.2.0 && git push origin v1.2.0
```

`.github/workflows/release.yml` (runs on `macos-26` with Xcode 26.4.1) then: writes `1.2.0` into `project.yml`
(build number = the workflow run number), builds Release `Claude Stats.app` and
`Claude Stats Lite.app`, packages both variants, publishes a GitHub Release
**in this source repo** with the artifact(s) attached, publishes the Sparkle
appcasts through an explicit GitHub Pages deployment job, snapshots those files
to this repo's `gh-pages` branch, and commits the bumped `project.yml` back to
`master` here.

The source repo is public and is the canonical download/update host. During the
migration away from the old public `claude-stats-releases` companion repo, the
workflow can still mirror only `appcast.xml` to that repo's `gh-pages` branch via
the optional fine-grained PAT `RELEASES_REPO_TOKEN` (Contents: Read and write) so
older builds can discover the migration release. The mirror includes generated
appcast files only; release binaries are no longer uploaded there.

Packaging has two modes, picked automatically:

- **Signed + notarized DMG** — when all signing and notarization secrets are set on the repo
  (`BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_TEAM_ID`,
  `BUILD_PROVISION_PROFILE_BASE64`, `NOTARY_APPLE_ID`, `NOTARY_PASSWORD`; see the
  comment block at the top of the workflow). Produces `ClaudeStats-<version>.dmg`
  and `ClaudeStatsLite-<version>.dmg`.
- **Un-notarized DMG + .zip** — when those secrets are absent (the default). Gatekeeper warns
  on first launch; users open it via right-click ▸ Open. Produces DMG and zip
  artifacts for both variants.

`scripts/release-build.sh` mirrors this: with `SIGN_IDENTITY` (plus `APPLE_TEAM_ID`, `APPLE_ID`,
`APP_PASSWORD`) it codesigns with hardened runtime, notarizes via `notarytool`, and staples
both DMGs; without it, it produces ad-hoc DMGs + zips for both variants. Dry-run locally:
`bash scripts/release-build.sh 1.2.0`.
Bump the version without building: `bash scripts/bump-version.sh 1.2.0`.

## Auto-update (Sparkle)

The app embeds [Sparkle 2](https://sparkle-project.org) (SPM dep in `project.yml`).
`UpdaterController` wraps `SPUStandardUpdaterController`; it's owned by
`AppEnvironment` and started from `AppEnvironment.start()`. Because this is an
`LSUIElement` app, `UpdaterController` flips the activation policy to `.regular`
while Sparkle's windows are up and back to `.accessory` when the session ends.
Settings ▸ About has a "Check for Updates…" button; scheduled background checks
are on by default (`SUEnableAutomaticChecks` in `Info.plist`).

The main update feed is `appcast.xml`, served at
`https://1pitaph.github.io/claude-stats/appcast.xml`
(`SUFeedURL` in `Info.plist`). The Lite feed is `appcast-lite.xml`, served at
`https://1pitaph.github.io/claude-stats/appcast-lite.xml`
(`SUFeedURL` in `InfoLite.plist`). On each tagged release the workflow EdDSA-signs
each variant archive (`scripts/publish-appcast.sh` → `scripts/update-appcast.py`)
and uploads the generated files as a Pages artifact. A dedicated `deploy-pages`
job deploys that artifact and exposes the deployment status and site URL in
Actions. The workflow also commits the same files to `gh-pages` as a history
snapshot, but branch pushes do not drive the live deployment. During the
transition, generated appcasts can also be mirrored to
`https://1pitaph.github.io/claude-stats-releases/` for older builds whose
`SUFeedURL` still points there. This works the same whether the release is the
un-notarized zip/DMG or the signed+notarized DMG — Sparkle just downloads
whichever asset the appcast points at (it prefers the `.zip` when present).
Release notes are generated from the source repo's commit log
between this tag and the previous semver tag, written as both markdown (used as
the GitHub Release body) and minimal HTML (embedded directly in the appcast's
`<description>` CDATA so Sparkle renders them inline without a webview fetch).

**One-time setup:**

1. Enable GitHub Pages on this repo: Settings → Pages → Source = **GitHub
   Actions**. Changing the publishing source requires repository administration
   permission, so the release workflow verifies this setting without trying to
   modify it through `GITHUB_TOKEN`.
2. Optional migration mirror: keep `1pitaph/claude-stats-releases` Pages enabled,
   create a fine-grained PAT scoped to that repo with **Contents: Read and write**,
   and add it as `RELEASES_REPO_TOKEN` until old builds have moved to the new feed.
3. Sparkle keys: `./bin/generate_keys` to generate (private key into login
   keychain, public key printed), then `./bin/generate_keys -x sparkle_private_key`
   to export the private key for CI. Put the public key in `Info.plist` as
   `SUPublicEDKey`; add the exported file's contents as repo secret
   `SPARKLE_PRIVATE_ED_KEY` (then `rm` the file — keychain keeps a copy).

## Regenerate the Xcode project

`ClaudeStats.xcodeproj` is generated, not committed. After editing `project.yml`
(or adding/removing source folders), run `bash scripts/generate.sh`.

## Atoll / Notch Island integration

`ThirdParty/Atoll` is a maintained fork submodule, not a throwaway dirty checkout.
Its fork remote is `https://github.com/1pitaph/Atoll.git`, the original project
remote is named `upstream`, and Claude Stats integration work lives on
`integration/claude-stats`.

Keep Atoll source changes inside the Atoll fork. Commit and push them from inside
`ThirdParty/Atoll`, then return to the main repo and commit only the updated
submodule pointer plus any Claude Stats integration files. Do not add
`ignore = dirty` back to `.gitmodules`; a dirty Atoll checkout should be visible
because it means the main app depends on uncommitted submodule code.

Typical Atoll edit flow:

```bash
git -C ThirdParty/Atoll checkout integration/claude-stats
# edit Atoll files
git -C ThirdParty/Atoll commit -am "Describe Atoll change"
git -C ThirdParty/Atoll push origin integration/claude-stats
git add ThirdParty/Atoll
```

When pulling new upstream Atoll changes, merge them into the integration branch
instead of replacing the branch:

```bash
git -C ThirdParty/Atoll fetch upstream
git -C ThirdParty/Atoll checkout integration/claude-stats
git -C ThirdParty/Atoll merge upstream/main
git -C ThirdParty/Atoll push origin integration/claude-stats
git add ThirdParty/Atoll
```

Atoll's MediaRemote runtime resources are intentionally split between the fork
and the app integration:

- `MediaRemoteAdapter.framework` stays embedded as nested code in
  `Contents/Frameworks` through the normal XcodeGen embed/sign configuration.
  Do not copy it into Resources for the app just to satisfy an old lookup path.
- `mediaremote-adapter.pl` is copied from
  `ThirdParty/Atoll/mediaremote-adapter/mediaremote-adapter.pl` into
  `Contents/Resources`.
- `NowPlayingTestClient` is copied from
  `ThirdParty/Atoll/Contents/Helpers/NowPlayingTestClient` into
  `Contents/Helpers`, kept executable, and re-signed during signed release builds.

The app-side runtime path logic lives in
`AtollEmbed/Runtime/AtollRuntimeResourceLocator.swift`. Use that locator for
Atoll bundle paths instead of open-coding `Bundle.main` lookups. It resolves the
Perl script from Resources, prefers `Bundle.main.privateFrameworksURL` /
`Contents/Frameworks` for `MediaRemoteAdapter.framework` with a Resources fallback
for compatibility, and requires `NowPlayingTestClient` to be executable. Keep
focused tests in `ClaudeStatsTests/AtollRuntimeResourceLocatorTests.swift` when
changing these paths.

After changing Atoll integration or `project.yml`, run `bash scripts/generate.sh`
if the Xcode project needs regeneration, then run `bash scripts/run-tests.sh` and
`bash scripts/run-debug.sh`. For release/signing-related changes, also verify the
built app with `codesign --verify --deep --strict`.

## Rockxy integration

`ThirdParty/Rockxy` is a maintained fork submodule, not a throwaway dirty checkout.
Its fork remote is `https://github.com/1pitaph/Rockxy.git`, the original project
remote is named `upstream`, and Claude Stats integration work lives on
`integration/claude-stats`.

Keep Rockxy source changes inside the Rockxy fork. Commit and push them from inside
`ThirdParty/Rockxy`, then return to the main repo and commit only the updated
submodule pointer plus Claude Stats integration files. Do not add `ignore = dirty`
for Rockxy in `.gitmodules`; a dirty Rockxy checkout should be visible because it
means the main app depends on uncommitted submodule code.

Typical Rockxy edit flow:

```bash
git -C ThirdParty/Rockxy checkout integration/claude-stats
# edit Rockxy files
git -C ThirdParty/Rockxy commit -am "Describe Rockxy change"
git -C ThirdParty/Rockxy push origin integration/claude-stats
git add ThirdParty/Rockxy
```

When pulling new upstream Rockxy changes, merge them into the integration branch
instead of replacing the branch:

```bash
git -C ThirdParty/Rockxy fetch upstream
git -C ThirdParty/Rockxy checkout integration/claude-stats
git -C ThirdParty/Rockxy merge upstream/main
git -C ThirdParty/Rockxy push origin integration/claude-stats
git add ThirdParty/Rockxy
```

## Provider code organization

Today there is one provider (Codex). Provider-specific behaviour lives under
`ClaudeStats/Providers/<Provider>/`; cross-provider logic lives in shared files
(`Models/`, `Services/`, `Utilities/`).

**Rule of thumb — per-provider data, shared behaviour:** any alias table, file
format quirk, or path convention that only one provider cares about belongs in
that provider's folder, behind the `Provider` protocol. How the canonical data
is rendered (formatters, the menu-bar label, the usage charts) is shared. When
you catch yourself writing `switch providerName { case "…": … }` in shared
code, stop — route it through a provider-owned method instead.

Adding a second provider should be: a new folder under `Providers/`, a type
conforming to `Provider`, and one line in `ProviderRegistry.all`. No changes to
shared code.

## Conventions

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY = complete`. Keep it warning-free.
- Data models are `Sendable` value types. Stores and view models are
  `@MainActor @Observable`. File I/O (scanning, parsing) runs off the main actor
  as plain `async` functions on non-isolated types.
- Logging goes through `Log` (`os.Logger`), not `print`.
- SwiftUI resize performance: preserve adaptive layouts unless the product
  behaviour is explicitly changing. If a pane is wide = two columns / narrow =
  one column, keep that breakpoint and keep `.infinity` where it prevents the
  sidebar or detail content from being clipped. To reduce resize jank, prefer
  `minWidth` + `idealWidth` + `maxWidth: .infinity`, stable `ForEach(rows)` over
  `Array(rows.enumerated())`, `LazyVStack` for long stacked tables, `Equatable`
  row data/views when equality is cheap, and fixed widths for trailing numeric
  columns so text measurement does not churn on every drag tick.

## UI Standards

- Content scroll regions must use the app-standard native scrollbar helpers:
  `AppScrollView` for SwiftUI content and `AppScrollbars.configure(_:axes:)` for
  `NSScrollView` wrappers. `AppScrollView` must keep its underlying native
  `NSScrollView` configured with the same helper so SwiftUI and AppKit scroll
  regions share the same overlay/autohide behavior. Let macOS own scrollbar
  rendering; do not add custom-drawn scrollbar thumbs or suppress native
  scrollers for normal content.
- Compact horizontal affordances such as tab strips, ref pills, and short inline
  code snippets may keep indicators hidden when the surrounding design depends
  on that compactness. For full content panes, sidebars, lists, inspectors,
  editors, and tables, use the standard helpers instead.
