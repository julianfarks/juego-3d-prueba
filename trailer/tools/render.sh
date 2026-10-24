#!/bin/bash
# Renderiza el tráiler con el Movie Maker de Godot y lo monta.
#   trailer/tools/render.sh horizontal|horizontal_en|vertical|preview [--only=story,action,logo]
# Requiere: godot 4.3 en el PATH, xvfb-run, ffmpeg, python3.
set -e
cd "$(dirname "$0")/../.."
MODE=${1:-horizontal}; shift || true
OUT=${TRAILER_OUT:-/tmp/lm3d_trailer}
mkdir -p "$OUT"
SAVE="$HOME/.local/share/godot/app_userdata/Lawyer Mayhem 3D/lawyer_mayhem_save.json"
rm -f "$SAVE"*
case "$MODE" in
  horizontal) W=1920; H=1080; EXTRA="";;
  horizontal_en) W=1920; H=1080; EXTRA="--lang=en";;
  vertical)   W=1080; H=1920; EXTRA="--vertical";;
  preview)    W=640;  H=360;  EXTRA="";;
  preview_v)  W=360;  H=640;  EXTRA="--vertical";;
esac
godot --headless --path . --import >/dev/null 2>&1 || true
xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path . --rendering-driver opengl3 --resolution ${W}x${H} \
  --write-movie "$OUT/raw_$MODE.avi" --fixed-fps 30 -- --trailer $EXTRA "$@" > "$OUT/log_$MODE.txt" 2>&1
python3 trailer/tools/assemble.py "$OUT/log_$MODE.txt" "$OUT/raw_$MODE.avi" "$OUT/trailer_$MODE.mp4" \
  --music assets/audio/music_main.mp3 $( [ "${MODE#preview}" != "$MODE" ] && echo --preview )
echo "Listo: $OUT/trailer_$MODE.mp4"
