#!/usr/bin/env bash
# Copies all Titan Quest II save games into a timestamped folder.
# Usage: ./backup_saves.sh [label]     e.g. ./backup_saves.sh vor-crafting-test
# Restore: close the game, then copy the files of a backup folder back into the SaveGames folder below.
set -euo pipefail

SAVE_DIR="$HOME/.steam/steam/steamapps/compatdata/1154030/pfx/drive_c/users/steamuser/AppData/Local/TQ2/Saved/SaveGames"
BACKUP_ROOT="${TQ2_BACKUP_DIR:-$HOME/tq2-save-backups}"
LABEL="${1:-backup}"

if ps -eo args | grep -i "TQ2-Win64-Shipping" | grep -v grep | grep -qv "bash"; then
    echo "Warning: Titan Quest II is running - the backup may contain a half-written save game." >&2
fi

TARGET="$BACKUP_ROOT/$(date +%Y-%m-%d_%H-%M-%S)_$LABEL"
mkdir -p "$TARGET"
cp -a "$SAVE_DIR/." "$TARGET/"
echo "Backed up: $TARGET ($(du -sh "$TARGET" | cut -f1))"
