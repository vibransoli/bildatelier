#!/bin/bash
# Compatible with macOS' bundled Bash 3.2. No Homebrew or fixed SDK paths.
set -euo pipefail
TASK_SOURCE="$(cd "$(dirname "$0")" && pwd -P)"
TASK_OUTPUT="$TASK_SOURCE/Build"
TASK_MODE=native
while [ "$#" -gt 0 ]; do
    case "$1" in
        --universal) TASK_MODE=universal; shift ;;
        --output) [ "$#" -ge 2 ] || { echo "Nach --output fehlt der Zielordner." >&2; exit 2; }; TASK_OUTPUT="$2"; shift 2 ;;
        *) echo "Unbekannte Option: $1" >&2; exit 2 ;;
    esac
done
if [ "$(uname -s)" != Darwin ]; then echo "Dieses Paket benötigt macOS 13 oder neuer." >&2; exit 1; fi
TASK_OS="$(sw_vers -productVersion)"
if [ "${TASK_OS%%.*}" -lt 13 ]; then echo "Diese App benötigt mindestens macOS 13. Installiert: $TASK_OS" >&2; exit 1; fi
if ! TASK_COMPILER="$(xcrun --find swiftc 2>/dev/null)" || ! TASK_SDK="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null)"; then
    echo "Die Apple-Entwicklerwerkzeuge fehlen oder sind nicht eingerichtet."
    echo "Bitte im Terminal ausführen: xcode-select --install"
    echo "Nach abgeschlossener Installation dieses Skript erneut starten."
    echo "Bei vorhandener Xcode-Installation Xcode einmal öffnen und die Einrichtung abschließen."
    exit 1
fi
TASK_ARCH="$(uname -m)"
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" = 1 ]; then TASK_ARCH=arm64; fi
case "$TASK_ARCH" in arm64|x86_64) ;; *) echo "Nicht unterstützte Architektur: $TASK_ARCH" >&2; exit 1 ;; esac
TASK_TEMP="$(mktemp -d "${TMPDIR:-/tmp}/BildAtelier-build.XXXXXX")"
trap 'rm -rf "$TASK_TEMP"' EXIT
mkdir -p "$TASK_TEMP/Sources" "$TASK_OUTPUT"
TASK_OUTPUT="$(cd "$TASK_OUTPUT" && pwd -P)"
cp "$TASK_SOURCE"/Sources/*.swift "$TASK_TEMP/Sources/"
cat > "$TASK_TEMP/Probe.swift" <<'PROBE'
import AppKit
import SwiftUI
#if compiler(<5.7)
#error("Swift 5.7 oder neuer erforderlich. Bitte Apple Command Line Tools aktualisieren.")
#endif
typealias AtelierState<Value> = SwiftUI.State<Value>
final class ProbeModel: ObservableObject { @Published var value = "" }
struct ProbeView: View {
    @AtelierState(wrappedValue: false) private var active: Bool
    @ObservedObject var model: ProbeModel
    var body: some View { TextField("Probe", text: $model.value) }
}
PROBE
# Select an SDK compatible with the active compiler. Probe the active SDK first,
# then installed sibling SDKs, never a hard-coded release or user directory.
TASK_SDK_CANDIDATES=("$TASK_SDK")
for TASK_CANDIDATE in "$(dirname "$TASK_SDK")"/MacOSX*.sdk; do
    [ -d "$TASK_CANDIDATE" ] && TASK_SDK_CANDIDATES+=("$TASK_CANDIDATE")
done
TASK_FOUND=0
for TASK_CANDIDATE in "${TASK_SDK_CANDIDATES[@]}"; do
    if "$TASK_COMPILER" -swift-version 5 -typecheck -sdk "$TASK_CANDIDATE" \
        -target "$TASK_ARCH-apple-macosx13.0" -module-cache-path "$TASK_OUTPUT/ModuleCache-$TASK_ARCH" \
        "$TASK_TEMP/Probe.swift" > "$TASK_TEMP/sdk-check.log" 2>&1; then
        TASK_SDK="$TASK_CANDIDATE"; TASK_FOUND=1; break
    fi
done
if [ "$TASK_FOUND" != 1 ]; then
    cat "$TASK_TEMP/sdk-check.log"
    echo "Kein zum Swift-Compiler passendes macOS-SDK gefunden."
    echo "Bitte die Apple Command Line Tools bzw. Xcode aktualisieren und neu starten."
    exit 1
fi
TASK_ARCHS=("$TASK_ARCH")
if [ "$TASK_MODE" = universal ]; then TASK_ARCHS=(arm64 x86_64); fi
TASK_APP="$TASK_TEMP/Bild-Atelier.app"
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
echo "macOS: $TASK_OS · Architektur: $TASK_ARCH · Modus: $TASK_MODE"
echo "SDK: $TASK_SDK"
"$TASK_COMPILER" --version
TASK_BINARIES=()
for TASK_TARGET in "${TASK_ARCHS[@]}"; do
    echo "Kompiliere $TASK_TARGET …"
    "$TASK_COMPILER" -swift-version 5 -O -sdk "$TASK_SDK" -target "$TASK_TARGET-apple-macosx13.0" \
        -module-cache-path "$TASK_OUTPUT/ModuleCache-$TASK_TARGET" "$TASK_TEMP"/Sources/*.swift \
        -o "$TASK_TEMP/BildAtelier-$TASK_TARGET"
    TASK_BINARIES+=("$TASK_TEMP/BildAtelier-$TASK_TARGET")
done
if [ "$TASK_MODE" = universal ]; then
    xcrun lipo -create "${TASK_BINARIES[@]}" -output "$TASK_APP/Contents/MacOS/BildAtelier"
else
    cp "${TASK_BINARIES[0]}" "$TASK_APP/Contents/MacOS/BildAtelier"
fi
chmod 755 "$TASK_APP/Contents/MacOS/BildAtelier"
cp "$TASK_SOURCE/Info.plist" "$TASK_APP/Contents/Info.plist"
if [ -f "$TASK_SOURCE/Assets/AppIcon.icns" ]; then cp "$TASK_SOURCE/Assets/AppIcon.icns" "$TASK_APP/Contents/Resources/AppIcon.icns"; fi
# Remove metadata only from this newly generated temporary app, never the input.
xattr -cr "$TASK_APP"
codesign --force --sign - "$TASK_APP"
codesign --verify --deep --strict "$TASK_APP"
TASK_BACKUP=""
if [ -e "$TASK_OUTPUT/Bild-Atelier.app" ]; then
    TASK_BACKUP="$TASK_OUTPUT/Bild-Atelier-vorher-$(date +%Y%m%d-%H%M%S)-$$.app"
    mv "$TASK_OUTPUT/Bild-Atelier.app" "$TASK_BACKUP"
fi
if ! ditto --norsrc --noextattr "$TASK_APP" "$TASK_OUTPUT/Bild-Atelier.app"; then
    echo "Kopieren der neuen App fehlgeschlagen. Vorherige App: $TASK_BACKUP" >&2
    exit 1
fi
codesign --verify --deep --strict "$TASK_OUTPUT/Bild-Atelier.app"
echo "Fertig: $TASK_OUTPUT/Bild-Atelier.app"
