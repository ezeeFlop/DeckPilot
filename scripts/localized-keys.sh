#!/bin/zsh
# Liste, une par ligne, les chaînes que le compilateur considère comme traduisibles dans l'application.
# Usage : scripts/localized-keys.sh
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
swift build --build-path "$OUT/build" -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null
python3 - "$OUT" <<'PY'
import glob, json, sys
keys = set()
for path in glob.glob(sys.argv[1] + "/*.stringsdata"):
    for items in json.load(open(path)).get("tables", {}).values():
        keys.update(item["key"] for item in items)
for key in sorted(k for k in keys if k):
    print(json.dumps(key, ensure_ascii=False))
PY
rm -rf "$OUT"
