# Screenshotter

A macOS menubar app that captures screen regions, annotates them, and uploads
to Cloudup, paying per upload in USDC on Base Sepolia via the
[MPP / x402](docs/superpowers/protocol/mpp-x402.md)-style protocol implemented
by [`tellyworth/mpp-remote`](https://github.com/tellyworth/mpp-remote).

Plan 1 (the library + CLI) and Plan 2 (the macOS app) are both implemented.

- `ScreenshotterCore` — Swift library handling the MCP + payment + upload pipeline.
- `screenshotter-cli` — CLI binary that demonstrates an end-to-end paid upload.
- `Screenshotter.app` — menubar app: ⌘⇧2 to capture, annotate, share.

## Build

```sh
swift build           # debug
swift build -c release # release
make app              # produce build/Screenshotter.app
```

## Test

```sh
swift test
```

51 unit tests + 1 viem-parity cross-check + 1 snapshot-tested renderer + 1 gated
live-network integration test.

Gated tests:
- `SCREENSHOTTER_KEYCHAIN_TESTS=1` — Keychain integration tests.
- `SCREENSHOTTER_INTEGRATION=1` + `SCREENSHOTTER_TEST_WALLET_KEY=0x<key>` —
  live paid upload against Cloudup stage + Base Sepolia.

## Running the macOS app

```sh
make app
open build/Screenshotter.app
```

On first launch:

1. Grant **Screen Recording** permission in System Settings → Privacy & Security
   → Screen Recording. Quit and relaunch the app after granting (macOS requires it).
2. Grant **Accessibility** permission for the global hotkey.
3. The onboarding window shows your wallet address. Fund it on Base Sepolia
   (need ~$0.10 USDC + a tiny bit of ETH for gas) from a faucet:
   - [Coinbase CDP faucet](https://portal.cdp.coinbase.com/products/faucet)
   - [Circle USDC faucet](https://faucet.circle.com/)

Then **press ⌘⇧2** anywhere to capture a region. The annotation editor opens
with the region as background; pick a tool (arrow / line / rect / ellipse /
text / pen / blur / sticker), draw, then hit **Upload**. The share URL lands on
your clipboard with a notification.

The CLI and the app share the same Keychain-backed wallet
(`com.bongnam.screenshotter / default`), so anything funded for the CLI is
already usable from the app.

## CLI usage

Get the wallet address:

```sh
.build/release/screenshotter-cli address
```

Upload anything:

```sh
.build/release/screenshotter-cli upload path/to/file.png
# prints: https://stage-cloudup.com/s/...
```

## Verified end-to-end

- Wallet generation + Keychain persistence: working.
- secp256k1 + EIP-1559 transaction signing: cross-validated byte-for-byte
  against `viem` 2.48.
- MCP Streamable HTTP transport + `initialize` session lifecycle: working
  against `https://api.stage-cloudup.com/mcp/public`.
- MPP/x402 payment flow (on-chain USDC `transfer()` settlement + credential
  retry): working against Base Sepolia.
- Cloudup `quick_upload` + `tools/call` content-array unwrapping: working;
  returns a real share URL.

## Docs

- Protocol notes: [`docs/superpowers/protocol/mpp-x402.md`](docs/superpowers/protocol/mpp-x402.md)
- Design spec: [`docs/superpowers/specs/2026-05-12-screenshotter-design.md`](docs/superpowers/specs/2026-05-12-screenshotter-design.md)
- Plan 1 (core + CLI): [`docs/superpowers/plans/2026-05-12-screenshotter-core-and-cli.md`](docs/superpowers/plans/2026-05-12-screenshotter-core-and-cli.md)
- Plan 2 (macOS app): [`docs/superpowers/plans/2026-05-12-screenshotter-macos-app.md`](docs/superpowers/plans/2026-05-12-screenshotter-macos-app.md)
