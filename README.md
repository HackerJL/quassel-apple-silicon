# Quassel for Apple Silicon

Builds native arm64 macOS apps of the [Quassel IRC](https://github.com/quassel/quassel) client
from the latest upstream source. The last official release (0.14.0, 2022) ships Intel-only Mac
builds that need Rosetta; upstream development continues but there are no new Mac packages.

This repo holds only the build recipe. The Quassel source is cloned into `src/` (ignored).

## Build

Requires Homebrew and the Xcode Command Line Tools.

```sh
./build.sh
```

Re-run any time to pull upstream changes and rebuild. Output lands in `dist/`:

| App | What it is |
| --- | --- |
| `Quassel Client.app` | Client only — connects to a Quassel core you run elsewhere |
| `Quassel.app` | All-in-one (monolithic) — connects to IRC directly |

Both are self-contained (Qt is bundled), so they keep working if Homebrew is removed.

The apps run only on the macOS version they were built on or newer: the bundled Homebrew
libraries target the build machine's macOS. Building on macOS 27 means they need macOS 27.

## Install / replace an existing Quassel

Drag the app into `/Applications`, replacing the matching old one (Client for Client,
all-in-one for all-in-one — they store settings under different names).

Settings are kept outside the app and are picked up unchanged:

- `~/Library/Preferences/org.quassel-irc.*.plist` — client settings, saved core logins
- `~/Library/Application Support/Quassel/` — data, certificates, and (all-in-one) the chat log database

The database schema is unchanged since 0.14.0, so switching back to the old app still works.
Back up `~/Library/Application Support/Quassel/` first anyway.

The apps are ad-hoc signed, so on another Mac the first launch is blocked. Right-click → Open,
or run:

```sh
xattr -dr com.apple.quarantine "/Applications/Quassel Client.app"
```

## Additions over upstream

- **Dark mode toolbar icons** (`patches/0001-auto-dark-icon-theme.patch`): with the icon theme
  set to "Automatic", Quassel uses Breeze Dark under a dark appearance and switches live.
  `build.sh` applies everything in `patches/` to a clean checkout.
- **macOS 26+ app icon** (`icon/Quassel.icon`): an Icon Composer icon with the ring and dot
  as separate glass layers, so macOS can render light, dark, clear and tinted variants
  (System Settings → Appearance → Icon & widget style). Compiling it needs full Xcode; without
  it `build.sh` falls back to the classic flat icon. `icon/make-layers.swift` regenerates the
  layer images.

To try changes without replacing a working build, build side by side:

```sh
DIST=dist-test BUILD=src/build-test ./build.sh
```

## What's left out

- **Core binary** (`quasselcore`) — not built (`WANT_CORE=OFF`); the all-in-one app includes core functionality.
- **FiSH/Blowfish chat encryption** — needs QCA built against Qt 5; Homebrew's `qca` targets Qt 6.
  TLS connections to servers are unaffected.
- **Link previews** — need QtWebEngine, which Homebrew's `qt@5` no longer ships.

## Why the packaging is manual

CMake's built-in bundle step (`-DBUNDLE=ON`) fails in `fixup_bundle` on current macOS.
`build.sh` instead copies the Quassel libraries into each app, fixes the rpaths, runs Qt's
`macdeployqt`, generates the app icon from `pics/quassel.iconset` (normally done by that bundle
step), ad-hoc signs, and then verifies nothing references Homebrew or the build tree and the
icon is present.
