#!/bin/bash
# Instala (ou atualiza) o Orion Terminal a partir do último release no GitHub.
#
#   curl -fsSL https://raw.githubusercontent.com/rodrillet/orion-terminal/main/install.sh | bash
#
# O que faz: baixa o .zip do release, confere o SHA-256 publicado junto, instala em /Applications
# (ou ~/Applications, se /Applications não for gravável), tira a quarentena do macOS e liga o
# comando `orion` em ~/.local/bin. Não pede senha e não instala nada além disso.
set -euo pipefail

REPO="rodrillet/orion-terminal"
NOME="Orion Terminal"

azul=$'\033[34m'; verde=$'\033[32m'; vermelho=$'\033[31m'; cinza=$'\033[2m'; fim=$'\033[0m'
passo() { printf "%s→%s %s\n" "$azul" "$fim" "$1"; }
ok() { printf "%s✓%s %s\n" "$verde" "$fim" "$1"; }
erro() { printf "%s✗ %s%s\n" "$vermelho" "$1" "$fim" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || erro "O Orion Terminal é um app de Mac."
[[ "$(uname -m)" == "arm64" ]] || erro "Por enquanto o Orion Terminal roda só em Mac com Apple Silicon (M1 ou mais novo)."
maior=$(sw_vers -productVersion | cut -d. -f1)
(( maior >= 15 )) || erro "Precisa do macOS 15 (Sequoia) ou mais novo. Este Mac está no $(sw_vers -productVersion)."

passo "Procurando a última versão"
json=$(curl -fsSL -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/releases/latest") \
  || erro "Não consegui falar com o GitHub."
url_zip=$(printf '%s' "$json" | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
url_sha=$(printf '%s' "$json" | grep -o '"browser_download_url": *"[^"]*\.zip\.sha256"' | head -1 | sed 's/.*"\(https[^"]*\)"/\1/')
versao=$(printf '%s' "$json" | grep -o '"tag_name": *"[^"]*"' | head -1 | sed 's/.*"v\{0,1\}\([^"]*\)"/\1/')
[[ -n "$url_zip" && -n "$url_sha" ]] || erro "O último release não tem o pacote do app."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

passo "Baixando o Orion Terminal $versao"
curl -fL --progress-bar "$url_zip" -o "$tmp/app.zip" || erro "Falhou o download."
curl -fsSL "$url_sha" -o "$tmp/app.zip.sha256" || erro "Falhou o download da soma de verificação."
esperado=$(awk '{print $1}' "$tmp/app.zip.sha256")
real=$(shasum -a 256 "$tmp/app.zip" | awk '{print $1}')
[[ "$esperado" == "$real" ]] || erro "O arquivo baixado não confere com o SHA-256 do release. Nada foi instalado."
ok "Arquivo conferido (SHA-256)"

ditto -x -k "$tmp/app.zip" "$tmp/novo"
[[ -d "$tmp/novo/$NOME.app" ]] || erro "Pacote inesperado."

destino_dir="/Applications"
[[ -w "$destino_dir" ]] || { destino_dir="$HOME/Applications"; mkdir -p "$destino_dir"; }
destino="$destino_dir/$NOME.app"

if pgrep -xq OrionTerminal; then
  passo "Fechando o Orion Terminal aberto (as abas voltam ao reabrir)"
  osascript -e "quit app \"$NOME\"" >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do pgrep -xq OrionTerminal || break; sleep 0.5; done
  pgrep -xq OrionTerminal && erro "O app ainda está aberto (talvez esperando confirmação). Feche e rode de novo."
fi

passo "Instalando em $destino_dir"
rm -rf "$destino.antigo"
[[ -d "$destino" ]] && mv "$destino" "$destino.antigo"
if mv "$tmp/novo/$NOME.app" "$destino"; then
  rm -rf "$destino.antigo"
else
  [[ -d "$destino.antigo" ]] && mv "$destino.antigo" "$destino"
  erro "Não consegui copiar para $destino_dir."
fi
xattr -dr com.apple.quarantine "$destino" 2>/dev/null || true

mkdir -p "$HOME/.local/bin"
ln -sf "$destino/Contents/MacOS/orion" "$HOME/.local/bin/orion"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ok "Comando orion pronto" ;;
  *) ok "Comando orion em ~/.local/bin/orion"
     printf "  %sPara usar em qualquer terminal, adicione ao ~/.zshrc:%s export PATH=\"\$HOME/.local/bin:\$PATH\"\n" "$cinza" "$fim" ;;
esac

ok "Orion Terminal $versao instalado"
printf "  %sAs próximas versões chegam sozinhas pelo próprio app.%s\n" "$cinza" "$fim"
open "$destino"
