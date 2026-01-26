#!/usr/bin/env bash
set -euo pipefail

### ===== 必填/可配参数 =====
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-"$ROOT_DIR/openmesh-apple/OpenMesh.xcodeproj"}"
SCHEME="${SCHEME:-OpenMesh.Sys}"
CONFIGURATION="${CONFIGURATION:-Release}"
SDK="${SDK:-macosx}"

# 如果你已经有一个可用的 .app，可以直接传入：
#   ./release_macos_dev_id.sh /path/to/OpenMeshMac.app
# 否则默认会从 Xcode 工程自动 build 出 .app
APP_PATH="${1:-${APP_PATH:-""}}"

# Developer ID Application 证书名（用于给 .app/.appex/.framework 等签名）
DEV_ID_APP="${DEV_ID_APP:-Developer ID Application: Yushian (Beijing) Technology Co., Ltd. (2XYK8RBB6M)}"

# （可选）Developer ID Installer 证书名（用于签名 .pkg）
DEV_ID_INSTALLER="${DEV_ID_INSTALLER:-}"

# notarytool 的 keychain profile（你之前脚本里已有）
NOTARY_PROFILE="${NOTARY_PROFILE:-notary-profile}"

# （重要）Provisioning Profile（用于校验受限 entitlements，如 Network Extension / App Groups）
# 说明：在当前 macOS 版本上，Developer ID 签名但带有受限 entitlements 的二进制会被 amfid 要求
#       “用匹配的 provisioning profile 进行校验”，否则 launchd 会报 error=162（Codesigning issue）并拒绝启动。
# 这里允许你显式指定要嵌入到 app/appex 中的 profile（通常是 Developer ID 类型的 profile）。
PROVISION_PROFILE_APP="${PROVISION_PROFILE_APP:-"$ROOT_DIR/app.provisionprofile"}"
PROVISION_PROFILE_VPN_MAC="${PROVISION_PROFILE_VPN_MAC:-}"
PROVISION_PROFILE_SYS_EXT="${PROVISION_PROFILE_SYS_EXT:-"$ROOT_DIR/sysext.provisionprofile"}"
REQUIRE_PROVISION_PROFILES="${REQUIRE_PROVISION_PROFILES:-0}" # 1=检测到受限 entitlements 时必须提供 profile（仅在确实需要时开启）

# entitlements（默认按本项目路径；必要时可覆盖）
ENTITLEMENTS_APP="${ENTITLEMENTS_APP:-"$ROOT_DIR/openmesh-apple/OpenMesh.Sys/OpenMesh.Sys.entitlements"}"
ENTITLEMENTS_VPN_MAC="${ENTITLEMENTS_VPN_MAC:-"$ROOT_DIR/openmesh-apple/vpn_extension_macos/vpn_extension_macos.entitlements"}"
ENTITLEMENTS_SYS_EXT="${ENTITLEMENTS_SYS_EXT:-"$ROOT_DIR/openmesh-apple/OpenMesh.Sys-ext/OpenMesh_Sys_ext.entitlements"}"

# 输出
VOL_NAME="${VOL_NAME:-OpenMeshX}"
OUT_DIR="${OUT_DIR:-"$(pwd)/dist-final"}"

# 行为开关
BUILD_APP="${BUILD_APP:-1}"               # 1=自动 build；0=只处理 APP_PATH
NOTARIZE_APP="${NOTARIZE_APP:-1}"         # 1=对 .app.zip 公证并 staple；0=跳过公证
SIGN_DMG="${SIGN_DMG:-1}"                 # 1=给 DMG 代码签名；0=不签
NOTARIZE_DMG="${NOTARIZE_DMG:-0}"         # 1=对 DMG 也公证+staple；0=不公证
MAKE_PKG="${MAKE_PKG:-0}"                 # 1=额外产出 .pkg（需要 DEV_ID_INSTALLER）
NOTARIZE_PKG="${NOTARIZE_PKG:-1}"         # 1=对 .pkg 公证+staple（当 MAKE_PKG=1）
### ========================

err(){ echo "ERROR: $*" >&2; exit 1; }
info(){ echo "==> $*" >&2; }

usage() {
  cat <<'EOF'
用法：
  release_macos_dev_id.sh [PATH_TO_APP]

说明：
  - 不传 PATH_TO_APP 时，默认从 openmesh-apple/OpenMesh.xcodeproj 自动 build（scheme=OpenMeshMac）
  - 会对主 app + Network Extension（.appex 或 .systemextension）+ 所有嵌套组件签名
  - 可选执行 notarytool 公证并 staple，然后输出 DMG（可选 PKG）

常用环境变量：
  DEV_ID_APP        Developer ID Application 证书名（必填）
  NOTARY_PROFILE    notarytool keychain profile 名
  OUT_DIR           输出目录（默认当前目录）
  NOTARIZE_APP      1=公证 app（默认 1），0=跳过
  MAKE_PKG          1=额外生成 PKG（默认 0），需要 DEV_ID_INSTALLER

示例：
  DEV_ID_APP="Developer ID Application: <Your Company>" \
  NOTARY_PROFILE="notary-profile" \
  OUT_DIR="$(pwd)/dist" \
  ./openmesh-apple/scripts/release_macos_dev_id.sh

OpenMesh.Sys（System Extension）示例：
  SCHEME="OpenMesh.Sys" \
  ENTITLEMENTS_APP="openmesh-apple/OpenMesh.Sys/OpenMesh.Sys.entitlements" \
  ENTITLEMENTS_SYS_EXT="openmesh-apple/OpenMesh.Sys-ext/OpenMesh_Sys_ext.entitlements" \
  ./openmesh-apple/scripts/release_macos_dev_id.sh
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

require_cmd() { command -v "$1" >/dev/null 2>&1 || err "缺少命令: $1"; }
require_file() { [[ -f "$1" ]] || err "找不到文件: $1"; }
require_dir() { [[ -d "$1" ]] || err "找不到目录: $1"; }

require_cmd xcrun
require_cmd xcodebuild
require_cmd codesign
require_cmd ditto
require_cmd hdiutil
require_cmd spctl
require_cmd file
require_cmd find
require_cmd awk
require_cmd xattr
require_cmd sort
require_cmd cut
require_cmd grep
require_cmd head
require_cmd security

[[ -n "$DEV_ID_APP" ]] || err "请设置 DEV_ID_APP（Developer ID Application 证书名）"

if ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "$DEV_ID_APP"; then
  err "未在钥匙串找到代码签名证书：$DEV_ID_APP（请检查证书名或 Keychain 访问权限）"
fi

WORK_DIR="$(mktemp -d -t "openmesh-macos-release")"
DERIVED_DATA="${WORK_DIR}/DerivedData"
ZIP_PATH="${WORK_DIR}/${SCHEME}.app.zip"
STAGE_DIR="${WORK_DIR}/stage"

# 清空旧输出并确保 entitlements 存在
info "Cleaning old output and checking dependencies..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

require_file "$ENTITLEMENTS_APP"
[[ -z "$ENTITLEMENTS_SYS_EXT" ]] || require_file "$ENTITLEMENTS_SYS_EXT"

cleanup(){ rm -rf "$WORK_DIR"; }
trap cleanup EXIT

is_macho() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  file -b "$f" | grep -Eiq 'Mach-O' || return 1
  return 0
}

entitlements_flag_for_target() {
  local target="$1"

  if [[ "$target" == *.app ]]; then
    # 仅对主 app 使用 OpenMeshMac.entitlements；避免误用于嵌套 helper.app
    if [[ -n "${APP_NAME:-}" && "$(basename "$target")" == "${APP_NAME}.app" && -f "$ENTITLEMENTS_APP" ]]; then
      echo "$ENTITLEMENTS_APP"
      return 0
    fi
  fi

  if [[ "$target" == *.appex ]]; then
    if [[ "$(basename "$target")" == *vpn_extension_macos* && -f "$ENTITLEMENTS_VPN_MAC" ]]; then
      echo "$ENTITLEMENTS_VPN_MAC"
      return 0
    fi
  fi

  if [[ "$target" == *.systemextension ]]; then
    if [[ -n "$ENTITLEMENTS_SYS_EXT" && -f "$ENTITLEMENTS_SYS_EXT" ]]; then
      echo "$ENTITLEMENTS_SYS_EXT"
      return 0
    fi
  fi

  # 尝试从现有签名提取 entitlements（如果存在）
  local tmp
  tmp="$(mktemp -t entitlements).plist"
  if codesign -d --entitlements :- "$target" 2>/dev/null >"$tmp"; then
    if grep -q "<plist" "$tmp"; then
      echo "$tmp"
      return 0
    fi
  fi
  rm -f "$tmp" || true
  return 1
}

codesign_one() {
  local target="$1"
  shift || true

  xattr -rc "$target" >/dev/null 2>&1 || true

  local ent_file=""
  if ent_file="$(entitlements_flag_for_target "$target" 2>/dev/null)"; then
    codesign --force --options runtime --timestamp --sign "$DEV_ID_APP" --entitlements "$ent_file" "$target"
    [[ "$ent_file" == "$ENTITLEMENTS_APP" || "$ent_file" == "$ENTITLEMENTS_VPN_MAC" || "$ent_file" == "$ENTITLEMENTS_SYS_EXT" ]] || rm -f "$ent_file" || true
  else
    codesign --force --options runtime --timestamp --sign "$DEV_ID_APP" "$target"
  fi
}

entitlements_need_profile() {
  local ent_file="$1"
  [[ -f "$ent_file" ]] || return 1
  # 经验规则：Network Extension 是受限 entitlement（需要额外授权）；部分系统/配置下可能要求 profile 校验
  if grep -q "com.apple.developer.networking.networkextension" "$ent_file"; then
    return 0
  fi
  return 1
}

embed_profile() {
  local src="$1"
  local dst="$2"
  [[ -n "$src" ]] || return 0
  require_file "$src"
  info "Embed provisioning profile: $src -> $dst"
  mkdir -p "$(dirname "$dst")"
  cp -f "$src" "$dst"
}

build_and_locate_app() {
  require_dir "$PROJECT_PATH"

  info "Build macOS app via xcodebuild"
  info "Project: $PROJECT_PATH"
  info "Scheme : $SCHEME"
  info "Config : $CONFIGURATION"
  info "Derived: $DERIVED_DATA"

  local full_product_name=""
  full_product_name="$(
    xcodebuild -showBuildSettings \
      -project "$PROJECT_PATH" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -sdk "$SDK" \
      -derivedDataPath "$DERIVED_DATA" \
      -destination "generic/platform=macOS" 2>/dev/null | \
      awk -F' = ' '/ FULL_PRODUCT_NAME /{print $2; exit}'
  )" || true

  xcodebuild build \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -sdk "$SDK" \
    -derivedDataPath "$DERIVED_DATA" \
    -destination "generic/platform=macOS" 1>&2

  local products_dir="${DERIVED_DATA}/Build/Products/${CONFIGURATION}"
  require_dir "$products_dir"

  if [[ -n "$full_product_name" && -d "${products_dir}/${full_product_name}" ]]; then
    echo "${products_dir}/${full_product_name}"
    return 0
  fi

  if [[ -d "${products_dir}/${SCHEME}.app" ]]; then
    echo "${products_dir}/${SCHEME}.app"
    return 0
  fi

  local first_app
  first_app="$(find "$products_dir" -maxdepth 1 -type d -name "*.app" -print | head -n 1 || true)"
  [[ -n "$first_app" && -d "$first_app" ]] || err "无法在 ${products_dir} 找到 build 产物 .app（请检查 scheme/configuration）"
  echo "$first_app"
}

if [[ -n "$APP_PATH" ]]; then
  require_dir "$APP_PATH"
fi

if [[ -z "$APP_PATH" ]]; then
  [[ "$BUILD_APP" == "1" ]] || err "未提供 APP_PATH 且 BUILD_APP=0"
  APP_PATH="$(build_and_locate_app)"
else
  if [[ "$BUILD_APP" == "1" ]]; then
    info "APP_PATH 已指定，跳过 build（如需强制 build，请清空 APP_PATH 或自行先 build）"
  fi
fi

APP_ABS="$(cd "$(dirname "$APP_PATH")" && pwd)/$(basename "$APP_PATH")"
APP_NAME="$(basename "$APP_ABS" .app)"

APP_WORK="${WORK_DIR}/${APP_NAME}.app"
info "Copy .app to workdir"
ditto "$APP_ABS" "$APP_WORK"

DMG_PATH="${OUT_DIR}/${APP_NAME}.dmg"
PKG_PATH="${OUT_DIR}/${APP_NAME}.pkg"

# 每次运行前，删除旧的产物
info "Remove old artifacts..."
rm -f "$DMG_PATH" "$PKG_PATH" || true

NOTARY_LOG_APP="${OUT_DIR}/${APP_NAME}.app.notary.log"
NOTARY_LOG_DMG="${OUT_DIR}/${APP_NAME}.dmg.notary.log"
NOTARY_LOG_PKG="${OUT_DIR}/${APP_NAME}.pkg.notary.log"

info "Input app : $APP_ABS"
info "Work app  : $APP_WORK"
info "Out dir   : $OUT_DIR"
info "Out DMG   : $DMG_PATH"
info "Signer    : $DEV_ID_APP"
info "Notary profile: $NOTARY_PROFILE"

require_file "$ENTITLEMENTS_APP"

# 仅在产物里确实包含对应组件时才强制要求其 entitlements/profile
HAS_VPN_MAC_APPEX=0
if [[ -d "$APP_WORK/Contents/PlugIns/vpn_extension_macos.appex" ]]; then
  HAS_VPN_MAC_APPEX=1
  require_file "$ENTITLEMENTS_VPN_MAC"
fi

HAS_SYS_EXT=0
if find "$APP_WORK/Contents/Library/SystemExtensions" -maxdepth 1 -type d -name "*.systemextension" -print -quit 2>/dev/null | grep -q .; then
  HAS_SYS_EXT=1
  [[ -n "$ENTITLEMENTS_SYS_EXT" ]] || err "检测到 .systemextension，但未设置 ENTITLEMENTS_SYS_EXT"
  require_file "$ENTITLEMENTS_SYS_EXT"
fi

### 0) 清理开发签名残留：embedded.provisionprofile
# 如果把 Apple Development build 出来的 provisioning profile 原样带到 Developer ID 分发包里，
# 很容易与 Developer ID 证书不匹配；而不带 profile 又会导致受限 entitlements 校验失败。
# info "Reset embedded provisioning profiles"
# while IFS= read -r -d '' p; do
#   info "Remove: $p"
#   rm -f "$p" || true
# done < <(find "$APP_WORK" -name "embedded.provisionprofile" -print0 2>/dev/null || true)

# 如果 entitlements 里包含受限项，强烈建议嵌入匹配的 provisioning profile（通常是 Developer ID profile）
if entitlements_need_profile "$ENTITLEMENTS_APP" || { [[ "$HAS_VPN_MAC_APPEX" == "1" ]] && entitlements_need_profile "$ENTITLEMENTS_VPN_MAC"; }; then
  if [[ "$REQUIRE_PROVISION_PROFILES" == "1" ]]; then
    [[ -n "$PROVISION_PROFILE_APP" ]] || err "需要设置 PROVISION_PROFILE_APP（包含受限 entitlements 的 macOS app 通常必须嵌入匹配的 provisioning profile，否则会出现 error=162 无法打开）"
    if [[ "$HAS_VPN_MAC_APPEX" == "1" ]]; then
      [[ -n "$PROVISION_PROFILE_VPN_MAC" ]] || err "需要设置 PROVISION_PROFILE_VPN_MAC（vpn_extension_macos.appex 的 provisioning profile）"
    fi
  fi
fi

if [[ "$HAS_SYS_EXT" == "1" ]] && entitlements_need_profile "$ENTITLEMENTS_SYS_EXT"; then
  if [[ "$REQUIRE_PROVISION_PROFILES" == "1" ]]; then
    [[ -n "$PROVISION_PROFILE_SYS_EXT" ]] || err "需要设置 PROVISION_PROFILE_SYS_EXT（.systemextension 的 provisioning profile）"
  fi
fi

if [[ -n "$PROVISION_PROFILE_APP" ]]; then
  embed_profile "$PROVISION_PROFILE_APP" "$APP_WORK/Contents/embedded.provisionprofile"
fi
if [[ "$HAS_VPN_MAC_APPEX" == "1" && -n "$PROVISION_PROFILE_VPN_MAC" ]]; then
  embed_profile "$PROVISION_PROFILE_VPN_MAC" "$APP_WORK/Contents/PlugIns/vpn_extension_macos.appex/Contents/embedded.provisionprofile"
fi

if [[ -n "$PROVISION_PROFILE_SYS_EXT" ]]; then
  sys_ext_dir="$(find "$APP_WORK/Contents/Library/SystemExtensions" -maxdepth 1 -type d -name "*.systemextension" -print | head -n 1 || true)"
  if [[ -n "$sys_ext_dir" && -d "$sys_ext_dir" ]]; then
    embed_profile "$PROVISION_PROFILE_SYS_EXT" "$sys_ext_dir/Contents/embedded.provisionprofile"
  else
    info "WARN: PROVISION_PROFILE_SYS_EXT 已设置，但未在 app 内找到 .systemextension（$APP_WORK/Contents/Library/SystemExtensions）"
  fi
fi

### 1) 先签名所有 Mach-O（包含 Resources 下的工具、dylib 等）
info "Scan & sign Mach-O files (including embedded tools)"

MACHO_COUNT=0
while IFS= read -r -d '' f; do
  if is_macho "$f"; then
    MACHO_COUNT=$((MACHO_COUNT + 1))
    chmod u+w "$f" >/dev/null 2>&1 || true
    codesign --remove-signature "$f" >/dev/null 2>&1 || true
    codesign_one "$f" || err "签名失败: $f"
  fi
done < <(find "$APP_WORK/Contents" -type f -print0 2>/dev/null || true)

info "Signed ${MACHO_COUNT} Mach-O files"

### 2) 签名嵌套的 code bundle（.appex/.xpc/.framework/.systemextension/...），按路径深度从深到浅
info "Sign nested code bundles"

CODE_BUNDLES_SORTED=()
while IFS= read -r b; do
  [[ -n "$b" ]] || continue
  CODE_BUNDLES_SORTED+=("$b")
done < <(
  find "$APP_WORK/Contents" -type d \( \
    -name "*.appex" -o \
    -name "*.xpc" -o \
    -name "*.framework" -o \
    -name "*.bundle" -o \
    -name "*.plugin" -o \
    -name "*.systemextension" -o \
    -name "*.app" \
  \) -print 2>/dev/null | \
  awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2-
)

if ((${#CODE_BUNDLES_SORTED[@]} > 0)); then
  info "Found ${#CODE_BUNDLES_SORTED[@]} nested code bundles"
  for b in "${CODE_BUNDLES_SORTED[@]}"; do
    chmod -R u+w "$b" >/dev/null 2>&1 || true
    codesign_one "$b" || err "签名失败: $b"
  done
fi

### 3) 最后签名主 .app（带 entitlements）
info "Sign main app bundle"
chmod -R u+w "$APP_WORK" >/dev/null 2>&1 || true
codesign_one "$APP_WORK"

### 4) 验证签名完整性
info "Verify codesign"
codesign --verify --deep --strict --verbose=2 "$APP_WORK"

### 4.1) 检查 .app 详细信息 (Diagnostic check before packaging)
info "Checking .app bundle information and signature detail..."
codesign -dvvv "$APP_WORK"
if [[ "$HAS_SYS_EXT" == "1" ]]; then
  info "Checking SystemExtension signature detail..."
  sys_ext_path="$(find "$APP_WORK/Contents/Library/SystemExtensions" -maxdepth 1 -type d -name "*.systemextension" -print | head -n 1 || true)"
  if [[ -n "$sys_ext_path" ]]; then
    codesign -dvvv "$sys_ext_path"
    info "Dump entitlements for SystemExtension:"
    codesign -d --entitlements :- "$sys_ext_path"
  fi
fi

### 5) 打包 zip（供 notarytool 提交）
if [[ "$NOTARIZE_APP" == "1" ]]; then
  info "Zip .app for notarization"
  /usr/bin/xcrun ditto -c -k --keepParent "$APP_WORK" "$ZIP_PATH"

  info "Submit app for notarization (requires Apple servers; may take a while)..."
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$NOTARY_LOG_APP"

  info "Staple notarization ticket to .app"
  xcrun stapler staple "$APP_WORK"
else
  info "Skip notarization (NOTARIZE_APP=0)"
fi

### 6) 生成 DMG（装入已 stapled 的 .app）
info "Create DMG"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
ditto "$APP_WORK" "$STAGE_DIR/$(basename "$APP_WORK")"
ln -s /Applications "$STAGE_DIR/Applications" || true

RW_DMG="$(mktemp -u -t "${APP_NAME}-rw").dmg"
hdiutil create -srcfolder "$STAGE_DIR" -volname "$VOL_NAME" -fs HFS+ -format UDRW -ov "$RW_DMG" >/dev/null
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" -ov >/dev/null
rm -f "$RW_DMG"

### 7) （可选）给 DMG 签名
if [[ "$SIGN_DMG" == "1" ]]; then
  info "Codesign DMG"
  codesign --force --sign "$DEV_ID_APP" --timestamp "$DMG_PATH"
fi

### 8) （可选）对 DMG 也公证 + staple
if [[ "$NOTARIZE_DMG" == "1" ]]; then
  info "Notarize DMG (optional)"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$NOTARY_LOG_DMG"
  info "Staple DMG"
  xcrun stapler staple "$DMG_PATH"
fi

### 9) （可选）产出 PKG（推荐用于企业分发；需要 DEV_ID_INSTALLER）
if [[ "$MAKE_PKG" == "1" ]]; then
  [[ -n "$DEV_ID_INSTALLER" ]] || err "MAKE_PKG=1 需要设置 DEV_ID_INSTALLER（Developer ID Installer 证书名）"
  require_cmd productbuild

  info "Create signed PKG"
  productbuild --component "$APP_WORK" /Applications --sign "$DEV_ID_INSTALLER" "$PKG_PATH"

  if [[ "$NOTARIZE_PKG" == "1" ]]; then
    info "Notarize PKG"
    xcrun notarytool submit "$PKG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$NOTARY_LOG_PKG"
    info "Staple PKG"
    xcrun stapler staple "$PKG_PATH"
  fi
fi

### 10) Gatekeeper 自检
info "Gatekeeper check (.app)"
spctl -a -vv "$APP_WORK" || true

info "Gatekeeper check (DMG)"
DMG_MOUNT="$(mktemp -d -t "${APP_NAME}-dmg-mount")"
if hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$DMG_MOUNT" >/dev/null 2>&1; then
  MOUNTED_APP="$(find "$DMG_MOUNT" -maxdepth 1 -type d -name "*.app" -print | head -n 1 || true)"
  if [[ -n "$MOUNTED_APP" && -d "$MOUNTED_APP" ]]; then
    spctl -a -vv "$MOUNTED_APP" || true
  else
    info "WARN: DMG mount succeeded but no .app found at root"
  fi
  hdiutil detach "$DMG_MOUNT" >/dev/null 2>&1 || true
else
  info "WARN: Unable to mount DMG for check"
fi
rmdir "$DMG_MOUNT" >/dev/null 2>&1 || true

if [[ "$MAKE_PKG" == "1" ]]; then
  info "Gatekeeper check (PKG)"
  spctl -a -vv "$PKG_PATH" || true
fi

echo
echo "✅ 完成：已生成可分发产物"
echo "   DMG : $DMG_PATH"
if [[ "$MAKE_PKG" == "1" ]]; then
  echo "   PKG : $PKG_PATH"
fi
if [[ "$NOTARIZE_APP" == "1" ]]; then
  echo "📝 App Notary log: $NOTARY_LOG_APP"
fi
if [[ "$NOTARIZE_DMG" == "1" ]]; then
  echo "📝 DMG Notary log: $NOTARY_LOG_DMG"
fi
if [[ "$MAKE_PKG" == "1" && "$NOTARIZE_PKG" == "1" ]]; then
  echo "📝 PKG Notary log: $NOTARY_LOG_PKG"
fi
