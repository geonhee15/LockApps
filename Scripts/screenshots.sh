#!/bin/zsh
# Regenerates docs/screenshots/*.png for the README with sample data.
# Never touches real settings: locks go to a scratch folder via LOCKAPPS_DATA_DIR, nothing is persisted,
# and the lock engine stays off during these runs. Windows are rendered offscreen (no screen-recording permission);
# behind-window blur and Liquid Glass cannot render that way, so snapshot runs use RenderMode.flat (painted backdrop).
#   ./build.sh debug && Scripts/screenshots.sh
set -u
cd "$(dirname "$0")/.."
export LC_ALL=en_US.UTF-8
OUT="$PWD/docs/screenshots"; APP="$PWD/build/LockApps.app/Contents/MacOS/LockApps"
D="$(mktemp -d /tmp/lockapps-shots.XXXXXX)"
mkdir -p "$OUT"

shot() {  # shot <name> <delay> [extra env...]
  local name=$1 delay=$2; shift 2
  pkill -f "$APP" 2>/dev/null; sleep 0.3; rm -f "$OUT/$name.png"
  (env LOCKAPPS_DATA_DIR="$D" LOCKAPPS_DEBUG_SAMPLE_LOCKS=1 LOCKAPPS_DEBUG_PROTECTION=1 LOCKAPPS_DEBUG_LOGIN_ITEM=1 \
       LOCKAPPS_SNAPSHOT="$OUT/$name.png" LOCKAPPS_SNAPSHOT_DELAY="$delay" "$@" "$APP" > "$D/log-$name.txt" 2>&1 &)
  local waited=0
  while [[ ! -f "$OUT/$name.png" && $waited -lt 25 ]]; do sleep 0.5; waited=$((waited + 1)); done
  [[ -f "$OUT/$name.png" ]] && echo "✔ $name" || { echo "✖ $name"; tail -3 "$D/log-$name.txt"; }
  sleep 0.5
}

shot main-light 3 LOCKAPPS_APPEARANCE=light
shot main-dark 3 LOCKAPPS_APPEARANCE=dark
shot locked-filter 3 LOCKAPPS_APPEARANCE=light LOCKAPPS_DEBUG_FILTER=locked
shot set-password 3 LOCKAPPS_APPEARANCE=dark LOCKAPPS_DEBUG_SHEET=set:com.apple.TextEdit
shot remove-lock 3 LOCKAPPS_APPEARANCE=light LOCKAPPS_DEBUG_SHEET=remove:com.apple.Notes
shot settings 3 LOCKAPPS_APPEARANCE=dark LOCKAPPS_DEBUG_SHEET=settings
shot search 3 LOCKAPPS_APPEARANCE=light LOCKAPPS_DEBUG_SEARCH=안전
# Unlock prompt: the overlay is its own window, captured separately (compact frame instead of full screen).
rm -f "$OUT/unlock-prompt.png" "$OUT/unlock-prompt-light.png"
for variant in "unlock-prompt dark" "unlock-prompt-light light"; do
  set -- ${=variant}; name=$1; mode=$2
  pkill -f "$APP" 2>/dev/null; sleep 0.3
  (env LOCKAPPS_DATA_DIR="$D" LOCKAPPS_DEBUG_SAMPLE_LOCKS=1 LOCKAPPS_DEBUG_PROTECTION=1 LOCKAPPS_APPEARANCE=$mode \
       LOCKAPPS_DEBUG_PROMPT=com.apple.Notes LOCKAPPS_SNAPSHOT_PROMPT="$OUT/$name.png" LOCKAPPS_SNAPSHOT_DELAY=3 \
       "$APP" > "$D/log-$name.txt" 2>&1 &)
  waited=0; while [[ ! -f "$OUT/$name.png" && $waited -lt 25 ]]; do sleep 0.5; waited=$((waited + 1)); done
  [[ -f "$OUT/$name.png" ]] && echo "✔ $name" || { echo "✖ $name"; tail -3 "$D/log-$name.txt"; }
done
pkill -f "$APP" 2>/dev/null
python3 - "$OUT" <<'PY'
# Round the window corners (the offscreen render is a plain rectangle) and report sizes.
import sys, os
from PIL import Image, ImageDraw
out = sys.argv[1]
for name in sorted(os.listdir(out)):
    if not name.endswith(".png"): continue
    p = os.path.join(out, name); im = Image.open(p).convert("RGBA")
    radius = 44 if not name.startswith("unlock-prompt") else 32
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1], radius=radius, fill=255)
    im.putalpha(mask)
    im.save(p, optimize=True)
    print(f"{name}: {im.size[0]}x{im.size[1]}")
PY
rm -rf "$D"
