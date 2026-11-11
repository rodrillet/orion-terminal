# Imagem de capa

`og.html` gera `../og-image.png` (1280×640, a usada no GitHub) e `../og-image@2x.png`.

```bash
cd docs/og
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --hide-scrollbars \
  --force-device-scale-factor=2 --window-size=1280,640 --screenshot=/tmp/og.png "file://$PWD/og.html"
sips -Z 1280 /tmp/og.png --out ../og-image.png && cp /tmp/og.png ../og-image@2x.png
```

Fonte: Instrument Sans (SIL Open Font License 1.1, ver `OFL-Instrument-Sans.txt`), usada só nesta imagem.
