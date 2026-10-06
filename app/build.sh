#!/bin/bash
# Builds "Make Intro.app" into build/.
# usage: ./app/build.sh [--install]   (--install also copies the app to ~/Applications)
#
# Localization: UI strings in the code are English. Translations live in app/Localizable.xcstrings
# (a String Catalog, editable in Xcode). Each build syncs the catalog with the strings used in the
# code, warns about missing translations and compiles it into the app. This needs Xcode's
# xcstringstool; without it the app is built in English only.
set -euo pipefail

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$APP_DIR")"
BUILD_DIR="${ROOT_DIR}/build"
APP="${BUILD_DIR}/Make Intro.app"
RES="${APP}/Contents/Resources"
CATALOG="${APP_DIR}/Localizable.xcstrings"
LANGUAGES=(en de)

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "$RES"

# --- Compile (also extracts the localizable strings) ---
swiftc -parse-as-library -O -target arm64-apple-macos15 \
  -emit-localized-strings -emit-localized-strings-path "${WORK_DIR}/stringsdata" \
  "${APP_DIR}"/Sources/*.swift \
  -o "${APP}/Contents/MacOS/MakeIntro"

# --- Localization ---
if xcrun --find xcstringstool >/dev/null 2>&1; then
  [ -f "$CATALOG" ] || echo '{ "sourceLanguage" : "en", "strings" : {}, "version" : "1.0" }' > "$CATALOG"
  xcrun xcstringstool sync "$CATALOG" --stringsdata "${WORK_DIR}"/stringsdata/*.stringsdata
  xcrun xcstringstool compile "$CATALOG" --output-directory "$RES"
  for lang in "${LANGUAGES[@]}"; do mkdir -p "${RES}/${lang}.lproj"; done

  # Warn about strings that are used in the code but not translated yet
  python3 - "$CATALOG" "${LANGUAGES[@]:1}" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1]))
for lang in sys.argv[2:]:
    missing = [key for key, entry in catalog["strings"].items()
               if entry.get("extractionState") != "stale" and entry.get("shouldTranslate", True)
               and entry.get("localizations", {}).get(lang, {}).get("stringUnit", {}).get("state") != "translated"]
    for key in missing:
        print(f"Warning: missing {lang} translation: {key!r}", file=sys.stderr)
PY
else
  echo "Warning: xcstringstool not found (requires Xcode) – building without translations." >&2
fi

# --- License (MIT: the notice must accompany every copy, including the app) ---
cp "${ROOT_DIR}/LICENSE" "${RES}/LICENSE"

# --- Neutral app icon ---
ICONSET="${WORK_DIR}/AppIcon.iconset"
mkdir -p "$ICONSET"
swift "${APP_DIR}/AppIcon.swift" "${WORK_DIR}/icon.png"
for size in 16 32 128 256 512; do
  sips -z $size $size "${WORK_DIR}/icon.png" --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) "${WORK_DIR}/icon.png" --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "${RES}/AppIcon.icns"

# --- Info.plist ---
cat > "${APP}/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Make Intro</string>
  <key>CFBundleDisplayName</key><string>Make Intro</string>
  <key>CFBundleIdentifier</key><string>info.netzarbeiter.make-intro</string>
  <key>CFBundleExecutable</key><string>MakeIntro</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>NSHumanReadableCopyright</key><string>© 2026 Thomas Off</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key>
  <array>
    <string>en</string>
    <string>de</string>
  </array>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built: $APP"

if [ "${1:-}" = "--install" ]; then
  mkdir -p "${HOME}/Applications"
  rm -rf "${HOME}/Applications/Make Intro.app"
  cp -R "$APP" "${HOME}/Applications/"
  echo "Installed: ${HOME}/Applications/Make Intro.app"
fi
