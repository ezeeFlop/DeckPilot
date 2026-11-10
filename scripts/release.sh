#!/bin/zsh
# Fabrique la version distribuée : application universelle signée « Developer ID », image disque,
# notarisation par Apple, agrafage du ticket.
#
# Usage : scripts/release.sh            → build/DeckPilot-<version>.dmg
#
# Identifiants de notarisation, lus dans l'environnement ou dans un fichier .env à la racine (jamais commité) :
#   APPLE_ID        adresse du compte développeur Apple
#   APPLE_PASSWORD  mot de passe d'application (appleid.apple.com › Connexion et sécurité)
#   TEAM_ID         identifiant d'équipe, 10 caractères
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -f .env ]]; then
    set -a
    source .env
    set +a
fi
for name in APPLE_ID APPLE_PASSWORD TEAM_ID; do
    [[ -n "${(P)name:-}" ]] || { echo "Variable manquante : $name (voir l'en-tête de ce script)" >&2; exit 1; }
done

IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
[[ -n "$IDENTITY" ]] || { echo "Aucun certificat « Developer ID Application » dans le trousseau." >&2; exit 1; }

VERSION="$(cat VERSION)"
APP="build/DeckPilot.app"
DMG="build/DeckPilot-${VERSION}.dmg"
STAGING="build/dmg-staging"

echo "==> Construction et signature (Developer ID, runtime renforcé)"
DECKPILOT_SIGN_IDENTITY="$IDENTITY" DECKPILOT_HARDENED=1 scripts/build-app.sh --universal
codesign --verify --strict --verbose=2 "$APP"

echo "==> Image disque"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/DeckPilot.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "DeckPilot" -srcfolder "$STAGING" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

echo "==> Notarisation (quelques minutes)"
xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID" --password "$APPLE_PASSWORD" --team-id "$TEAM_ID" --wait

echo "==> Agrafage du ticket"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "Prêt à distribuer : $DMG"
shasum -a 256 "$DMG"
