DEVELOPER_DIR := $(if $(wildcard /Applications/Xcode.app/Contents/Developer),/Applications/Xcode.app/Contents/Developer,$(shell xcode-select -p))
export DEVELOPER_DIR
export CLANG_MODULE_CACHE_PATH := $(CURDIR)/.build/clang-module-cache
export SWIFTPM_MODULECACHE_OVERRIDE := $(CURDIR)/.build/swiftpm-module-cache
export XDG_CACHE_HOME := $(CURDIR)/.build/cache

.PHONY: bootstrap generate build test lint phase2 phase5
bootstrap:
	@scripts/bootstrap.sh
generate:
	@command -v xcodegen >/dev/null && xcodegen generate || echo "xcodegen unavailable; Package.swift remains usable"
build:
	swift build --disable-sandbox
test:
	swift test --disable-sandbox
lint:
	@scripts/lint.sh
phase2:
	@echo "Phase 2 capture/image analysis is not implemented yet."
phase5:
	@echo "Phase 5 browser extension/native host is not implemented yet."
