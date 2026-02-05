#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENMESH_APPLE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_GROUP_DIR_DEFAULT="$HOME/Library/Group Containers/group.com.meshnetprotocol.OpenMesh"
APP_GROUP_DIR="${APP_GROUP_DIR:-$APP_GROUP_DIR_DEFAULT}"
PROFILE_SRC="${PROFILE_SRC:-$OPENMESH_APPLE_DIR/MeshFluxMac/default_profile.json}"
RULESET_SRC_DIR="${RULESET_SRC_DIR:-$OPENMESH_APPLE_DIR/shared/rule-set}"
PROFILE_DST_NAME="${PROFILE_DST_NAME:-config_1.json}"
OVERWRITE="${OVERWRITE:-0}"

CONFIG_DIR="$APP_GROUP_DIR/configs"
RULESET_DST_DIR="$APP_GROUP_DIR/rule-set"
PROFILE_DST="$CONFIG_DIR/$PROFILE_DST_NAME"

mkdir -p "$CONFIG_DIR" "$RULESET_DST_DIR"

if [[ ! -f "$PROFILE_SRC" ]]; then
  echo "Profile source not found: $PROFILE_SRC" >&2
  exit 1
fi

if [[ -f "$PROFILE_DST" && "$OVERWRITE" != "1" ]]; then
  echo "Target profile exists: $PROFILE_DST"
  echo "Set OVERWRITE=1 to replace it."
  exit 1
fi

cp -f "$PROFILE_SRC" "$PROFILE_DST"
echo "Installed default profile: $PROFILE_DST"

if [[ -f "$RULESET_SRC_DIR/geoip-cn.srs" ]]; then
  cp -f "$RULESET_SRC_DIR/geoip-cn.srs" "$RULESET_DST_DIR/geoip-cn.srs"
  echo "Installed snapshot: $RULESET_DST_DIR/geoip-cn.srs"
else
  echo "Warning: missing $RULESET_SRC_DIR/geoip-cn.srs (run update_sing_rule_sets.sh first)"
fi

if [[ -f "$RULESET_SRC_DIR/geosite-geolocation-cn.srs" ]]; then
  cp -f "$RULESET_SRC_DIR/geosite-geolocation-cn.srs" "$RULESET_DST_DIR/geosite-geolocation-cn.srs"
  echo "Installed snapshot: $RULESET_DST_DIR/geosite-geolocation-cn.srs"
else
  echo "Warning: missing $RULESET_SRC_DIR/geosite-geolocation-cn.srs (run update_sing_rule_sets.sh first)"
fi

echo ""
echo "App Group target: $APP_GROUP_DIR"
ls -la "$CONFIG_DIR" | sed -n '1,20p'
ls -la "$RULESET_DST_DIR" | sed -n '1,20p'

