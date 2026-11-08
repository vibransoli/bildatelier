#!/bin/bash
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd -P)"
TASK_DEST="$TASK_ROOT/Build"
if [ ! -w "$TASK_ROOT" ]; then TASK_DEST="$HOME/Desktop/Bild-Atelier-Build"; fi
mkdir -p "$TASK_DEST"
TASK_LOG="$TASK_DEST/Build-Protokoll.txt"
TASK_TEST="$(mktemp -d "${TMPDIR:-/tmp}/BildAtelier-check.XXXXXX")"
trap 'rm -rf "$TASK_TEST"' EXIT
trap 'printf "\nBuild oder Prüfung fehlgeschlagen. Protokoll: %s\n" "$TASK_LOG"; if [ -t 0 ]; then read -r -p "Enter zum Schließen … " || true; fi' ERR
{
    bash "$TASK_ROOT/Quellcode/build.sh" --output "$TASK_DEST" "$@"
    echo "Prüfe temporäre Testdateien (keine eigenen Fotos) …"
    # CLI checks run outside the app bundle, avoiding LaunchServices registration
    # in terminals without an attached graphical session.
    cp "$TASK_DEST/Bild-Atelier.app/Contents/MacOS/BildAtelier" "$TASK_TEST/BildAtelier-Check"
    "$TASK_TEST/BildAtelier-Check" --self-test --skip-video --demo
    echo "Build und Selbsttests erfolgreich."
} 2>&1 | tee "$TASK_LOG"
open "$TASK_DEST/Bild-Atelier.app"
