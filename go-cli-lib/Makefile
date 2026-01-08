# ========= OpenMesh GoMobile Build =========
# Build iOS XCFramework (device + simulator) for Xcode

# 你要绑定的 Go 包路径（你现在的 openmesh 在 ./interface 目录）
PKG            ?= ./interface

# 输出目录与产物名
OUTPUT_DIR     ?= ./lib
FRAMEWORK_NAME ?= OpenMeshGo
XCFRAMEWORK    := $(OUTPUT_DIR)/$(FRAMEWORK_NAME).xcframework

# 最低 iOS 版本（你的 App 目标 iOS15+）
IOS_VERSION    ?= 15.0

# ObjC 符号前缀（避免和其它库冲突；想换也行，比如 OM）
OBJC_PREFIX    ?= OM

# Go / Tooling
GO             ?= go
GOPATH         := $(shell $(GO) env GOPATH)
GOMOBILE       := $(GOPATH)/bin/gomobile
GOBIND         := $(GOPATH)/bin/gobind

# Apple platforms: ios, iossimulator, macos, maccatalyst (comma-delimited)
APPLE_TARGETS  ?= ios,iossimulator

.PHONY: all doctor tools gomobile-init ios ios-fast-sim clean test help

all: ios

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

# 生成 Xcode 直接可用的 OpenMesh.xcframework（真机 + 模拟器）
ios: gomobile-init
	@mkdir -p $(OUTPUT_DIR)
	@rm -rf $(XCFRAMEWORK)
	@echo "Building XCFramework => $(XCFRAMEWORK)"
	@echo "  PKG: $(PKG)"
	@echo "  TARGETS: $(APPLE_TARGETS)"
	@$(GOMOBILE) bind \
		-target=$(APPLE_TARGETS) \
		-iosversion=$(IOS_VERSION) \
		-prefix=$(OBJC_PREFIX) \
		-o $(XCFRAMEWORK) \
		$(PKG)
	@echo "✅ Done: $(XCFRAMEWORK)"

# 更快的本地验证：只编译 Apple Silicon 模拟器（arm64-simulator），跑 UI/调试更快
# 如果你在 Intel Mac 上，把 iossimulator/arm64 改成 iossimulator/amd64
ios-fast-sim: gomobile-init
	@mkdir -p $(OUTPUT_DIR)
	@rm -rf $(XCFRAMEWORK)
	@echo "Building FAST Simulator-only XCFramework (arm64 simulator) => $(XCFRAMEWORK)"
	@$(GOMOBILE) bind \
		-target=iossimulator/arm64 \
		-iosversion=$(IOS_VERSION) \
		-prefix=$(OBJC_PREFIX) \
		-o $(XCFRAMEWORK) \
		$(PKG)
	@echo "✅ Done (sim-only): $(XCFRAMEWORK)"

test:
	@echo "Running go test..."
	@$(GO) test ./... -count=1

clean:
	@rm -rf $(OUTPUT_DIR)
	@echo "Cleaned: $(OUTPUT_DIR)"

help:
	@echo "make doctor        - 检查 go / xcode / gomobile 环境"
	@echo "make tools         - 安装 gomobile/gobind"
	@echo "make ios           - 生成 OpenMesh.xcframework (ios + iossimulator, iOS>=15)"
	@echo "make ios-fast-sim  - 快速验证：仅生成模拟器 arm64 的 xcframework"
	@echo "make test          - go test ./..."
	@echo "make clean         - 清理产物"
