# ========= OpenMesh GoMobile Build =========
# Build iOS XCFramework (device + simulator) for Xcode

# 你要绑定的 Go packages（gomobile bind 支持多个 packages，一次生成一个 Framework/XCFramework）
# - ./interface: 你的 OpenMesh 业务 API（钱包/分析/等）
# - github.com/sagernet/sing-box/experimental/libbox: sing-box 的 Apple/Android 客户端复用层（转发引擎入口 + PlatformInterface）
PKGS           ?= ./interface github.com/sagernet/sing-box/experimental/libbox

# 输出目录与产物名
IOS_OUTPUT_DIR     ?= ./lib/ios
MACOS_OUTPUT_DIR   ?= ./lib/macos
ANDROID_OUTPUT_DIR ?= ./lib/android
FRAMEWORK_NAME     ?= OpenMeshGo
IOS_XCFRAMEWORK    := $(IOS_OUTPUT_DIR)/$(FRAMEWORK_NAME).xcframework
MACOS_XCFRAMEWORK  := $(MACOS_OUTPUT_DIR)/$(FRAMEWORK_NAME).xcframework

# 最低 iOS 版本（你的 App 目标 iOS15+）
IOS_VERSION    ?= 15.0

# macOS 版本
MACOS_VERSION  ?= 13.0

# ObjC 符号前缀（避免和其它库冲突；想换也行，比如 OM）
OBJC_PREFIX    ?= OM

# Go / Tooling
GO             ?= go
GOPATH         := $(shell $(GO) env GOPATH)
GOMOBILE       := $(GOPATH)/bin/gomobile
GOBIND         := $(GOPATH)/bin/gobind
# Prefer offline-friendly builds once `make vendor` has been run.
GOFLAGS        ?= -mod=vendor

# Apple platforms: ios,iossimulator,macos,maccatalyst (comma-delimited)
IOS_TARGETS    ?= ios,iossimulator
MACOS_TARGETS  ?= macos
# 目标：一个 XCFramework 同时包含 iOS + Simulator + macOS slices
APPLE_TARGETS  ?= $(IOS_TARGETS),$(MACOS_TARGETS)

.PHONY: all doctor tools gomobile-init apple ios ios-fast-sim macos macos-all android clean test vendor help

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
	@echo "Installing gomobile/gobind into GOPATH/bin..."
	@$(GO) install golang.org/x/mobile/cmd/gomobile@latest
	@$(GO) install golang.org/x/mobile/cmd/gobind@latest
	@echo "Done: $(GOMOBILE)"

gomobile-init: tools
	@echo "Initializing gomobile toolchain..."
	@$(GOMOBILE) init

# 一次性生成包含 ios+sim+macos 的 OpenMeshGo.xcframework
apple: gomobile-init
	@mkdir -p ./lib
	@rm -rf ./lib/$(FRAMEWORK_NAME).xcframework
	@echo "Building Unified Apple XCFramework => ./lib/$(FRAMEWORK_NAME).xcframework"
	@echo "  PKGS: $(PKGS)"
	@echo "  TARGETS: $(APPLE_TARGETS)"
	@$(GOMOBILE) bind \
		-target=$(APPLE_TARGETS) \
		-iosversion=$(IOS_VERSION) \
		-prefix=$(OBJC_PREFIX) \
		-o ./lib/$(FRAMEWORK_NAME).xcframework \
		$(PKGS)
	@echo "✅ Done: ./lib/$(FRAMEWORK_NAME).xcframework"

# 生成 Xcode 直接可用的 OpenMesh.xcframework（真机 + 模拟器）
ios: gomobile-init
	@mkdir -p $(IOS_OUTPUT_DIR)
	@rm -rf $(IOS_XCFRAMEWORK)
	@echo "Building XCFramework => $(IOS_XCFRAMEWORK)"
	@echo "  PKGS: $(PKGS)"
	@echo "  TARGETS: $(IOS_TARGETS)"
	@$(GOMOBILE) bind \
		-target=$(IOS_TARGETS) \
		-iosversion=$(IOS_VERSION) \
		-prefix=$(OBJC_PREFIX) \
		-o $(IOS_XCFRAMEWORK) \
		$(PKGS)
	@echo "✅ Done: $(IOS_XCFRAMEWORK)"

# 更快的本地验证：只编译 Apple Silicon 模拟器（arm64-simulator），跑 UI/调试更快
# 如果你在 Intel Mac 上，把 iossimulator/arm64 改成 iossimulator/amd64
ios-fast-sim: gomobile-init
	@mkdir -p $(IOS_OUTPUT_DIR)
	@rm -rf $(IOS_XCFRAMEWORK)
	@echo "Building FAST Simulator-only XCFramework (arm64 simulator) => $(IOS_XCFRAMEWORK)"
	@$(GOMOBILE) bind \
		-target=iossimulator/arm64 \
		-iosversion=$(IOS_VERSION) \
		-prefix=$(OBJC_PREFIX) \
		-o $(IOS_XCFRAMEWORK) \
		$(PKGS)
	@echo "✅ Done (sim-only): $(IOS_XCFRAMEWORK)"

# 为 macOS 构建单独的 xcframework
macos: gomobile-init
	@mkdir -p $(MACOS_OUTPUT_DIR)
	@rm -rf $(MACOS_XCFRAMEWORK)
	@echo "Building macOS XCFramework => $(MACOS_XCFRAMEWORK)"
	@$(GOMOBILE) bind \
		-target=$(MACOS_TARGETS) \
		-prefix=$(OBJC_PREFIX) \
		-o $(MACOS_XCFRAMEWORK) \
		$(PKGS)
	@echo "✅ Done: $(MACOS_XCFRAMEWORK)"

# 为 macOS 构建通用 xcframework（包含多种架构）
macos-all: gomobile-init
	@mkdir -p $(MACOS_OUTPUT_DIR)
	@rm -rf $(MACOS_XCFRAMEWORK)
	@echo "Building Universal macOS XCFramework => $(MACOS_XCFRAMEWORK)"
	@$(GOMOBILE) bind \
		-target=$(MACOS_TARGETS) \
		-prefix=$(OBJC_PREFIX) \
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

vendor:
	@echo "Vendoring dependencies into ./vendor (offline-friendly builds)..."
	@GOCACHE=/tmp/openmesh-go-build-cache $(GO) mod vendor
	@echo "✅ Done: ./vendor"

clean:
	@rm -rf ./lib
	@echo "Cleaned: ./lib"

help:
	@echo "make doctor        - 检查 go / xcode / gomobile 环境"
	@echo "make tools         - 安装 gomobile/gobind"
	@echo "make vendor        - 生成 ./vendor (便于离线构建)"
	@echo "make apple         - 生成统一 OpenMeshGo.xcframework (ios+sim+macos)"
	@echo "make ios           - 生成 OpenMesh.xcframework (ios + iossimulator, iOS>=15)"
	@echo "make ios-fast-sim  - 快速验证：仅生成模拟器 arm64 的 xcframework"
	@echo "make macos         - 生成 OpenMesh.xcframework (macOS, macOS>=13)"
	@echo "make macos-all     - 生成通用 OpenMesh.xcframework (macOS, macOS>=13)"
	@echo "make android       - 生成 OpenMesh.aar (Android)"
	@echo "make test          - go test ./..."
	@echo "make clean         - 清理产物"
