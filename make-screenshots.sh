#!/bin/bash
# Rigenera le immagini del README in docs/ con dati dimostrativi (nessun dato reale del Mac).
set -e
cd "$(dirname "$0")"
[ -d MenuStats.app ] || ./build.sh
./MenuStats.app/Contents/MacOS/MenuStats --screenshots docs
