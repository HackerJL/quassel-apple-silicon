#!/usr/bin/env bash
# Build native Apple Silicon (arm64) Quassel apps from upstream source.
# Output: dist/Quassel Client.app and dist/Quassel.app (self-contained, ad-hoc signed).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/src"
# Override to build side by side without touching an existing build, e.g.
#   DIST=dist-test BUILD=src/build-test ./build.sh
BUILD="$(cd "$ROOT" && mkdir -p "${BUILD:-src/build}" && cd "${BUILD:-src/build}" && pwd)"
DIST="$ROOT/${DIST:-dist}"
QT="/opt/homebrew/opt/qt@5"
# Oldest macOS the apps run on. Homebrew's bottles only target the newest macOS,
# so libraries bundled from it that need more are rebuilt from source below.
MACOS_MIN="${MACOS_MIN:-26.0}"
DEPS="$ROOT/src/deps-$MACOS_MIN"
UPSTREAM="https://github.com/quassel/quassel.git"

step() { printf '\n==> %s\n' "$*"; }

step "Installing build dependencies (Homebrew)"
brew install cmake ninja meson pkgconf qt@5 boost

step "Fetching Quassel source"
if [ -d "$SRC/.git" ]; then
    # src/ is a managed upstream checkout: drop previously applied patches before updating.
    git -C "$SRC" checkout -- .
    git -C "$SRC" pull --ff-only
else
    git clone "$UPSTREAM" "$SRC"
fi
# Translations live in a submodule; the build fails without it.
git -C "$SRC" submodule update --init --depth 1

step "Applying patches"
for P in "$ROOT"/patches/*.patch; do
    [ -e "$P" ] || continue
    echo "  $(basename "$P")"
    git -C "$SRC" apply "$P"
done

step "Building libraries for macOS $MACOS_MIN"
# QtCore and QtGui link these from Homebrew. Building the same versions with a lower
# deployment target gives drop-in replacements, swapped into the bundles after macdeployqt.
export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
NCPU="$(sysctl -n hw.ncpu)"
mkdir -p "$DEPS/src"
# Unpacks the source Homebrew uses for a formula into $DEPS/src/<formula> and sets STAMP.
# Returns 1 when that exact source is already built. Runs in an `if`, so set -e is off here.
fetch_source() {
    local url sha tarball
    read -r url sha < <(brew info --json=v2 "$1" | python3 -c \
        'import json,sys; u=json.load(sys.stdin)["formulae"][0]["urls"]["stable"]; print(u["url"], u["checksum"])')
    STAMP="$DEPS/.built-$1-${sha:0:12}"
    [ -f "$STAMP" ] && return 1
    echo "  $1 ($(basename "$url"))"
    tarball="$DEPS/src/$1-$(basename "$url")"
    [ -f "$tarball" ] || curl -fsSL -o "$tarball" "$url" || exit 1
    echo "$sha  $tarball" | shasum -a 256 -c --status || { echo "checksum mismatch: $tarball" >&2; exit 1; }
    rm -rf "$DEPS/src/$1" && mkdir -p "$DEPS/src/$1"
    tar -xf "$tarball" -C "$DEPS/src/$1" --strip-components 1 || exit 1
}
if fetch_source pcre2; then
    (cd "$DEPS/src/pcre2" && ./configure --prefix="$DEPS" --disable-static --enable-pcre2-16 --enable-jit \
        && make -j"$NCPU" && make install) >/dev/null
    touch "$STAMP"
fi
if fetch_source libpng; then
    (cd "$DEPS/src/libpng" && ./configure --prefix="$DEPS" --disable-static \
        && make -j"$NCPU" && make install) >/dev/null
    touch "$STAMP"
fi
if fetch_source md4c; then
    (cd "$DEPS/src/md4c" && cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS" \
        && cmake --build build && cmake --install build) >/dev/null
    touch "$STAMP"
fi
# glib uses the pcre2 above and Homebrew's libintl, which already targets an old enough macOS.
if fetch_source glib; then
    (cd "$DEPS/src/glib" && PKG_CONFIG_PATH="$DEPS/lib/pkgconfig" \
        CPPFLAGS="-I/opt/homebrew/opt/gettext/include" LDFLAGS="-L/opt/homebrew/opt/gettext/lib" \
        meson setup build --prefix="$DEPS" --buildtype=release --default-library=shared \
            -Dintrospection=disabled -Dtests=false -Ddtrace=disabled -Dbsymbolic_functions=false \
        && meson compile -C build && meson install -C build) >/dev/null
    touch "$STAMP"
fi

step "Configuring"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$QT;/opt/homebrew" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN" \
    -DWANT_CORE=OFF \
    -DWITH_WEBENGINE=OFF \
    -DBUNDLE=ON \
    -DEMBED_DATA=ON

step "Compiling"
cmake --build "$BUILD"

# BUNDLE=ON makes the build produce .app bundles, but its install-time
# fixup_bundle step fails on current macOS, so instead of `cmake --install`
# the apps are packaged by hand and macdeployqt pulls in Qt.
step "Compiling app icon"
# icon/Quassel.icon is an Icon Composer icon with separate glyph layers, so macOS
# can render light, dark and tinted variants. Compiling it needs full Xcode;
# without it the apps get only the classic flat icon.
ICONCAR="$BUILD/appicon"
rm -rf "$ICONCAR"
mkdir -p "$ICONCAR"
XCODE_DEV="/Applications/Xcode.app/Contents/Developer"
if [ -d "$XCODE_DEV" ] && DEVELOPER_DIR="$XCODE_DEV" xcrun actool "$ROOT/icon/Quassel.icon" \
        --compile "$ICONCAR" --platform macosx --minimum-deployment-target "$MACOS_MIN" \
        --app-icon Quassel --output-partial-info-plist "$ICONCAR/partial.plist" >/dev/null; then
    echo "  Icon Composer icon compiled (light/dark/tinted)"
else
    echo "  Xcode's actool unavailable; using the classic icon only"
    rm -f "$ICONCAR/Assets.car"
fi

step "Packaging apps into $DIST"
# Remove only the bundles: Finder can recreate .DS_Store mid-delete if the folder is open.
mkdir -p "$DIST"
rm -rf "$DIST/Quassel Client.app" "$DIST/Quassel.app"
for APP in "Quassel Client" "Quassel"; do
    cp -R "$BUILD/$APP.app" "$DIST/"
    FW="$DIST/$APP.app/Contents/Frameworks"
    mkdir -p "$FW"
    LIBS=(common client uisupport qtui)
    [ "$APP" = "Quassel" ] && LIBS+=(core)
    for L in "${LIBS[@]}"; do
        cp -L "$BUILD"/lib/libquassel-"$L".*.*.*.dylib "$FW/"
    done
    EXE="$DIST/$APP.app/Contents/MacOS/$APP"
    install_name_tool -delete_rpath "$BUILD/lib" "$EXE"
    install_name_tool -add_rpath @executable_path/../Frameworks "$EXE"
    for f in "$FW"/libquassel-*.dylib; do
        install_name_tool -add_rpath @loader_path "$f" 2>/dev/null || true
    done
    "$QT/bin/macdeployqt" "$DIST/$APP.app" -always-overwrite
    # Replace Homebrew's copies with the ones built for $MACOS_MIN, linked the way macdeployqt links.
    for f in "$FW"/*.dylib; do
        name="$(basename "$f")"
        [ -f "$DEPS/lib/$name" ] || continue
        cp -L "$DEPS/lib/$name" "$f"
        chmod u+w "$f"
        install_name_tool -id "@executable_path/../Frameworks/$name" "$f" 2>/dev/null
        otool -L "$f" | tail -n +3 | awk '{print $1}' | while read -r dep; do
            case "$dep" in
                /usr/lib/*|/System/*|@executable_path/*) ;;
                *) install_name_tool -change "$dep" "@executable_path/../Frameworks/$(basename "$dep")" "$f" 2>/dev/null ;;
            esac
        done
    done
    # macdeployqt skips Homebrew libraries referenced through @rpath (libwebp -> libsharpyuv),
    # which leaves the WebP and TIFF image plugins unable to load. Bundle and relink those too.
    for f in "$FW"/*.dylib; do
        otool -L "$f" | tail -n +3 | awk '$1 ~ /^@rpath\// && $1 !~ /\/libquassel-/ {print $1}' | while read -r dep; do
            name="${dep#@rpath/}"
            if [ ! -e "$FW/$name" ]; then
                cp -L "/opt/homebrew/lib/$name" "$FW/"
                chmod u+w "$FW/$name"
                install_name_tool -id "@executable_path/../Frameworks/$name" "$FW/$name" 2>/dev/null
            fi
            install_name_tool -change "$dep" "@executable_path/../Frameworks/$name" "$f" 2>/dev/null
        done
    done
    plutil -replace LSMinimumSystemVersion -string "$MACOS_MIN" "$DIST/$APP.app/Contents/Info.plist"
    # Info.plist expects quassel.icns; upstream only generates it in the skipped bundle step.
    iconutil -c icns -o "$DIST/$APP.app/Contents/Resources/quassel.icns" "$SRC/pics/quassel.iconset"
    if [ -f "$ICONCAR/Assets.car" ]; then
        # CFBundleIconName (asset catalog) takes precedence over CFBundleIconFile on current macOS
        cp "$ICONCAR/Assets.car" "$DIST/$APP.app/Contents/Resources/"
        plutil -replace CFBundleIconName -string Quassel "$DIST/$APP.app/Contents/Info.plist"
    fi
    codesign --force --deep -s - "$DIST/$APP.app"
done

step "Verifying"
BAD=0
while IFS= read -r -d '' f; do
    id="$(otool -D "$f" 2>/dev/null | sed -n 2p)"
    if otool -L "$f" 2>/dev/null | tail -n +2 | grep -E '/opt/homebrew|/Users/' | grep -vF "$id"; then
        echo "  ^ external dependency in: $f"
        BAD=1
    fi
    # Every bundled reference must resolve to a file in the bundle.
    contents="${f%%/Contents/*}/Contents"
    while read -r dep; do
        case "$dep" in
            @executable_path/*) target="$contents/MacOS/${dep#@executable_path/}" ;;
            @rpath/*) target="$contents/Frameworks/${dep#@rpath/}" ;;
            *) continue ;;
        esac
        [ -e "$target" ] || { echo "  unresolved $dep in: $f"; BAD=1; }
    done < <(otool -L "$f" 2>/dev/null | tail -n +2 | awk '{print $1}')
done < <(find "$DIST" -type f \( -perm +111 -o -name '*.dylib' \) -print0)
# Every Mach-O must load on $MACOS_MIN (minos for LC_BUILD_VERSION, version for LC_VERSION_MIN).
while IFS= read -r -d '' f; do
    v="$(vtool -show-build "$f" 2>/dev/null | awk '$1 == "minos" || $1 == "version" {print $2; exit}')"
    [ -n "$v" ] || continue
    if [ "$(printf '%s\n' "$MACOS_MIN" "$v" | sort -V | tail -1)" != "$MACOS_MIN" ]; then
        echo "  needs macOS $v: $f"
        BAD=1
    fi
done < <(find "$DIST" -type f \( -perm +111 -o -name '*.dylib' \) -print0)
for APP in "Quassel Client" "Quassel"; do
    file "$DIST/$APP.app/Contents/MacOS/$APP"
    if [ ! -s "$DIST/$APP.app/Contents/Resources/quassel.icns" ]; then
        echo "  missing app icon in: $APP.app"
        BAD=1
    fi
done
if [ "$BAD" -ne 0 ]; then
    echo "Verification failed." >&2
    exit 1
fi

step "Done"
du -sh "$DIST"/*.app
