# ========= OpenMesh GoMobile Build =========
# Build iOS XCFramework (device + simulator) for Xcode

#
# 你要绑定的 Go packages（gomobile bind 支持多个 packages，一次生成一个 Framework/XCFramework）
#
# ⚠️ Apple VPN / NetworkExtension 场景强烈建议 “只绑定 sing-box/libbox”，完全对齐 sing-box：
# - 避免把钱包/业务依赖（go-ethereum、gin、bip32/bip39 等）拉进 Apple slice，导致依赖网络问题/GoModule 变动
# - 避免在 gomobile 过程中触发 git 认证/代理差异（会直接导致构建失败）
#
# 如需业务 API（钱包/分析），建议单独产物/单独 module 构建，不要和 libbox 混在同一个 Apple xcframework 里。
PKGS           ?= github.com/sagernet/sing-box/experimental/libbox

# Apple bind：直接在 sing-box module 根目录执行（最接近 upstream 的方式）。
# 这样 gomobile 生成临时代码时不会试图“补写 go.mod”，因为 sing-box 自己的 go.mod/go.sum 已经完整。
APPLE_BIND_DIR ?= .
APPLE_PKGS     ?= $(PKGS)

# 用可访问的 GOPROXY（避免 goproxy.io / goproxy.cn 对某些模块 404 或 DNS/TLS 不稳定）
# proxy.golang.org 是 Go 官方代理，兼容性最好
APPLE_GOPROXY  ?= https://proxy.golang.org,direct
APPLE_GOSUMDB  ?= sum.golang.org

# Some environments set GOFLAGS=-mod=readonly globally, and gomobile may inherit it.
# Allow module graph updates in gomobile's temporary work dirs.
APPLE_GOFLAGS  ?= -mod=mod

# 输出目录与产物名
IOS_OUTPUT_DIR     ?= ./lib/ios
MACOS_OUTPUT_DIR   ?= ./lib/macos
ANDROID_OUTPUT_DIR ?= ./lib/android
FRAMEWORK_NAME     ?= OpenMeshGo
IOS_XCFRAMEWORK    := $(IOS_OUTPUT_DIR)/$(FRAMEWORK_NAME).xcframework
MACOS_XCFRAMEWORK  := $(MACOS_OUTPUT_DIR)/$(FRAMEWORK_NAME).xcframework

# Absolute output path for gomobile when running from another module dir.
APPLE_XCFRAMEWORK_ABS := $(abspath ./lib/$(FRAMEWORK_NAME).xcframework)

# 最低 iOS 版本（你的 App 目标 iOS15+）
IOS_VERSION    ?= 15.0

# macOS 版本
MACOS_VERSION  ?= 13.0

# ObjC 符号前缀（避免和其它库冲突；想换也行，比如 OM）
OBJC_PREFIX    ?= OM

# Go build tags (comma-separated recommended for gomobile, e.g. "with_gvisor,with_clash_api").
#
# Goal: Keep our VPN/libbox behavior fully aligned with upstream sing-box.
# Upstream reference:
#   sing-box/cmd/internal/build_libbox/main.go (sharedTags + darwinTags)
#
# Notes:
# - Some features are only used on specific platforms in upstream (e.g. low_memory, tailscale),
#   but gomobile bind here uses a single tag set across Apple targets; we include the upstream
#   feature tags directly to minimize "feature not included" runtime failures.
# NOTE: sing-box upstream includes `badlinkname`, but that tag activates go1.25-only
# linkname hooks in `sing-box/common/badtls/*` which break on Go 1.25.x (linker error
# against `crypto/tls.(*Conn).handlePostHandshakeMessage`).
# Until we build with Go 1.24.x (upstream's go.mod), keep `badlinkname` disabled here.
#
# IMPORTANT (macOS NetworkExtension / app extension):
# `with_naive_outbound` pulls in cronet-go (Chromium/Cronet), which depends on AppKit
# symbols like NSApp / NSApplication. App extensions are built with -fapplication-extension
# and must not link AppKit, otherwise you'll hit undefined symbols / app-extension API violations.
#
# So for system/app extensions we keep GO_TAGS "extension-safe" by default.
# If you really need naive outbound (Cronet), build a separate non-extension variant.
GO_TAGS        ?= with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_clash_api,with_conntrack,tfogo_checklinkname0

ifneq ($(strip $(GO_TAGS)),)
GOMOBILE_TAGS_FLAG := -tags=$(GO_TAGS)
endif

# Go / Tooling
GO             ?= go
GOPATH         := $(shell $(GO) env GOPATH)
GOMOBILE       := $(GOPATH)/bin/gomobile
GOBIND         := $(GOPATH)/bin/gobind

# Apple platforms: ios,iossimulator,macos,maccatalyst (comma-delimited)
IOS_TARGETS    ?= ios,iossimulator
MACOS_TARGETS  ?= macos
# 目标：一个 XCFramework 同时包含 iOS + Simulator + macOS slices
APPLE_TARGETS  ?= $(IOS_TARGETS),$(MACOS_TARGETS)

.PHONY: all doctor tools gomobile-init apple ios ios-fast-sim macos macos-all android clean test help

all: apple

doctor:
	@echo "== go =="
	@$(GO) version
	@echo "== xcode =="
	@xcodebuild -version
	@echo "== xcode-select =="
	@xcode-select -p
	@echo "== gomobile =="
	@([ -x "$(GOMOBILE)" ] && $(GOMOBILE) version) || echo "gomobile not installed (run: make tools)"

tools:
	@echo "Installing/updating gomobile/gobind (sagernet fork, required for iossimulator/tvossimulator tags)..."
	@GOPROXY="$(APPLE_GOPROXY)" GOSUMDB="$(APPLE_GOSUMDB)" $(GO) install github.com/sagernet/gomobile/cmd/gomobile@v0.1.11
	@GOPROXY="$(APPLE_GOPROXY)" GOSUMDB="$(APPLE_GOSUMDB)" $(GO) install github.com/sagernet/gomobile/cmd/gobind@v0.1.11
	@echo "gomobile installed at: $(GOMOBILE)"
	@go version -m "$(GOMOBILE)" 2>/dev/null | sed -n '1,12p' || true
	@echo "gobind installed at: $(GOBIND)"
	@go version -m "$(GOBIND)" 2>/dev/null | sed -n '1,12p' || true

gomobile-init: tools
	@if [ "$(FORCE_GOMOBILE_INIT)" = "1" ]; then \
		echo "Forcing gomobile init..."; \
		rm -rf "$(GOPATH)/pkg/gomobile"; \
		$(GOMOBILE) init; \
	elif ! go version -m "$(GOMOBILE)" 2>/dev/null | grep -q "github.com/sagernet/gomobile"; then \
		echo "Detected non-sagernet gomobile; forcing re-init to enable iossimulator/tvossimulator build tags..."; \
		rm -rf "$(GOPATH)/pkg/gomobile"; \
		$(GOMOBILE) init; \
	elif [ -d "$(GOPATH)/pkg/gomobile" ]; then \
		echo "gomobile toolchain already initialized: $(GOPATH)/pkg/gomobile"; \
		echo "  (set FORCE_GOMOBILE_INIT=1 to re-init)"; \
	else \
		echo "Initializing gomobile toolchain..."; \
		$(GOMOBILE) init; \
	fi

# 一次性生成包含 ios+sim+macos 的 OpenMeshGo.xcframework
apple: gomobile-init
	@mkdir -p ./lib
	@rm -rf ./lib/$(FRAMEWORK_NAME).xcframework
	@echo "Cleaning previous build artifacts in $(APPLE_BIND_DIR)/build..."
	@rm -rf "$(APPLE_BIND_DIR)/build"
	@echo "Building Unified Apple XCFramework => ./lib/$(FRAMEWORK_NAME).xcframework"
	@echo "  BIND_DIR: $(APPLE_BIND_DIR)"
	@echo "  PKGS: $(APPLE_PKGS)"
	@echo "  TARGETS: $(APPLE_TARGETS)"
	@echo "  GO_TAGS: $(GO_TAGS)"
	@cd "$(APPLE_BIND_DIR)" && MACOSX_DEPLOYMENT_TARGET=$(MACOS_VERSION) \
		GOPROXY="$(APPLE_GOPROXY)" GOSUMDB="$(APPLE_GOSUMDB)" GOFLAGS="$(APPLE_GOFLAGS)" \
		$(GOMOBILE) bind \
		-target=$(APPLE_TARGETS) \
		-iosversion=$(IOS_VERSION) \
		-prefix=$(OBJC_PREFIX) \
		$(GOMOBILE_TAGS_FLAG) \
		-o "$(APPLE_XCFRAMEWORK_ABS)" \
		$(APPLE_PKGS)
	@echo "✅ Done: ./lib/$(FRAMEWORK_NAME).xcframework"

# 生成 Xcode 直接可用的 OpenMesh.xcframework（真机 + 模拟器）
ios: gomobile-init
	@mkdir -p $(IOS_OUTPUT_DIR)
	@rm -rf $(IOS_XCFRAMEWORK)
	@echo "Building XCFramework => $(IOS_XCFRAMEWORK)"
	@echo "  BIND_DIR: $(APPLE_BIND_DIR)"
	@echo "  PKGS: $(APPLE_PKGS)"
	@echo "  TARGETS: $(IOS_TARGETS)"
	@echo "  GO_TAGS: $(GO_TAGS)"
	@cd "$(APPLE_BIND_DIR)" && GOFLAGS="$(APPLE_GOFLAGS)" \
		$(GOMOBILE) bind \
		-target=$(IOS_TARGETS) \
		-iosversion=$(IOS_VERSION) \
		-prefix=$(OBJC_PREFIX) \
		$(GOMOBILE_TAGS_FLAG) \
		-o ../$(IOS_XCFRAMEWORK) \
		$(APPLE_PKGS)
	@echo "✅ Done: $(IOS_XCFRAMEWORK)"

# 更快的本地验证：只编译 Apple Silicon 模拟器（arm64-simulator），跑 UI/调试更快
# 如果你在 Intel Mac 上，把 iossimulator/arm64 改成 iossimulator/amd64
ios-fast-sim: gomobile-init
	@mkdir -p $(IOS_OUTPUT_DIR)
	@rm -rf $(IOS_XCFRAMEWORK)
	@echo "Building FAST Simulator-only XCFramework (arm64 simulator) => $(IOS_XCFRAMEWORK)"
	@cd "$(APPLE_BIND_DIR)" && GOFLAGS="$(APPLE_GOFLAGS)" \
		$(GOMOBILE) bind \
		-target=iossimulator/arm64 \
		-iosversion=$(IOS_VERSION) \
		-prefix=$(OBJC_PREFIX) \
		$(GOMOBILE_TAGS_FLAG) \
		-o ../$(IOS_XCFRAMEWORK) \
		$(APPLE_PKGS)
	@echo "✅ Done (sim-only): $(IOS_XCFRAMEWORK)"

# 为 macOS 构建单独的 xcframework
macos: gomobile-init
	@mkdir -p $(MACOS_OUTPUT_DIR)
	@rm -rf $(MACOS_XCFRAMEWORK)
	@echo "Building macOS XCFramework => $(MACOS_XCFRAMEWORK)"
	@MACOSX_DEPLOYMENT_TARGET=$(MACOS_VERSION) $(GOMOBILE) bind \
		-target=$(MACOS_TARGETS) \
		-prefix=$(OBJC_PREFIX) \
		$(GOMOBILE_TAGS_FLAG) \
		-o $(MACOS_XCFRAMEWORK) \
		$(PKGS)
	@echo "✅ Done: $(MACOS_XCFRAMEWORK)"

# 为 macOS 构建通用 xcframework（包含多种架构）
macos-all: gomobile-init
	@mkdir -p $(MACOS_OUTPUT_DIR)
	@rm -rf $(MACOS_XCFRAMEWORK)
	@echo "Building Universal macOS XCFramework => $(MACOS_XCFRAMEWORK)"
	@MACOSX_DEPLOYMENT_TARGET=$(MACOS_VERSION) $(GOMOBILE) bind \
		-target=$(MACOS_TARGETS) \
		-prefix=$(OBJC_PREFIX) \
		$(GOMOBILE_TAGS_FLAG) \
		-o $(MACOS_XCFRAMEWORK) \
		$(PKGS)
	@echo "✅ Done: $(MACOS_XCFRAMEWORK)"

# 为 Android 构建 AAR 文件
android: gomobile-init
	@mkdir -p $(ANDROID_OUTPUT_DIR)
	@echo "Building Android AAR => $(ANDROID_OUTPUT_DIR)/$(FRAMEWORK_NAME).aar"
	@$(GOMOBILE) bind \
		-target=android \
		-o $(ANDROID_OUTPUT_DIR)/$(FRAMEWORK_NAME).aar \
		$(PKG)
	@echo "✅ Done: $(ANDROID_OUTPUT_DIR)/$(FRAMEWORK_NAME).aar"

test:
	@echo "Running go test..."
	@GOCACHE=/tmp/openmesh-go-build-cache $(GO) test ./... -count=1

clean:
	@rm -rf ./lib
	@rm -rf "$(APPLE_BIND_DIR)/build"
	@echo "Cleaned: ./lib and $(APPLE_BIND_DIR)/build"

help:
	@echo "make doctor        - 检查 go / xcode / gomobile 环境"
	@echo "make tools         - 安装 gomobile/gobind"
	@echo "make apple         - 生成统一 OpenMeshGo.xcframework (ios+sim+macos)"
	@echo "make ios           - 生成 OpenMesh.xcframework (ios + iossimulator, iOS>=15)"
	@echo "make ios-fast-sim  - 快速验证：仅生成模拟器 arm64 的 xcframework"
	@echo "make macos         - 生成 OpenMesh.xcframework (macOS, macOS>=13)"
	@echo "make macos-all     - 生成通用 OpenMesh.xcframework (macOS, macOS>=13)"
	@echo "make android       - 生成 OpenMesh.aar (Android)"
	@echo "make test          - go test ./..."
	@echo "make clean         - 清理产物"
