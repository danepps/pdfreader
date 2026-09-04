#!/bin/zsh
# Build Folio.app into ./build. Usage: ./build.sh [--run] [--debug]
set -euo pipefail
ROOT="${0:A:h}"
CONFIG=release
RUN=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN=1 ;;
    --debug) CONFIG=debug ;;
  esac
done

swift build -c "$CONFIG" --package-path "$ROOT"

APP="$ROOT/build/Folio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/$CONFIG/Folio" "$APP/Contents/MacOS/Folio"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [[ -f "$ROOT/Support/Folio.icns" ]]; then
  cp "$ROOT/Support/Folio.icns" "$APP/Contents/Resources/Folio.icns"
fi
if [[ -f "$ROOT/Support/Assets.car" ]]; then
  cp "$ROOT/Support/Assets.car" "$APP/Contents/Resources/Assets.car"
fi
codesign --force --sign - "$APP" >/dev/null 2>&1
echo "Built $APP"

if [[ $RUN -eq 1 ]]; then
  open "$APP"
fi
