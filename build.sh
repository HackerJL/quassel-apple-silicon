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
UPSTREAM="https://github.com/quassel/quassel.git"

step() { printf '\n==> %s\n' "$*"; }

step "Installing build dependencies (Homebrew)"
brew install cmake ninja qt@5 boost

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

step "Configuring"
cmake -S "$SRC" -B "$BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$QT;/opt/homebrew" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DWANT_CORE=OFF \
    -DWITH_WEBENGINE=OFF \
    -DBUNDLE=ON \
    -DEMBED_DATA=ON

step "Compiling"
cmake --build "$BUILD"

# BUNDLE=ON makes the build produce .app bundles, but its install-time
# fixup_bundle step fails on current macOS, so instead of `cmake --install`
# the apps are packaged by hand and macdeployqt pulls in Qt.
step "Packaging apps into $DIST"
rm -rf "$DIST"
mkdir -p "$DIST"
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
    # Info.plist expects quassel.icns; upstream only generates it in the skipped bundle step.
    iconutil -c icns -o "$DIST/$APP.app/Contents/Resources/quassel.icns" "$SRC/pics/quassel.iconset"
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
done < <(find "$DIST" -type f \( -perm +111 -o -name '*.dylib' \) -print0)
for APP in "Quassel Client" "Quassel"; do
    file "$DIST/$APP.app/Contents/MacOS/$APP"
    if [ ! -s "$DIST/$APP.app/Contents/Resources/quassel.icns" ]; then
        echo "  missing app icon in: $APP.app"
        BAD=1
    fi
done
if [ "$BAD" -ne 0 ]; then
    echo "Verification failed: bundles reference files outside the app." >&2
    exit 1
fi

step "Done"
du -sh "$DIST"/*.app
