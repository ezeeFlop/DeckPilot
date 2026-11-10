#!/bin/zsh
# Vérifie que chaque texte traduisible de l'application a sa traduction dans chaque langue de Resources/*.lproj
# (sauf le français, langue du code). Échoue en listant ce qui manque ou ce qui ne sert plus.
set -euo pipefail
cd "$(dirname "$0")/.."
KEYS="$(mktemp)"
scripts/localized-keys.sh > "$KEYS"
STATUS=0
for table in Resources/*.lproj/Localizable.strings; do
    [[ "$table" == Resources/fr.lproj/* ]] && continue
    plutil -lint -s "$table"
    python3 - "$KEYS" "$table" <<'PY' || STATUS=1
import json, plistlib, subprocess, sys
wanted = {json.loads(line) for line in open(sys.argv[1]) if line.strip()}
xml = subprocess.run(["plutil", "-convert", "xml1", "-o", "-", sys.argv[2]], capture_output=True, check=True).stdout
have = set(plistlib.loads(xml))
missing, unused = sorted(wanted - have), sorted(have - wanted)
for key in missing: print(f"{sys.argv[2]} : traduction manquante pour {key!r}")
for key in unused: print(f"{sys.argv[2]} : traduction inutilisée {key!r}")
sys.exit(1 if missing or unused else 0)
PY
done
rm -f "$KEYS"
[[ $STATUS -eq 0 ]] && echo "Traductions complètes."
exit $STATUS
