DEVELOPER_DIR := $(if $(wildcard /Applications/Xcode.app/Contents/Developer),/Applications/Xcode.app/Contents/Developer,$(shell xcode-select -p))
export DEVELOPER_DIR

.PHONY: bootstrap generate build test lint phase2 phase5
bootstrap:
	@scripts/bootstrap.sh
generate:
	@command -v xcodegen >/dev/null && xcodegen generate || echo "xcodegen unavailable; Package.swift remains usable"
build:
	swift build
test:
	swift test
lint:
	@scripts/lint.sh
phase2:
	@echo "Phase 2 capture/image analysis is not implemented yet."
phase5:
	@echo "Phase 5 browser extension/native host is not implemented yet."

