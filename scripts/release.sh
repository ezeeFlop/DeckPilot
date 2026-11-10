#!/bin/zsh
# Fabrique la version distribuée : application universelle signée « Developer ID », image disque,
# notarisation par Apple, agrafage du ticket.
#
# Usage : scripts/release.sh             → build/DeckPilot-<version>.dmg et appcast.xml mis à jour
#         scripts/release.sh --publish   → en plus : version GitHub créée, puis appcast.xml commité et poussé
#
# La version vient du fichier VERSION. Les notes de version, si le fichier release-notes/<version>.md existe,
# sont montrées par Sparkle dans sa fenêtre de mise à jour et reprises dans la version GitHub.
# La signature des mises à jour utilise la clé EdDSA de Sparkle rangée dans le trousseau.
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

echo "==> Contrôle des traductions"
scripts/check-localizations.sh

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

echo "==> Flux de mises à jour (appcast.xml)"
REPO_URL="https://github.com/ezeeFlop/DeckPilot"
NOTES="release-notes/${VERSION}.md"
FEED="build/appcast"
rm -rf "$FEED"
mkdir -p "$FEED"
cp "$DMG" "$FEED/"
[[ -f appcast.xml ]] && cp appcast.xml "$FEED/appcast.xml"
[[ -f "$NOTES" ]] && cp "$NOTES" "$FEED/DeckPilot-${VERSION}.md"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --download-url-prefix "${REPO_URL}/releases/download/v${VERSION}/" \
    --link "$REPO_URL" --embed-release-notes -o "$FEED/appcast.xml" "$FEED"
cp "$FEED/appcast.xml" appcast.xml

echo "Prêt à distribuer : $DMG"
shasum -a 256 "$DMG"

if [[ "${1:-}" == "--publish" ]]; then
    echo "==> Publication sur GitHub"
    # L'image disque d'abord, le flux ensuite : le flux ne doit jamais annoncer un fichier absent.
    if [[ -f "$NOTES" ]]; then
        gh release create "v${VERSION}" "$DMG" --title "DeckPilot ${VERSION}" --notes-file "$NOTES"
    else
        gh release create "v${VERSION}" "$DMG" --title "DeckPilot ${VERSION}" --generate-notes
    fi
    git add appcast.xml
    git commit -m "Flux de mises à jour : version ${VERSION}"
    git push
fi
