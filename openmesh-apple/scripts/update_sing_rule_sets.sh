#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENMESH_APPLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_DIR="${1:-$OPENMESH_APPLE_DIR/shared/rule-set}"

mkdir -p "$DEST_DIR"

download_one() {
  local out="$1"
  shift
  local urls=("$@")
  local tmp
  tmp="$(mktemp)"
  local ok=0

  for url in "${urls[@]}"; do
    echo "Trying: $url"
    if curl -4 --http1.1 -fL --connect-timeout 15 --retry 5 --retry-all-errors --retry-delay 1 -o "$tmp" "$url"; then
      ok=1
      break
    fi
  done

  if [[ "$ok" != "1" ]]; then
    rm -f "$tmp"
    echo "Failed to download: $out" >&2
    exit 1
  fi

  mv "$tmp" "$out"
  echo "Saved: $out ($(wc -c < "$out") bytes)"
  shasum -a 256 "$out"
}

download_one \
  "$DEST_DIR/geoip-cn.srs" \
  "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs" \
  "https://ghproxy.com/https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs" \
  "https://cdn.jsdelivr.net/gh/SagerNet/sing-geoip@rule-set/geoip-cn.srs"

download_one \
  "$DEST_DIR/geosite-geolocation-cn.srs" \
  "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs" \
  "https://ghproxy.com/https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-geolocation-cn.srs" \
  "https://cdn.jsdelivr.net/gh/SagerNet/sing-geosite@rule-set/geosite-geolocation-cn.srs"

echo ""
echo "Done."
echo "Rule-set snapshot directory: $DEST_DIR"
