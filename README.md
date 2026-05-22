# CloudupSnap

A macOS menubar app that captures screenshots and screen recordings,
annotates them, and uploads to Cloudup. Each upload is paid in USDC on
Base Sepolia via the MPP / x402-style protocol implemented by
[`tellyworth/mpp-remote`](https://github.com/tellyworth/mpp-remote).

- `CloudupSnapCore` — Swift library: MCP + payment + upload pipeline.
- `cloudupsnap-cli` — minimal CLI demonstrating an end-to-end paid upload.
- `Cloudup Snap.app` — the menubar app.

## Build

```sh
swift build              # debug
swift build -c release   # release
make app                 # produce "build/Cloudup Snap.app"
```

## Test

```sh
swift test
```

Gated tests:
- `CLOUDUPSNAP_KEYCHAIN_TESTS=1` — Keychain integration tests.
- `CLOUDUPSNAP_INTEGRATION=1` + `CLOUDUPSNAP_TEST_WALLET_KEY=0x<key>` —
  live paid upload against Cloudup stage + Base Sepolia.

## Running the app

```sh
make app
open "build/Cloudup Snap.app"
```

On first launch:

1. Grant **Screen Recording** in System Settings → Privacy & Security
   → Screen Recording, then relaunch (macOS requires it).
2. Grant **Accessibility** so the ⌘⇧2 global hotkey works.
3. Fund the wallet shown in onboarding: ~$0.10 USDC plus a tiny bit of
   ETH for gas on Base Sepolia. Faucets:
   [Coinbase CDP](https://portal.cdp.coinbase.com/products/faucet),
   [Circle](https://faucet.circle.com/). Or expand
   **Already have a wallet?** in the onboarding window to paste a
   32-byte hex private key — it's written to the Keychain in place of
   the auto-generated one.

Then **⌘⇧2** captures a region (annotate → Upload → share URL on the
clipboard); the menubar also records video, with an optional Convert to
GIF step before upload.

The CLI and the app share the same Keychain-backed wallet
(`com.bongnam.cloudupsnap / default`).

## CLI

```sh
.build/release/cloudupsnap-cli address                  # wallet address
.build/release/cloudupsnap-cli upload path/to/file.png  # prints share URL
```
