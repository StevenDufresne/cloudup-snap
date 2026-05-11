# Screenshotter

A macOS app (forthcoming) that captures, annotates, and uploads screenshots
to Cloudup, paying per upload in USDC on Base Sepolia via MPP/x402.

This repository currently contains:
- `ScreenshotterCore` — the Swift library that handles the MCP + payment + upload pipeline.
- `screenshotter-cli` — a CLI binary that demonstrates an end-to-end paid upload.

The macOS app (Plan 2) is forthcoming.

## Build

    swift build

## Test

    swift test

## CLI usage (after Plan 1)

    screenshotter-cli upload path/to/file.png
