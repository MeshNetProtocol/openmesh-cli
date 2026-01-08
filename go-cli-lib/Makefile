# 获取 iOS SDK 路径
IOS_SDK_PATH = $(shell xcrun --sdk iphoneos --show-sdk-path)
SIMULATOR_SDK_PATH = $(shell xcrun --sdk iphonesimulator --show-sdk-path)

# 编译目标平台
TARGETS = ios android darwin linux windows
GO_SOURCES = $(shell find . -name "*.go" -type f)

# 包路径和输出目录
PACKAGE = .
OUTPUT_DIR = ./lib

.PHONY: all clean ios ios-sim darwin linux windows

all: ios

ios:
	@echo "构建 iOS 版本库文件 (arm64)..."
	GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CGO_CFLAGS="-isysroot ${IOS_SDK_PATH}" go build -buildmode=c-archive -o $(OUTPUT_DIR)/libopenmesh.a $(PACKAGE)
	@echo "iOS arm64 库文件编译完成: $(OUTPUT_DIR)/libopenmesh.a"

ios-sim:
	@echo "构建 iOS 模拟器版本库文件 (amd64)..."
	GOOS=ios GOARCH=amd64 CGO_ENABLED=1 CGO_CFLAGS="-isysroot ${SIMULATOR_SDK_PATH}" go build -buildmode=c-archive -o $(OUTPUT_DIR)/libopenmesh-sim.a $(PACKAGE)
	@echo "iOS 模拟器库文件编译完成: $(OUTPUT_DIR)/libopenmesh-sim.a"

ios-universal: ios ios-sim
	@echo "合并真机和模拟器库文件..."
	mkdir -p $(OUTPUT_DIR)
	lipo -create $(OUTPUT_DIR)/libopenmesh.a $(OUTPUT_DIR)/libopenmesh-sim.a -output $(OUTPUT_DIR)/libopenmesh-universal.a
	@echo "iOS 通用库文件编译完成: $(OUTPUT_DIR)/libopenmesh-universal.a"

darwin:
	@echo "构建 macOS 版本库文件..."
	GOOS=darwin GOARCH=amd64 CGO_ENABLED=1 go build -buildmode=c-archive -o $(OUTPUT_DIR)/libopenmesh-mac.a $(PACKAGE)
	@echo "macOS 库文件编译完成: $(OUTPUT_DIR)/libopenmesh-mac.a"

clean:
	rm -rf $(OUTPUT_DIR)/

install-deps:
	go mod tidy

init:
	mkdir -p $(OUTPUT_DIR)

build: init ios darwin

help:
	@echo "make ios              - 构建 iOS 版本库文件 (arm64)"
	@echo "make ios-sim          - 构建 iOS 模拟器版本库文件 (amd64)"
	@echo "make ios-universal    - 构建 iOS 通用库文件 (合并真机和模拟器)"
	@echo "make darwin           - 构建 macOS 版本库文件"
	@echo "make clean            - 清理编译产物"
	@echo "make build            - 构建所有平台库文件"
	@echo "make install-deps     - 安装依赖"