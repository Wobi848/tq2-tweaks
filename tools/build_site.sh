#!/usr/bin/env bash
# Builds the GitHub Pages site in docs/ from the browser pages and the game data dumps:
#   docs/index.html        data page (monsters & drops, item affixes), from tools/game_data.html
#   docs/loot_filter.html  loot filter editor, from TQ2Tweaks/loot_filter.html
#   docs/build_planner.html build planner with build_character.js and build_data.js (python3 tools/build_data.py)
# Only game data goes online: the affix dump without the ground items and without the player's own loot filter,
# the game data dump as it is. Run after a game patch (F9 and Shift+F9 in game), then commit docs/.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
mod="$root/TQ2Tweaks"
site="$root/docs"
game_version="${1:?usage: tools/build_site.sh <game version, e.g. 0.7.1>}"

for needed in "$mod/game_data.json" "$mod/affix_dump.txt" "$mod/build_data.js"; do
    [[ -f "$needed" ]] || { echo "Missing $needed: dump the game data first (see TQ2Tweaks/README.md)." >&2; exit 1; }
done

mkdir -p "$site"
# Same pages, local paths flattened; data_info.js (game version) is loaded before the page scripts.
add_info='s#<script src="\([^"]*\)affix_data.js"></script>#<script src="data_info.js"></script>\n&#'
sed -e 's#\.\./TQ2Tweaks/##g' -e "$add_info" "$root/tools/game_data.html" > "$site/index.html"
sed -e 's#https://wobi848.github.io/tq2-tweaks/#index.html#g' -e 's#Game data (online)#Game data#' -e "$add_info" "$mod/loot_filter.html" > "$site/loot_filter.html"
cp "$mod/affix_parse.js" "$mod/icons.js" "$mod/page_style.css" "$site/"
cp "$mod/build_planner.html" "$mod/build_character.js" "$mod/build_data.js" "$site/"

# Affix dump without the "GROUND ITEMS" section (what lay around the player), as the pages' data script.
python3 - "$mod/affix_dump.txt" "$site/affix_data.js" <<'PY'
import json, re, sys
text = open(sys.argv[1], encoding="utf-8").read()
text = re.sub(r"\nGROUND ITEMS \(\d+\)\n.*?(?=\nAFFIX POOLS|\nSOCKETABLES|\Z)", "\n", text, flags=re.S)
open(sys.argv[2], "w", encoding="utf-8").write(
    "window.TQ2_TWEAKS_DATA = { dump: " + json.dumps(text) + ", filter: null };\n")
PY
echo "window.TQ2_GAME_DATA = $(cat "$mod/game_data.json");" > "$site/game_data.js"
echo "window.TQ2_DATA_INFO = { gameVersion: \"$game_version\", built: \"$(date +%Y-%m-%d)\" };" > "$site/data_info.js"
touch "$site/.nojekyll"
echo "Site built in $site (game $game_version)."
