#!/bin/bash
# Publica uma versão nova no GitHub. Todos os apps instalados percebem sozinhos (consultam o
# release mais novo ao abrir, ao voltar para a frente e a cada hora) e se atualizam.
#
#   1. Suba o número em VERSAO no build.sh
#   2. Escreva as novidades em notas/<versão>.md
#   3. ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

VERSAO=$(grep -m1 '^VERSAO=' build.sh | cut -d'"' -f2)
NOTAS="notas/$VERSAO.md"
[[ -f "$NOTAS" ]] || { echo "✗ Escreva as novidades em $NOTAS"; exit 1; }
git diff --quiet && git diff --cached --quiet || { echo "✗ Há mudanças sem commit. Faça o commit antes."; exit 1; }
git rev-parse "v$VERSAO" >/dev/null 2>&1 && { echo "✗ A tag v$VERSAO já existe. Suba a versão no build.sh."; exit 1; }

./build.sh --publico
ZIP="dist/Orion-Terminal-$VERSAO.zip"

git tag -a "v$VERSAO" -m "Orion Terminal $VERSAO"
git push origin HEAD "v$VERSAO"
gh release create "v$VERSAO" "$ZIP" "$ZIP.sha256" --title "Orion Terminal $VERSAO" --notes-file "$NOTAS"
echo "✓ v$VERSAO publicada — os apps instalados vão atualizar sozinhos."
