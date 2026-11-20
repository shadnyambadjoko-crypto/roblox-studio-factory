#!/usr/bin/env bash
# Installe Rojo, luau-lsp et les définitions de types Roblox dans .tools/
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .tools && cd .tools
[ -x rojo ] || { curl -sSLO https://github.com/rojo-rbx/rojo/releases/download/v7.4.4/rojo-7.4.4-linux-x86_64.zip && unzip -o -q rojo-7.4.4-linux-x86_64.zip && chmod +x rojo; }
[ -x luau-lsp ] || { curl -sSLO https://github.com/JohnnyMorganz/luau-lsp/releases/latest/download/luau-lsp-linux-x86_64.zip && unzip -o -q luau-lsp-linux-x86_64.zip && chmod +x luau-lsp; }
[ -f globalTypes.d.luau ] || curl -sSL -o globalTypes.d.luau https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau
rm -f ./*.zip
echo "Outils prêts : $(./rojo --version)"
