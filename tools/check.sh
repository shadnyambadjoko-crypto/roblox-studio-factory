#!/usr/bin/env bash
# Usage : bash tools/check.sh games/<jeu>
# Construit le .rbxlx et vérifie les types Luau. Échoue s'il y a la moindre erreur.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$(cd "$1" && pwd)"
T="$ROOT/.tools"
[ -x "$T/rojo" ] || bash "$ROOT/tools/setup.sh"
cd "$GAME"
NAME=$(python3 -c "import json;print(json.load(open('default.project.json'))['name'])")
"$T/rojo" build default.project.json -o "$NAME.rbxlx"
"$T/rojo" sourcemap default.project.json -o /tmp/sourcemap.json >/dev/null
OUT=$("$T/luau-lsp" analyze --definitions="$T/globalTypes.d.luau" --sourcemap=/tmp/sourcemap.json src 2>&1 | grep -vE '^\[(INFO|WARN)\]' || true)
if [ -n "$OUT" ]; then echo "$OUT"; echo "❌ Erreurs dans $NAME"; exit 1; fi
echo "✅ $NAME : construit et 0 erreur de types"
