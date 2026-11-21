#!/usr/bin/env bash
# Installs UE4SS (from an unpacked release) and links the TQ2Tweaks mod folder into the game (for development).
# Usage: ./install.sh <folder of the unpacked UE4SS release, containing dwmapi.dll and ue4ss/ or UE4SS/>
# Recommended: "UE4SS for TQ2" from Nexus (nexusmods.com/titanquest2/mods/77); the GitHub release
# crashes TQ2 (UE 5.7) without the MemberVariableLayout.ini shipped there.
set -euo pipefail

GAME_BIN="${TQ2_BIN:-$HOME/.steam/steam/steamapps/common/Titan Quest II/TQ2/Binaries/Win64}"
MOD_SOURCE="$(cd "$(dirname "$0")" && pwd)/TQ2Tweaks"
UE4SS_RELEASE="${1:?Path to the unpacked UE4SS release is missing}"

# Find the UE4SS folder in the release and in the game, whether spelled "ue4ss" or "UE4SS".
find_ue4ss_dir() {
    find "$1" -maxdepth 1 -type d -iname ue4ss | head -1
}

RELEASE_DIR="$(find_ue4ss_dir "$UE4SS_RELEASE")"
GAME_UE4SS="$(find_ue4ss_dir "$GAME_BIN")"
if [ -z "$GAME_UE4SS" ]; then
    cp "$UE4SS_RELEASE/dwmapi.dll" "$GAME_BIN/"
    cp -r "$RELEASE_DIR" "$GAME_BIN/"
    GAME_UE4SS="$GAME_BIN/$(basename "$RELEASE_DIR")"
    echo "UE4SS installed: $GAME_UE4SS"
fi

ln -sfn "$MOD_SOURCE" "$GAME_UE4SS/Mods/TQ2Tweaks"

MODS_LIST="$GAME_UE4SS/Mods/mods.txt"
if ! grep -q "^TQ2Tweaks" "$MODS_LIST"; then
    # Insert above the built-in keybinds, which UE4SS requires to stay last.
    sed -i 's/^; Built-in keybinds/TQ2Tweaks : 1\n\n&/' "$MODS_LIST"
fi

MODS_JSON="$GAME_UE4SS/Mods/mods.json"
if [ -f "$MODS_JSON" ] && ! grep -q '"TQ2Tweaks"' "$MODS_JSON"; then
    python3 -I - "$MODS_JSON" <<'EOF'
import json, sys
path = sys.argv[1]
mods = json.load(open(path))
mods.append({"mod_name": "TQ2Tweaks", "mod_enabled": True})
json.dump(mods, open(path, "w"), indent=4)
EOF
fi
echo "TQ2Tweaks linked: $GAME_UE4SS/Mods/TQ2Tweaks -> $MOD_SOURCE"
