#!/usr/bin/env bash
# Run the Windows Godot 4.7 editor binary on this repo from WSL.
#   tools/godot.sh import            re-import changed assets
#   tools/godot.sh script <res path> run a SceneTree tool script headless
#   tools/godot.sh reimport <glob>   force re-import of matching assets
#   tools/godot.sh <args...>         anything else is passed through
G="${GODOT:-/mnt/c/Users/jlion/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WP="$(wslpath -w "$ROOT")"
case "$1" in
  import) exec "$G" --headless --path "$WP" --import ;;
  script) exec "$G" --headless --path "$WP" --script "$2" "${@:3}" ;;
  reimport)
    shift
    for pat in "$@"; do
      for f in $ROOT/$pat; do
        base="$(basename "$f")"
        rm -f "$ROOT"/.godot/imported/"$base"-*
        # dropping uid/dest lines forces Godot to treat the asset as changed
        [ -f "$f.import" ] && sed -i '/^\(dest_files\|source_file\|valid\)/d' "$f.import"
      done
    done
    exec "$G" --headless --path "$WP" --import ;;
  *) exec "$G" --path "$WP" "$@" ;;
esac
