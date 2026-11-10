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

# Sparkle (mises à jour) : la bibliothèque voyage dans l'application.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
cp -R .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework "$SPARKLE"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/DeckPilot" 2>/dev/null || true

# macOS 26 découpe lui-même une icône pleine surface ; avant, l'icône doit déjà porter ses coins arrondis.
# L'icône arrondie est toujours embarquée : l'application la reprend pour le Dock sur les systèmes plus anciens.
if [[ "$(sw_vers -productVersion | cut -d. -f1)" -ge 26 ]]; then ICON=Resources/AppIcon.icns; else ICON=Resources/AppIcon-legacy.icns; fi
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp Resources/AppIcon-legacy.icns "$APP/Contents/Resources/AppIcon-legacy.icns"

# Langues : le français est la langue du code, les autres sont des tables de traduction.
cp -R Resources/*.lproj "$APP/Contents/Resources/"

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
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>SUFeedURL</key><string>https://raw.githubusercontent.com/ezeeFlop/DeckPilot/main/appcast.xml</string>
    <key>SUPublicEDKey</key><string>hII6oRXJerWXupIwDLmbCTLGsVj7rUOR0QGDzabuhzI=</string>
    <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
    <key>NSAppleEventsUsageDescription</key><string>DeckPilot règle le volume du Mac quand une touche le demande.</string>
</dict>
</plist>
PLIST

# Une identité de signature stable évite de redonner l'autorisation Accessibilité à chaque reconstruction.
DETECTED="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
IDENTITY="${DECKPILOT_SIGN_IDENTITY:-${DETECTED:--}}"
BASE=(--force --sign "$IDENTITY")
[[ "${DECKPILOT_HARDENED:-0}" == "1" ]] && BASE+=(--options runtime --timestamp)
# Signature de l'intérieur vers l'extérieur : les composants de Sparkle, puis la bibliothèque, puis l'application.
codesign "${BASE[@]}" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
codesign "${BASE[@]}" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
codesign "${BASE[@]}" "$SPARKLE/Versions/B/Autoupdate"
codesign "${BASE[@]}" "$SPARKLE/Versions/B/Updater.app"
codesign "${BASE[@]}" "$SPARKLE"
codesign "${BASE[@]}" --identifier com.spongetheory.deckpilot --entitlements Resources/DeckPilot.entitlements "$APP"
codesign --verify --deep --strict "$APP"
echo "Construit : $APP (version $VERSION)"

if [[ $INSTALL -eq 1 ]]; then
    rm -rf /Applications/DeckPilot.app
    cp -R "$APP" /Applications/DeckPilot.app
    echo "Installé : /Applications/DeckPilot.app"
fi
