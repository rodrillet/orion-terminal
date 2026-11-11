#!/bin/bash
# Compila o Orion Terminal (nativo: AppKit + SwiftUI + SwiftTerm) só com as Command Line Tools.
#   ./build.sh             → build/Orion Terminal.app
#   ./build.sh --instalar  → idem, copia para /Applications e liga ~/.local/bin/orion
#   ./build.sh --abrir     → compila e abre
#   ./build.sh --publico   → versão para distribuir: assinatura ad-hoc (sem certificado local),
#                            dist/Orion-Terminal-<versão>.zip + .zip.sha256 (o que o release e o atualizador usam)
set -euo pipefail
cd "$(dirname "$0")"

NOME="Orion Terminal"
VERSAO="0.7.0"
ID="com.rodrillet.orion-terminal"
INSTALAR=0 ABRIR=0 PUBLICO=0
for a in "$@"; do
  case "$a" in
    --instalar) INSTALAR=1 ;;
    --abrir) ABRIR=1 ;;
    --publico) PUBLICO=1 ;;
    *) echo "Opção desconhecida: $a"; exit 2 ;;
  esac
done
APP="build/$NOME.app"

echo "→ Compilando"
swift build -c release 2>&1 | grep -E "error|warning: unre|Compiling|Build complete" || true
BIN=$(swift build -c release --show-bin-path)
[[ -x "$BIN/OrionTerminal" ]] || { echo "✗ falhou"; exit 1; }

rm -rf "$APP" build/AppIcon.iconset
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/OrionTerminal" "$BIN/orion" "$APP/Contents/MacOS/"

echo "→ Ícone"
if [[ ! -f build/icone-1024.png || tools/icone.swift -nt build/icone-1024.png ]]; then
  swift tools/icone.swift build/icone-1024.png
fi
mkdir -p build/AppIcon.iconset
for t in 16 32 128 256 512; do
  sips -z $t $t build/icone-1024.png --out "build/AppIcon.iconset/icon_${t}x${t}.png" >/dev/null
  sips -z $((t * 2)) $((t * 2)) build/icone-1024.png --out "build/AppIcon.iconset/icon_${t}x${t}@2x.png" >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"

cat >"$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NOME</string>
  <key>CFBundleDisplayName</key><string>$NOME</string>
  <key>CFBundleIdentifier</key><string>$ID</string>
  <key>CFBundleExecutable</key><string>OrionTerminal</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSAO</string>
  <key>CFBundleVersion</key><string>$VERSAO</string>
  <key>CFBundleDevelopmentRegion</key><string>pt-BR</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>Orya Growth</string>
</dict>
</plist>
PLIST

if (( ! PUBLICO )) && security find-identity -p codesigning 2>/dev/null | grep -q '"Orion App Local"'; then
  echo "→ Assinando (Orion App Local)"
  codesign --force --deep --sign "Orion App Local" --identifier "$ID" "$APP"
else
  echo "→ Assinando (ad-hoc)"
  codesign --force --deep --sign - --identifier "$ID" "$APP"
fi

if (( PUBLICO )); then
  echo "→ Pacote para distribuir"
  # Garantia: nada pessoal dentro do app.
  if strings "$APP/Contents/MacOS/"* | grep -E -q "/Users/[a-z]|@gmail\.com|Orion App Local"; then
    echo "✗ Achei dado pessoal no binário:"; strings "$APP/Contents/MacOS/"* | grep -E "/Users/[a-z]|@gmail\.com|Orion App Local" | head; exit 1
  fi
  mkdir -p dist
  ZIP="dist/Orion-Terminal-$VERSAO.zip"
  rm -f "$ZIP" "$ZIP.sha256"
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  (cd dist && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
  echo "✓ $ZIP ($(du -h "$ZIP" | cut -f1))"
fi

if (( INSTALAR )); then
  echo "→ Instalando em /Applications"
  rm -rf "/Applications/$NOME.app"
  cp -R "$APP" /Applications/
  APP="/Applications/$NOME.app"
  mkdir -p "$HOME/.local/bin"
  ln -sf "$APP/Contents/MacOS/orion" "$HOME/.local/bin/orion"
  echo "✓ ~/.local/bin/orion"
fi
echo "✓ $APP"
if (( ABRIR )); then open "$APP"; fi
