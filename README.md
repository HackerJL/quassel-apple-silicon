# Quassel for Apple Silicon

Native arm64 macOS apps of the [Quassel IRC](https://github.com/quassel/quassel) client, built
from the latest upstream source. The last official release (0.14.0, 2022) ships Intel-only Mac
builds that need Rosetta; upstream development continues but there are no new Mac packages.

> [!IMPORTANT]
> **This is an unofficial build.** It is not made, reviewed or endorsed by the Quassel IRC
> project. Please report problems [here](../../issues), not to the Quassel developers.
>
> **It was made with AI.** The build script, patches, icon and documentation in this repo were
> written by [Claude Code](https://claude.com/claude-code), Anthropic's AI coding assistant,
> working under the direction of the repo owner. See [How this was made](#how-this-was-made).

This repo holds only the build recipe, two small patches and an app icon. Quassel itself is
written by the Quassel team; its source is cloned into `src/` at build time (not committed).

## Download

Get the zip for the app you want from [Releases](../../releases):

| App | What it is |
| --- | --- |
| `Quassel Client.app` | Client only — connects to a Quassel core you run elsewhere |
| `Quassel.app` | All-in-one (monolithic) — connects to IRC directly |

Requires an Apple Silicon Mac (M1 or later) running **macOS 26 or newer**. The apps are
self-contained; nothing else needs to be installed.

### First launch: the "unidentified developer" warning

The apps are not signed with an Apple Developer ID or notarized by Apple, so macOS blocks them
the first time. To open one anyway:

1. Unzip it and drag it into `/Applications`.
2. Open it. macOS says it can't verify the app — click **Done**.
3. Go to **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next
   to the message about Quassel. Confirm with your password.

Or, in Terminal:

```sh
xattr -dr com.apple.quarantine "/Applications/Quassel Client.app"
```

Only do this if you trust this build: anything you allow this way runs without Apple's checks.
If you'd rather not, build it yourself from source (below) so nothing downloaded is executed.

### Replacing an existing Quassel

Drag the app into `/Applications`, replacing the matching old one (Client for Client,
all-in-one for all-in-one — they store settings under different names).

Settings are kept outside the app and are picked up unchanged:

- `~/Library/Preferences/org.quassel-irc.*.plist` — client settings, saved core logins
- `~/Library/Application Support/Quassel/` — data, certificates, and (all-in-one) the chat log database

The database schema is unchanged since 0.14.0, so switching back to the old app still works.
Back up `~/Library/Application Support/Quassel/` first anyway.

## Build from source

Requires an Apple Silicon Mac, Homebrew and the Xcode Command Line Tools.

```sh
./build.sh
```

Re-run any time to pull upstream changes and rebuild. Output lands in `dist/`. Both apps are
self-contained (Qt is bundled), so they keep working if Homebrew is removed.

The apps run on macOS 26 and newer. Homebrew's bottles target only the newest macOS, so
`build.sh` rebuilds the bundled libraries that would need more (glib, pcre2, libpng, md4c)
from the same sources with a macOS 26 deployment target, and fails if anything in the
bundles still needs a newer macOS. Set `MACOS_MIN` to change the target, e.g.
`MACOS_MIN=27.0 ./build.sh`.

To try changes without replacing a working build, build side by side:

```sh
DIST=dist-test BUILD=src/build-test ./build.sh
```

## Additions over upstream

`build.sh` applies everything in `patches/` to a clean upstream checkout.

- **Dark mode toolbar icons** (`patches/0001-auto-dark-icon-theme.patch`): with the icon theme
  set to "Automatic", Quassel uses Breeze Dark under a dark appearance and switches live.
- **Keep the Dock icon** (`patches/0002-keep-bundle-dock-icon-on-macos.patch`): upstream
  replaces the Dock icon with the classic flat icon at startup; on macOS this patch leaves the
  app bundle's icon in place.
- **macOS 26+ app icon** (`icon/Quassel.icon`): an Icon Composer icon with the ring and dot
  as separate glass layers, so macOS can render light, dark, clear and tinted variants
  (System Settings → Appearance → Icon & widget style). Compiling it needs full Xcode; without
  it `build.sh` falls back to the classic flat icon. `icon/make-layers.swift` regenerates the
  layer images from the geometry of Quassel's own logo.

## What's left out

- **Core binary** (`quasselcore`) — not built (`WANT_CORE=OFF`); the all-in-one app includes core functionality.
- **FiSH/Blowfish chat encryption** — needs QCA built against Qt 5; Homebrew's `qca` targets Qt 6.
  TLS connections to servers are unaffected.
- **Link previews** — need QtWebEngine, which Homebrew's `qt@5` no longer ships.

## Why the packaging is manual

CMake's built-in bundle step (`-DBUNDLE=ON`) fails in `fixup_bundle` on current macOS.
`build.sh` instead copies the Quassel libraries into each app, fixes the rpaths, runs Qt's
`macdeployqt`, bundles the libraries it misses, generates the app icon from
`pics/quassel.iconset` (normally done by that bundle step), ad-hoc signs, and then verifies that
nothing references Homebrew or the build tree, every library reference resolves inside the
bundle, nothing needs a newer macOS than the target, and the icon is present.

## How this was made

This repo was built by its owner working with [Claude Code](https://claude.com/claude-code),
Anthropic's AI coding assistant. Claude wrote the code and text in this repo — `build.sh`, both
patches, the icon and the script that draws it, and this README — and ran the builds and checks.
The owner decided what to build, reviewed the changes, and tested the results. Every commit
Claude contributed to carries a `Co-Authored-By: Claude` line, so `git log` shows exactly which
those are (currently all of them).

What that means for you:

- The patches are small and readable (`patches/`); the rest of the app is unmodified upstream
  Quassel, Qt and Homebrew libraries.
- Testing so far: the apps have been built and run on macOS 27 on Apple Silicon. Every binary
  is checked by `build.sh` to target macOS 26, but they have not yet been run on a macOS 26 Mac.
- There is no warranty (see below). Keep a backup of your Quassel settings.

## License

The build script, patches, icon files and documentation in this repo are licensed under the
GNU General Public License, version 2 or (at your option) any later version — see `LICENSE`.

The apps contain software by others, under their own licenses:

| Component | License |
| --- | --- |
| [Quassel IRC](https://github.com/quassel/quassel) | GPL-2.0 or GPL-3.0 |
| Breeze and Oxygen icon themes (KDE, shipped with Quassel) | LGPL-3.0-or-later |
| [Qt 5](https://www.qt.io) (from Homebrew `qt@5`) | LGPL-3.0 (and others, per module) |
| glib, gettext's libintl | LGPL-2.1-or-later |
| pcre2, libwebp, libjpeg-turbo, zstd | BSD-style |
| libpng | libpng-2.0 |
| md4c | MIT |
| FreeType | FreeType License |
| libtiff | libtiff License |
| xz (liblzma) | 0BSD |
| SQLite | Public domain |

Each release's notes name the exact upstream Quassel commit it was built from. The complete
source for a release is that commit plus this repo at the release tag (`build.sh` and
`patches/`); the libraries are unmodified upstream sources, as fetched by `build.sh` and
Homebrew.

This software is provided without any warranty, to the extent permitted by law.
