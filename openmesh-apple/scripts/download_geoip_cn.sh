#!/usr/bin/env bash
# Download geoip-cn.srs for the system VPN extension (vpn_extension_macx).
# Run from openmesh-apple: ./scripts/download_geoip_cn.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENMESH_APPLE="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST="$OPENMESH_APPLE/vpn_extension_macx/Resources/geoip-cn.srs"
URL="https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"

mkdir -p "$(dirname "$DEST")"
echo "Downloading geoip-cn.srs to $DEST ..."
curl -sL -o "$DEST" "$URL"
echo "Done. Size: $(wc -c < "$DEST") bytes."
