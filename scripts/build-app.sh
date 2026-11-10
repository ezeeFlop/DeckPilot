#!/bin/zsh
# Construit build/DeckPilot.app à partir du paquet Swift.
#
# Usage : scripts/build-app.sh [--install] [--universal]
#   --install    copie l'application dans /Applications après la construction
#   --universal  construit pour Apple Silicon et Intel (utilisé pour les versions distribuées)
#
# Variables : DECKPILOT_SIGN_IDENTITY  identité de signature (par défaut : « Apple Development » si présente, sinon ad hoc)
#             DECKPILOT_HARDENED=1     active le runtime renforcé et l'horodatage (exigés par la notarisation)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(cat VERSION)"
INSTALL=0
ARCHS=()
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
        *) echo "option inconnue : $arg" >&2; exit 2 ;;
    esac
done

swift build -c release --product DeckPilot "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/DeckPilot"
APP="build/DeckPilot.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DeckPilot"

# macOS 26 découpe lui-même une icône pleine surface ; avant, l'icône doit déjà porter ses coins arrondis.
# L'icône arrondie est toujours embarquée : l'application la reprend pour le Dock sur les systèmes plus anciens.
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ]]; then ICON=Resources/AppIcon.icns; else ICON=Resources/AppIcon-legacy.icns; fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon-legacy.icns "$APP/Contents/Resources/AppIcon-legacy.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DeckPilot</string>
    <key>CFBundleDisplayName</key><string>DeckPilot</string>
    <key>CFBundleIdentifier</key><string>com.spongetheory.deckpilot</string>
    <key>CFBundleExecutable</key><string>DeckPilot</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleEventsUsageDescription</key><string>DeckPilot règle le volume du Mac quand une touche le demande.</string>
</dict>
</plist>
PLIST

# Une identité de signature stable évite de redonner l'autorisation Accessibilité à chaque reconstruction.
DETECTED="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
IDENTITY="${DECKPILOT_SIGN_IDENTITY:-${DETECTED:--}}"
SIGN_OPTIONS=(--force --sign "$IDENTITY" --identifier com.spongetheory.deckpilot --entitlements Resources/DeckPilot.entitlements)
[[ "${DECKPILOT_HARDENED:-0}" == "1" ]] && SIGN_OPTIONS+=(--options runtime --timestamp)
codesign "${SIGN_OPTIONS[@]}" "$APP"
echo "Construit : $APP (version $VERSION)"

if [[ $INSTALL -eq 1 ]]; then
    rm -rf /Applications/DeckPilot.app
    cp -R "$APP" /Applications/DeckPilot.app
    echo "Installé : /Applications/DeckPilot.app"
fi
