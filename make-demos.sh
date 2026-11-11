#!/bin/bash
# Genera le animazioni WebP del README in docs/ (serve img2webp: brew install webp).
# Nessuna registrazione dello schermo: l'app disegna fuori schermo, con dati dimostrativi,
# le scene animate; img2webp salva solo le parti che cambiano tra un fotogramma e l'altro.
set -e
cd "$(dirname "$0")"
[ -d MenuStats.app ] || ./build.sh
rm -rf build/demo; mkdir -p build/demo docs
./MenuStats.app/Contents/MacOS/MenuStats --gifs build/demo
for d in build/demo/*/; do
  name=$(basename "$d")
  img2webp -loop 0 -d 100 -mixed -q 82 -m 5 "$d"*.png -o "docs/$name.webp" >/dev/null 2>&1
  echo "docs/$name.webp $(du -h "docs/$name.webp" | cut -f1)"
done
rm -rf build/demo
