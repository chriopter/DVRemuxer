#!/usr/bin/env bash
set -Eeuo pipefail

# DVRemuxer Automatic - Non-interactive DV7 to DV8.1 converter
# Scans directory recursively and converts all DV7 files automatically

TARGET_DIR="${1:-.}"
JOB_NAME="${2:-$(basename "$TARGET_DIR")}"

# Optional ntfy notification settings (set environment variables or edit here)
NTFY_URL="${NTFY_URL:-}"  # e.g., https://ntfy.sh/mytopic
NTFY_TOKEN="${NTFY_TOKEN:-}"  # Optional bearer token

notify() {
  if [[ -n "$NTFY_URL" ]]; then
    if [[ -n "$NTFY_TOKEN" ]]; then
      curl -s -H "Authorization: Bearer $NTFY_TOKEN" -d "$1" "$NTFY_URL" >/dev/null 2>&1 || true
    else
      curl -s -d "$1" "$NTFY_URL" >/dev/null 2>&1 || true
    fi
  fi
}

echo "Starting DV7 scan in: $TARGET_DIR"
notify "🔍 Starting DV conversion: ${JOB_NAME}"

converted=0
failed=0

# Process all MKV files in directory tree
while IFS= read -r -d '' mkv; do
  [[ "$mkv" == *.DV8.mkv ]] && continue

  # Detect DV Profile 7
  dvProfile="$(mediainfo --ParseSpeed=0.0 --Inform='Video;%HDR_Format_Profile%' "$mkv" 2>/dev/null || true)"
  [[ ! "$dvProfile" =~ (dvhe\.07|07) ]] && continue

  dir="$(dirname "$mkv")"
  base="$(basename "$mkv" .mkv)"
  
  echo "Converting: $base"
  notify "🎬 Converting: ${base}"

  if mkvextract "$mkv" tracks 0:"$dir/$base.hevc" >/dev/null 2>&1 \
     && dovi_tool demux --el-only "$dir/$base.hevc" -e "$dir/$base.DV7.EL_RPU.hevc" >/dev/null 2>&1 \
     && dovi_tool -m 2 convert --discard "$dir/$base.hevc" -o "$dir/$base.dv8.hevc" >/dev/null 2>&1 \
     && mkvmerge -o "$dir/$base.DV8.mkv" -D "$mkv" "$dir/$base.dv8.hevc" --track-order 1:0 >/dev/null 2>&1
  then
    ((converted++))
    rm -f -- "$mkv" "$dir/$base.hevc" "$dir/$base.dv8.hevc"  # Keep .DV7.EL_RPU.hevc for restoration
    echo "  ✓ Success"
    notify "✅ Converted: ${base}"
  else
    ((failed++))
    rm -f -- "$dir/$base.hevc" "$dir/$base.dv8.hevc" "$dir/$base.DV7.EL_RPU.hevc"
    echo "  ✗ Failed"
    notify "❌ Failed: ${base}"
  fi
done < <(find "$TARGET_DIR" -type f -name '*.mkv' -print0)

echo ""
echo "Conversion complete: $converted succeeded, $failed failed"
notify "✅ Completed: ${JOB_NAME} (converted ${converted} file(s))"
exit 0