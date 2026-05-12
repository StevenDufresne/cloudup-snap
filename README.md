# Screenshotter

A macOS app (forthcoming) that captures, annotates, and uploads screenshots
to Cloudup, paying per upload in USDC on Base Sepolia via the
[MPP / x402](docs/superpowers/protocol/mpp-x402.md)-style protocol implemented
by [`tellyworth/mpp-remote`](https://github.com/tellyworth/mpp-remote).

This repository currently contains **Plan 1**:

- `ScreenshotterCore` — Swift library handling the MCP + payment + upload pipeline.
- `screenshotter-cli` — CLI binary that demonstrates an end-to-end paid upload.

Plan 2 (the macOS app — capture, annotation, menubar, hotkey) is forthcoming.

## Build

```sh
swift build           # debug
swift build -c release # release; binary at .build/release/screenshotter-cli
```

## Test

```sh
swift test
```

42 unit tests + 1 viem-parity cross-check + 1 gated live-network integration test.

The Keychain integration tests are gated behind `SCREENSHOTTER_KEYCHAIN_TESTS=1`.
The paid-upload integration test is gated behind `SCREENSHOTTER_INTEGRATION=1`
plus `SCREENSHOTTER_TEST_WALLET_KEY=0x<funded testnet key>`.

## CLI usage

Get the CLI's wallet address (generated on first run, stored in macOS Keychain
under the `com.bongnam.screenshotter` service):

```sh
screenshotter-cli address
```

Fund that address with **Base Sepolia ETH (for gas)** and **Base Sepolia USDC
(for the upload fee, ~0.05 USDC per upload)** from a faucet:

- Coinbase CDP faucet: <https://portal.cdp.coinbase.com/products/faucet>
- Circle USDC faucet: <https://faucet.circle.com/>

Then upload anything:

```sh
screenshotter-cli upload path/to/file.png
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

Protocol notes are in [`docs/superpowers/protocol/mpp-x402.md`](docs/superpowers/protocol/mpp-x402.md).
Design spec: [`docs/superpowers/specs/2026-05-12-screenshotter-design.md`](docs/superpowers/specs/2026-05-12-screenshotter-design.md).
Implementation plan: [`docs/superpowers/plans/2026-05-12-screenshotter-core-and-cli.md`](docs/superpowers/plans/2026-05-12-screenshotter-core-and-cli.md).
