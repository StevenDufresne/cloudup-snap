# CloudupSnap — Design

A macOS menubar app that captures, annotates, and uploads screenshots to Cloudup, paying for each upload in USDC on Base Sepolia via the Machine Payment Protocol (MPP / x402).

Working name: **CloudupSnap**. Trivial to rename later — the name appears only in the bundle identifier, menubar tooltip, and notification text.

## Goals

- One-keystroke capture → annotate → public share URL on the clipboard.
- Crypto payment as invisible plumbing. The wallet exists, the app uses it, the user sees it only when it runs dry.
- Native macOS feel: small binary, fast, no Electron/web stack.
- Trivially shareable: an unsigned `.app` hand-distributed to a few friends. Each install carries its own wallet.

## Non-goals (v1)

- Mac App Store distribution.
- Cross-platform (Windows, Linux, web).
- Screen recordings — designed for as future work; explicitly out of scope for v1.
- Cloud sync, history, search.
- Fancy AI/local-model annotation features.
- Configurable hotkey or per-user max-spend cap.
- Account system, multi-user, sharing within the app.

## Audience and distribution

- **Audience:** the author and a small circle of friends.
- **Distribution:** built locally with Xcode, exported as an unsigned `.app`, zipped and sent. Recipients right-click → Open the first time to bypass Gatekeeper.
- **No Apple Developer Program for v1.** Signing/notarization deferred.

## Architecture

One process. Background-only menubar app (`LSUIElement = YES`, no Dock icon). Internally split into small, single-purpose Swift modules.

```
┌─────────────────────────────────────────────────────────────┐
│                    CloudupSnap.app                        │
│                                                             │
│  ┌──────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │ Menubar  │    │   Hotkey     │    │   Onboarding     │   │
│  │ icon +   │    │   manager    │    │   coordinator    │   │
│  │  menu    │    │  (⌘⇧2)       │    │ (first run +     │   │
│  └────┬─────┘    └──────┬───────┘    │  permission UX)  │   │
│       │                 │            └──────────────────┘   │
│       └────────┬────────┘                                   │
│                ▼                                            │
│         ┌──────────────────┐                                │
│         │ CaptureCoordinator                                │
│         │ (state machine)  │                                │
│         └────────┬─────────┘                                │
│                  │                                          │
│   ┌──────────────┼─────────────────────┐                    │
│   ▼              ▼                     ▼                    │
│ ┌─────────┐  ┌────────────┐    ┌──────────────────┐         │
│ │ Capture │  │Annotation  │    │ Uploader         │         │
│ │ Service │  │  Editor    │    │  └─ MCPClient    │         │
│ │ (SCK)   │  │ (SwiftUI)  │    │  └─ PaymentClient│         │
│ └─────────┘  └────────────┘    └────────┬─────────┘         │
│                                         │                   │
│                                         ▼                   │
│                                    ┌─────────┐              │
│                                    │ Wallet  │ ◀── Keychain │
│                                    │(EIP-712)│              │
│                                    └─────────┘              │
│                                                             │
│  Cross-cutting: ClipboardService, NotificationService,      │
│                 FundingPanel, OnboardingCoordinator         │
└─────────────────────────────────────────────────────────────┘
```

`CaptureCoordinator` is the brain. State machine:

- `Idle → Selecting` on hotkey / menubar invocation.
- `Selecting → Editing` when the user finishes the rubber-band / picks a window / picks a screen.
- `Selecting → Idle` on Esc or capture error.
- `Editing → Uploading` when the user hits Upload (the commit point — first place the wallet signs).
- `Editing → Idle` on editor close without uploading.
- `Uploading → Done` on a successful upload, which copies the URL, posts the toast, and immediately re-enters `Idle`.
- `Uploading → Editing` on any recoverable failure (network, payment cap exceeded, insufficient funds, malformed quote). The editor stays alive, the Upload button is re-enabled, and FundingPanel may be layered on top depending on the failure kind (see Error handling).

The coordinator owns no UI itself; it drives the other modules.

## Approach decision

**Pure SwiftUI / AppKit native.** Rejected alternatives:
- *Tauri (Rust + WebView):* screen capture story on macOS is the hardest part of this app, and Tauri fights macOS for it. We'd end up writing a native helper anyway. Native wins.
- *Electron:* 150 MB binary for an app whose entire UI surface is a borderless capture overlay, an annotation canvas, a toast, and a funding panel. Massive overkill.
- *Swift + tiny Rust crypto helper (hybrid):* viable fallback if Swift wallet libs prove painful. The wallet module is a single boundary; we can switch later without rearchitecting.

## Components

| Module | Responsibility | Notes |
|---|---|---|
| `MenubarController` | Owns the `NSStatusItem`. Builds the menu: capture mode picker, "Wallet…" → opens FundingPanel, "Quit". | AppKit, ~80 LOC. |
| `HotkeyManager` | Registers the ⌘⇧2 global hotkey. Invokes `CaptureCoordinator.startCapture(.region)` on press. | `MASShortcut` or Carbon API. Requires Accessibility permission. |
| `OnboardingCoordinator` | First-run flow. Prompts for Screen Recording + Accessibility permissions with deep links to System Settings. Then shows wallet address + QR + instructions to fund from a Base Sepolia faucet. | SwiftUI window. Runs once; gated by a `UserDefaults` flag. Also re-invoked if a permission gets revoked later. |
| `CaptureCoordinator` | State machine. Receives a `CaptureMode`, drives `CaptureService → AnnotationEditor → Uploader`. Handles cancellation and error transitions. | Pure Swift, no UI. Easy to test. |
| `CaptureService` | Wraps ScreenCaptureKit. Three modes: region (borderless overlay across all screens for rubber-band selection), window (window picker), full-screen (display picker). Output is `CGImage`. | **Non-trivial.** Region overlay must handle multi-monitor + mixed Retina densities + not leak click events to underlying apps. |
| `AnnotationEditor` | Borderless window. Background: the captured `CGImage`. Overlay: SwiftUI canvas with resizable annotation elements. Tools palette: select, arrow, line, rectangle, ellipse, text, pen, blur/redact, sticker picker. Emits an `AnnotationDocument` on Cmd+↩ (or Upload button). | Largest UI surface in the app. |
| `AnnotationModel` | Element types: `Line`, `Rect`, `Ellipse`, `Text`, `Sticker`, `PenStroke`, `BlurRegion`. Each has position, size, style, z-order. Supports hit-testing, selection, drag, resize handles. | Pure value types. Heavily unit-tested. |
| `UndoStack` | Command pattern over `AnnotationModel`. Every add/move/resize/delete/style-change is a reversible command. ⌘Z / ⌘⇧Z. Capped at 50 entries. | Lives inside `AnnotationEditor`. |
| `Renderer` | Flattens `AnnotationDocument` (background `CGImage` + ordered elements) → PNG `Data`. Honors element z-order, alpha, blur region effects. | Core Graphics. Snapshot-tested. |
| `Uploader` | Public API: `upload(data: Data, filename: String, mime: String) → URL`. Internally drives `MCPClient.callTool("quick_upload", …)` and routes 402 challenges through `PaymentClient`. | |
| `MCPClient` | JSON-RPC 2.0 client over Streamable HTTP (POST + SSE) for MCP. Surfaces: `initialize`, `tools/list`, `tools/call`. | ~300 LOC. Reusable for any MCP server. |
| `PaymentClient` | Implements the MPP/x402 client flow. Receives a 402/-32042 response from `MCPClient`, parses the EIP-712 quote, validates `amount ≤ MAX_AMOUNT_USD` (hardcoded $0.50), signs via `Wallet`, attaches the payment header, asks `MCPClient` to retry. On failure, surfaces a typed error to `Uploader` distinguishing `.insufficientFunds(needed, haveUSDC, haveETH)` (routes to `FundingPanel`) from `.capExceeded(amount)`, `.signatureFailed`, and `.other(underlying)` (route to a toast). | **Non-trivial.** Spec'd by reading `github:tellyworth/mpp-remote` — that is the canonical reference implementation. |
| `Wallet` | secp256k1 keypair stored in Keychain. Generated on first launch. Public surface: `address`, `signEIP712(typedData) → Signature`, `balanceUSDC() → Decimal`, `balanceETH() → Decimal`. Balance queries hit a Base Sepolia RPC (public endpoint configurable). | Uses `secp256k1.swift` SwiftPM dependency + a thin EIP-712 typed-data hashing layer. |
| `ClipboardService` | `copy(_ url: URL)` → `NSPasteboard.general`. | ~10 LOC. |
| `NotificationService` | `toast(_ message: String, url: URL? = nil)` via UserNotifications. Tapping the notification re-copies the URL. | ~30 LOC. |
| `FundingPanel` | SwiftUI window. Shows wallet address (selectable text + copy button), QR code (CIFilter `QRCodeGenerator`), current USDC and ETH balances (live-refreshed), "Retry upload" button. | Opens on settlement failure. Stays in front of the editor so the user keeps their annotations. |

## Data flow (happy path)

```
hotkey press (⌘⇧2)
   │
   ▼
HotkeyManager ──▶ CaptureCoordinator (Idle → Selecting)
                       │
                       ▼
                 CaptureService
                  ├─ region: borderless overlay across all screens
                  │          → user drags rubber band → CGImage
                  ├─ window: window picker → CGImage
                  └─ full:   display picker → CGImage
                       │
                       ▼
            CaptureCoordinator (Selecting → Editing)
                       │
                       ▼
                 AnnotationEditor (borderless window)
                  background: CGImage
                  overlay:    SwiftUI canvas, tools palette
                  output:     AnnotationDocument on Cmd+↩ / Upload
                       │
                       ▼
            CaptureCoordinator (Editing → Uploading)
                       │
                       ▼
                  Renderer.flatten(doc) → PNG Data
                       │
                       ▼
                  Uploader.upload(data, "screenshot.png", "image/png")
                       │
                       │   ┌────────────────────────────────────┐
                       └──▶│ MCPClient.callTool("quick_upload") │
                           │       │                            │
                           │       ▼  402 / -32042              │
                           │ PaymentClient.handle(quote)        │
                           │   ├─ check amount ≤ MAX cap        │
                           │   ├─ Wallet.signEIP712(quote)      │
                           │   └─ return payment header         │
                           │       │                            │
                           │       ▼  retry w/ X-PAYMENT        │
                           │     share_url                      │
                           └────────────────────────────────────┘
                       │
                       ▼
            CaptureCoordinator (Uploading → Done)
                       │
            ┌──────────┴──────────┐
            ▼                     ▼
     ClipboardService      NotificationService
     .copy(share_url)      .toast("Copied: …")
                       │
                       ▼
                     Idle
```

### Commit point

The wallet only signs **after** the user hits Upload on the annotation editor. Cancelling at any prior step (Esc during region selection, closing the editor without uploading) returns to `Idle` with zero on-chain activity. The annotation editor's Upload button is the single commit point for spending.

### Pre-flight vs react-to-failure on balance

V1 attempts the upload and reacts to settlement failure rather than pre-flighting balance via RPC. Matches `mpp-remote`, saves an RPC round-trip per capture, and aligns with the "invisible plumbing" payment philosophy — the user only sees the wallet when the wallet matters.

## Annotation editor

### Tools

- **Select** (default after placing): hit-test, drag, resize via 8 corner/edge handles, delete via ⌫.
- **Arrow** / **Line** / **Rect** / **Ellipse** — click-drag to place. Style: stroke color (8-swatch palette), stroke width (3 presets), fill on/off for shapes.
- **Text** — click to place, inline edit. Font: system, sizes 12/16/24/36, bold toggle. Colors share the palette.
- **Pen** — freehand stroke. Same color palette, width slider.
- **Blur / Redact** — drag a rectangle; the underlying region of the background image gets a Gaussian blur (radius 12) in the final render.
- **Sticker** — opens a small picker popover. Built-in pack: a curated emoji subset (≈40), arrow set (8 directions), numbered pins 1–9. Click to drop at canvas center.

### Element model

```
AnnotationDocument
├── background: CGImage   (immutable)
└── elements:  [Element]  (ordered, bottom-to-top z-order)

Element  (sum type / enum):
├── id: UUID
├── frame: CGRect
├── style: { stroke, fill, fontSize, blurRadius, … }
└── payload: .line | .rect | .ellipse | .text(String) | .pen([CGPoint]) | .blur | .sticker(StickerID)
```

### Undo/redo

Command pattern. Concrete commands: `AddElement`, `RemoveElement`, `MoveElement(id, from, to)`, `ResizeElement(id, from, to)`, `ChangeStyle(id, from, to)`. Each implements `do()` / `undo()`. Stack capped at 50; bound to ⌘Z / ⌘⇧Z. Cleared when the editor closes.

### Output

Cmd+↩ or the Upload button emits the `AnnotationDocument` to `CaptureCoordinator`. `Renderer.flatten` produces PNG `Data`.

## Wallet and payment

### Wallet

- secp256k1 keypair generated on first launch.
- Private key stored as a generic password in Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- Address derived per Ethereum convention (keccak256 of uncompressed pubkey, last 20 bytes).
- Public surface kept tiny: `address`, `signEIP712`, `balanceUSDC`, `balanceETH`.

Each install gets its own wallet. There is no recovery flow in v1 — if the user wipes the app, the key is gone. The wallet is intentionally low-value (capped at $0.50/upload, on testnet) so loss is tolerable. A "show recovery phrase" feature could be added later; out of scope for v1.

### Payment

`PaymentClient` mirrors the behavior of `github:tellyworth/mpp-remote`. Implementation steps:

1. Read `mpp-remote`'s payment-handling code as the spec.
2. Reimplement the 402-challenge handler, the EIP-712 typed-data hashing, and the `X-PAYMENT` header construction in Swift.
3. Pin a `MAX_AMOUNT_USD` constant of 0.50 — same default as the reference.
4. Cross-validate a few signatures against the reference impl on a fixture quote before trusting the Swift implementation in flight.

### Networking targets

- MCP server: `https://api.stage-cloudup.com/mcp/public` (Streamable HTTP transport).
- Base Sepolia RPC (balance queries): public endpoint (e.g., `https://sepolia.base.org`). Configurable in source.

## Onboarding (first-run)

A single SwiftUI window, three steps:

1. **Permissions.** Two rows, one each for Screen Recording and Accessibility. Each shows status (granted/denied) and a button that deep-links to the relevant System Settings pane.
2. **Wallet.** Display the freshly-generated address and a QR. Short copy: "This app pays a few cents per upload in USDC on Base Sepolia. Fund this address from a faucet to get started — try [Coinbase CDP Faucet](https://portal.cdp.coinbase.com/products/faucet) (gets you ETH and USDC) or [Circle's USDC faucet](https://faucet.circle.com/) (USDC only)." Live-refreshed balance below.
3. **Ready.** "Press ⌘⇧2 anywhere to capture. Press Esc to cancel." A "Done" button dismisses the window and sets the `onboarded` flag.

Re-invoked if a permission is revoked later, jumping to step 1.

## Error handling

Grouped by origin. Each row: condition → user-visible behavior → notes.

| Origin | Condition | Behavior | Notes |
|---|---|---|---|
| Permissions | Screen Recording missing | `OnboardingCoordinator` opens to step 1 with deep link | |
| Permissions | Accessibility missing | Same | |
| Hotkey | Conflict with another app | Hotkey silently fails; menubar still works. Configurable hotkey is future work. | |
| Capture | User presses Esc | Overlay closes; coordinator → Idle. | |
| Capture | ScreenCaptureKit error (display unplugged, GPU error) | Toast: "Capture failed — try again". → Idle. | |
| Editor | User closes without uploading | Discard document. → Idle. No upload, no charge. | |
| Network | MCP connection fails | Toast: "Couldn't reach Cloudup — check connection". Editor stays open; Upload button re-enabled. | |
| Network | MCP request timeout (>30s) | Same | |
| Payment | Quote amount > `MAX_AMOUNT_USD` cap | Toast: "Upload cost ($X) exceeds your $0.50 cap". Editor stays open. | Cap surfaceable in a future settings pane. |
| Payment | Signature failed (Keychain locked / corrupted) | Toast: "Wallet unavailable — restart app". | Vanishingly rare. |
| Payment | Settlement reverted: insufficient USDC or ETH for gas | `FundingPanel` opens. Editor stays open behind it. User funds wallet externally, hits Retry. | Main reason FundingPanel exists. |
| Payment | Settlement reverted: any other reason (RPC down, malformed quote) | Toast: "Payment failed — try again later". Editor stays open. Log details. | Catch-all. |
| Post-upload | Cloudup returns 5xx after settlement (paid but no URL) | Toast: "Upload paid but server didn't respond — see logs for tx hash". | Should be vanishingly rare. Tx hash always logged for manual recovery. |

### Logging

Structured logs via `OSLog` with subsystem `com.bongnam.cloudupsnap`. Mirrored to `~/Library/Logs/CloudupSnap/app.log` for forensic review. Every payment attempt logs: timestamp, MCP tool name, quote amount, signed tx hash (when available), result. Captures log dimensions and outcome only — never image contents.

## Testing

### Unit (XCTest)

| Module | Coverage |
|---|---|
| `AnnotationModel` | Element creation, serialization round-trip, hit-testing, z-order, drag/resize coordinate transforms. |
| `UndoStack` | Round-trip every command type. Stack cap at 50 enforced. |
| `Wallet` | EIP-712 signing against fixed test vectors (known private key + typed data → known signature). Address derivation from a known pubkey. |
| `PaymentClient` | Mocked `MCPClient` feeds canned 402/-32042 responses. Assert retry carries a valid `X-PAYMENT` header. Cap-rejection branch blocks the retry. Settlement-failure paths surface the expected typed error. |
| `MCPClient` | JSON-RPC 2.0 framing, request/response correlation, SSE event parsing. Mocked `URLSession`. |
| `Renderer` | Snapshot tests via `swift-snapshot-testing`. Fixed `AnnotationDocument` → render PNG → byte-compare to golden image. Catches "exported PNG looks different from editor preview" regressions. |

### Integration (gated)

- End-to-end paid upload against the live `https://api.stage-cloudup.com/mcp/public` using a dedicated test wallet with a small balance. Asserts a real `share_url` comes back.
- Gated behind `CLOUDUPSNAP_INTEGRATION=1` + the test wallet key as a CI secret.

### Manual checklist (run before sharing each build)

- Multi-monitor region selection (Retina + non-Retina mixed).
- External display unplugged mid-capture.
- Every annotation tool. Undo/redo through a 10-step sequence.
- Resize handles on every shape type. Z-order swap.
- First-run permission flow on a clean macOS user. Re-permission flow after revoke.
- Notification click → re-copies URL to clipboard.
- Funding panel: address QR scans correctly, retry succeeds after funding.
- App relaunch with existing wallet: wallet persists, no re-onboarding.
- Fresh install: empty wallet, onboarding shown.

### CI

- Local `xcodebuild test` on push for the unit suite.
- SwiftLint on push.
- No coverage targets in v1.

## Open questions / future work

- **Configurable hotkey.** Hardcoded ⌘⇧2 in v1. Add a Preferences window with hotkey binding when a friend's keyboard layout breaks it.
- **Configurable max-spend cap.** Hardcoded `MAX_AMOUNT_USD = 0.50`. Surface in Preferences when needed.
- **Wallet recovery phrase / export.** Out of scope for v1. Tolerable because wallet value is intentionally tiny.
- **Recordings.** Future feature. Architecture is positioned to support it: ScreenCaptureKit handles video streams; `AVAssetWriter` produces MP4/HEVC; switch `Uploader` from `quick_upload` to `begin_upload` + `complete_upload` (already exposed by the same MCP server) for chunked transfer; `PaymentClient` / `Wallet` / `MCPClient` reused as-is. The recordings editor (trim/crop/cursor highlight) is a separate design.
- **Mac App Store distribution.** Out of scope. Would require sandbox-compatible hotkey (the user-facing Keyboard Shortcuts entitlement) and a Developer Program subscription.
- **Fun factor.** Local image-manipulation model features (magic eraser, generative stickers, vibe filters) explicitly deferred to a later iteration. The annotation editor's `Element` model is designed to be extensible (sum type with a `payload` enum), so adding new element kinds later is additive.
- **Multi-recipient share UI.** Currently the only share affordance is "URL on clipboard". A share-sheet variant (Mail / Messages / etc.) is a natural extension but not required for v1.

## Risks

1. **`PaymentClient` byte-correctness against the MPP reference.** Mitigation: cross-validate signatures against `mpp-remote` on a fixture quote before trusting in-flight calls. Fallback: ship a tiny Rust dylib with the reference signing if Swift proves painful.
2. **Region overlay across multi-monitor + Retina.** Classic source of off-by-pixel-density bugs. Mitigation: manual test matrix + a small XCTest helper that mocks `NSScreen` topology to exercise coordinate math.
3. **Cloudup MCP server contract drift.** The `quick_upload` schema could change. Mitigation: integration test in CI catches breakage early; tool-call schema is small and stable so far.
