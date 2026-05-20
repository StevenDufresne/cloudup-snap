# CloudupSnap

A macOS menubar app that captures screen regions, annotates them, and uploads
to Cloudup, paying per upload in USDC on Base Sepolia via the
MPP / x402-style protocol implemented by
[`tellyworth/mpp-remote`](https://github.com/tellyworth/mpp-remote).

Plan 1 (the library + CLI) and Plan 2 (the macOS app) are both implemented.

- `CloudupSnapCore` — Swift library handling the MCP + payment + upload pipeline.
- `cloudupsnap-cli` — CLI binary that demonstrates an end-to-end paid upload.
- `Cloudup Snap.app` — menubar app: ⌘⇧2 to capture, annotate, share.

## Build

```sh
swift build           # debug
swift build -c release # release
make app              # produce "build/Cloudup Snap.app"
```

## Test

```sh
swift test
```

51 unit tests + 1 viem-parity cross-check + 1 snapshot-tested renderer + 1 gated
live-network integration test.

Gated tests:
- `CLOUDUPSNAP_KEYCHAIN_TESTS=1` — Keychain integration tests.
- `CLOUDUPSNAP_INTEGRATION=1` + `CLOUDUPSNAP_TEST_WALLET_KEY=0x<key>` —
  live paid upload against Cloudup stage + Base Sepolia.

## Running the macOS app

```sh
make app
open "build/Cloudup Snap.app"
```

On first launch:

1. Grant **Screen Recording** permission in System Settings → Privacy & Security
   → Screen Recording. Quit and relaunch the app after granting (macOS requires it).
2. Grant **Accessibility** permission for the global hotkey.
3. The onboarding window shows your wallet address. Fund it on Base Sepolia
   (need ~$0.10 USDC + a tiny bit of ETH for gas) from a faucet:
   - [Coinbase CDP faucet](https://portal.cdp.coinbase.com/products/faucet)
   - [Circle USDC faucet](https://faucet.circle.com/)

   Already have a wallet? Expand **"Already have a wallet? Import a private
   key"** in the onboarding window and paste a 32-byte hex key — it gets
   written to the Keychain and the auto-generated wallet is replaced.

Then **press ⌘⇧2** anywhere to capture a region. The annotation editor opens
with the region as background; pick a tool (arrow / line / rect / ellipse /
text / pen / blur / sticker), draw, then hit **Upload**. The share URL lands on
your clipboard with a notification.

The CLI and the app share the same Keychain-backed wallet
(`com.bongnam.cloudupsnap / default`), so anything funded for the CLI is
already usable from the app.

## CLI usage

Get the wallet address:

```sh
.build/release/cloudupsnap-cli address
```

Upload anything:

```sh
.build/release/cloudupsnap-cli upload path/to/file.png
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

