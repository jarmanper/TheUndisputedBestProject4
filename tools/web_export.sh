#!/usr/bin/env bash
# Build the Web export with web-sized assets.
#
# WHY
#   The desktop asset set does not fit in a browser. Measured on 2026-10-29 with
#   the textures as imported for desktop (2048 px) the Web export was:
#       index.pck   231 MB   (178 MB of it compressed textures)
#       index.wasm   40 MB
#       total       271 MB
#   Two playtesters on the GitHub Pages build never got the game to start.
#
#   Godot has no per-preset texture size, so this script temporarily rewrites
#   the texture and model .import files, re-imports, exports, and then puts the
#   .import files back exactly as they were. Nothing in the repo changes: the
#   desktop/editor asset quality is untouched.
#
# USAGE
#   tools/web_export.sh [output_html]            # default build/web/index.html
#   WEB_TEXTURE_LIMIT=256 tools/web_export.sh    # smaller still
#   WEB_KEEP_LODS=1 tools/web_export.sh          # keep mesh LODs (bigger)
#   GODOT=/path/to/godot tools/web_export.sh     # pick the binary
#
# Requires the Web export templates for the matching Godot version.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/web/index.html}"
GODOT="${GODOT:-godot}"
TEX_LIMIT="${WEB_TEXTURE_LIMIT:-512}"
KEEP_LODS="${WEB_KEEP_LODS:-0}"

# The project path Godot wants. On WSL with a Windows Godot binary that is a
# Windows path; everywhere else it is just $ROOT.
if [[ "$GODOT" == *.exe ]] && command -v wslpath >/dev/null 2>&1; then
	GPATH="$(wslpath -w "$ROOT")"
	OUT_ARG="$(wslpath -w "$OUT" 2>/dev/null || echo "$OUT")"
else
	GPATH="$ROOT"
	OUT_ARG="$OUT"
fi

BACKUP="$(mktemp -d)"
restore() {
	if [ -d "$BACKUP/files" ]; then
		echo "web_export: restoring .import files"
		( cd "$BACKUP/files" && find . -type f -print0 | while IFS= read -r -d '' f; do
			cp "$f" "$ROOT/${f#./}"
		done )
	fi
	rm -rf "$BACKUP"
}
trap restore EXIT

mkdir -p "$BACKUP/files" "$(dirname "$OUT")"

echo "web_export: patching import settings (textures -> ${TEX_LIMIT}px, lods_kept=${KEEP_LODS})"
python3 - "$ROOT" "$BACKUP/files" "$TEX_LIMIT" "$KEEP_LODS" <<'PY'
import os, re, shutil, sys

root, backup, limit, keep_lods = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"

def edit(path, subs):
	with open(path, "r", encoding="utf-8") as fh:
		src = fh.read()
	out = src
	for pattern, value in subs:
		out = re.sub(pattern, value, out, flags=re.M)
	if out == src:
		return False
	rel = os.path.relpath(path, root)
	dest = os.path.join(backup, rel)
	os.makedirs(os.path.dirname(dest), exist_ok=True)
	shutil.copy2(path, dest)
	with open(path, "w", encoding="utf-8") as fh:
		fh.write(out)
	return True

tex = mesh = 0
for folder, _dirs, files in os.walk(os.path.join(root, "assets")):
	for name in files:
		if not name.endswith(".import"):
			continue
		path = os.path.join(folder, name)
		if name.endswith(".png.import"):
			# size_limit caps the longest side at import time. Mip chains and
			# VRAM compression are unchanged, so nothing else has to know.
			tex += edit(path, [(r"^process/size_limit=\d+$", "process/size_limit=" + limit)])
		elif name.endswith(".glb.import") or name.endswith(".gltf.import"):
			subs = [(r"^meshes/create_shadow_meshes=.*$", "meshes/create_shadow_meshes=false")]
			if not keep_lods:
				subs.append((r"^meshes/generate_lods=.*$", "meshes/generate_lods=false"))
			mesh += edit(path, subs)
print("web_export: patched %d texture and %d model imports" % (tex, mesh))
PY

echo "web_export: re-importing"
"$GODOT" --headless --path "$GPATH" --import

echo "web_export: exporting Web release to $OUT"
"$GODOT" --headless --path "$GPATH" --export-release "Web" "$OUT_ARG"

echo "web_export: payload"
du -b "$(dirname "$OUT")"/* 2>/dev/null | sort -rn | head -10 || ls -la "$(dirname "$OUT")"
