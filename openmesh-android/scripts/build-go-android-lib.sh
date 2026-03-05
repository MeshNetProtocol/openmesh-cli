#!/usr/bin/env bash
set -euo pipefail

GO_CLI_LIB_DIR="${GO_CLI_LIB_DIR:-../go-cli-lib}"
OUTPUT_LIBS_DIR="${OUTPUT_LIBS_DIR:-./libs}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-OpenMeshGo}"
GO_TAGS="${GO_TAGS:-with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_clash_api,with_conntrack}"
ANDROID_API="${ANDROID_API:-21}"
EXTRA_GOFLAGS="${EXTRA_GOFLAGS:--ldflags=-checklinkname=0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GO_CLI_LIB_PATH="$(cd "$ANDROID_ROOT/$GO_CLI_LIB_DIR" && pwd)"
LIBS_PATH="$(cd "$ANDROID_ROOT" && mkdir -p "$OUTPUT_LIBS_DIR" && cd "$OUTPUT_LIBS_DIR" && pwd)"

ANDROID_BUILD_DIR="$GO_CLI_LIB_PATH/lib/android"
AAR_PATH="$ANDROID_BUILD_DIR/${FRAMEWORK_NAME}.aar"
SOURCES_JAR_PATH="$ANDROID_BUILD_DIR/${FRAMEWORK_NAME}-sources.jar"

PKGS=(
  "github.com/sagernet/sing-box/experimental/libbox"
  "github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/interface"
)

echo "== OpenMesh Android Go library build (bash) =="
echo "go-cli-lib: $GO_CLI_LIB_PATH"
echo "android libs: $LIBS_PATH"

if ! command -v go >/dev/null 2>&1; then
  echo "go command not found. Please install Go first." >&2
  exit 1
fi

GOPATH_DIR="$(go env GOPATH)"
if [[ -z "$GOPATH_DIR" ]]; then
  echo "Failed to read GOPATH from go env." >&2
  exit 1
fi
GOMOBILE="$GOPATH_DIR/bin/gomobile"
GOBIND="$GOPATH_DIR/bin/gobind"

if [[ ! -x "$GOMOBILE" || ! -x "$GOBIND" ]]; then
  echo "Installing gomobile/gobind (sagernet fork)..."
  go install github.com/sagernet/gomobile/cmd/gomobile@v0.1.11
  go install github.com/sagernet/gomobile/cmd/gobind@v0.1.11
fi

if [[ ! -x "$GOMOBILE" ]]; then
  echo "gomobile executable not found after installation attempt: $GOMOBILE" >&2
  exit 1
fi

echo "Initializing gomobile toolchain..."
"$GOMOBILE" init

SDK_CANDIDATES=()
[[ -n "${ANDROID_SDK_ROOT:-}" ]] && SDK_CANDIDATES+=("$ANDROID_SDK_ROOT")
[[ -n "${ANDROID_HOME:-}" ]] && SDK_CANDIDATES+=("$ANDROID_HOME")
SDK_CANDIDATES+=("$HOME/Library/Android/sdk")
SDK_CANDIDATES+=("$HOME/Android/Sdk")
SDK_CANDIDATES+=("$HOME/Android/sdk")

SDK_ROOT=""
NDK_ROOT=""
for candidate in "${SDK_CANDIDATES[@]}"; do
  [[ -d "$candidate" ]] || continue
  SDK_ROOT="$candidate"

  if [[ -d "$candidate/ndk" ]]; then
    latest_ndk="$(find "$candidate/ndk" -mindepth 1 -maxdepth 1 -type d | sort | tail -n 1 || true)"
    if [[ -n "$latest_ndk" ]]; then
      NDK_ROOT="$latest_ndk"
      break
    fi
  fi

  if [[ -d "$candidate/ndk-bundle" ]]; then
    NDK_ROOT="$candidate/ndk-bundle"
    break
  fi
done

if [[ -z "$SDK_ROOT" || -z "$NDK_ROOT" ]]; then
  cat >&2 <<'EOF'
Android SDK/NDK not found.
Checked ANDROID_SDK_ROOT / ANDROID_HOME / ~/Library/Android/sdk / ~/Android/Sdk.
Install NDK first, for example:
  sdkmanager "ndk;27.2.12479018" "platforms;android-34" "build-tools;34.0.0"
Then rerun this script.
EOF
  exit 1
fi

export ANDROID_SDK_ROOT="$SDK_ROOT"
if [[ -z "${ANDROID_HOME:-}" ]]; then
  export ANDROID_HOME="$SDK_ROOT"
fi
# Force javac to use UTF-8 so generated JavaDoc from Go comments won't fail on locale defaults.
if [[ "${JAVA_TOOL_OPTIONS:-}" == *"file.encoding"* ]]; then
  :
else
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:-} -Dfile.encoding=UTF-8"
  export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS#" "}"
fi

mkdir -p "$ANDROID_BUILD_DIR" "$LIBS_PATH"

pushd "$GO_CLI_LIB_PATH" >/dev/null
GOFLAGS="-mod=mod $EXTRA_GOFLAGS" "$GOMOBILE" bind -target=android "-androidapi=$ANDROID_API" "-tags=$GO_TAGS" -o "$AAR_PATH" "${PKGS[@]}"
popd >/dev/null

if [[ ! -f "$AAR_PATH" ]]; then
  echo "AAR not generated: $AAR_PATH" >&2
  exit 1
fi

cp -f "$AAR_PATH" "$LIBS_PATH/"
if [[ -f "$SOURCES_JAR_PATH" ]]; then
  cp -f "$SOURCES_JAR_PATH" "$LIBS_PATH/"
fi

echo "Build done."
echo "AAR: $AAR_PATH"
echo "Copied to: $LIBS_PATH"
