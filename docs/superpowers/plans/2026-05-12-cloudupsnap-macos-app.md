# CloudupSnap macOS App Implementation Plan (Plan 2 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `CloudupSnap.app` — a macOS menubar app that captures a screen region (or window / full screen) via a global ⌘⇧2 hotkey, opens a SwiftUI annotation editor with the basic kit (shapes, text, pen, blur, stickers, undo/redo), uploads the flattened PNG to Cloudup via the Plan 1 library, and drops the share URL on the clipboard with a notification toast.

**Architecture:** Native SwiftUI / AppKit on top of the `CloudupSnapCore` library from Plan 1. Single `LSUIElement` app — menubar icon, no Dock icon. `CaptureCoordinator` state machine drives the flow `Idle → Selecting → Editing → Uploading → Done` across modules with single-responsibility seams. The wallet is shared with the Plan 1 CLI via the same Keychain entry (`com.bongnam.cloudupsnap / default`), so any funds the CLI's wallet has are immediately usable from the app.

**Tech Stack:**
- Swift 6, Swift Package Manager, no Xcode project
- SwiftUI + AppKit (NSStatusItem, NSWindow for borderless overlays, NSPasteboard, UserNotifications, ScreenCaptureKit, Carbon hotkey API)
- `swift-snapshot-testing` (new dep) for `Renderer` golden-image tests
- `CloudupSnapCore` (Plan 1's library) for the upload pipeline
- App bundling via a `scripts/bundle.sh` script — no Xcode project file

**Spec:** `docs/superpowers/specs/2026-05-12-cloudupsnap-design.md`
**Plan 1:** `docs/superpowers/plans/2026-05-12-cloudupsnap-core-and-cli.md`
**Branch:** create `feature/macos-app` off `feature/core-and-cli` (the Plan 1 library is required).

---

## File Structure

```
/Users/bongnam/dev/cloudupsnap/
├── Package.swift                                # adds CloudupSnap executable target + swift-snapshot-testing dep
├── scripts/
│   └── bundle.sh                                # wraps the binary into CloudupSnap.app/Contents/{MacOS,Info.plist}
├── Sources/
│   ├── CloudupSnapCore/                       # Plan 1 — unchanged except Wallet balance helpers
│   │   └── Wallet/Wallet+Balance.swift          # NEW: balanceUSDC(...), balanceETH(...)
│   ├── CloudupSnap/                           # NEW: GUI app
│   │   ├── App/
│   │   │   ├── CloudupSnapApp.swift           # @main + NSApplicationDelegate
│   │   │   ├── Info.plist.template              # LSUIElement, NSScreenCaptureUsageDescription, etc.
│   │   │   └── Assets/
│   │   │       └── stickers/                    # PNG sticker assets (emoji renders + arrows)
│   │   ├── Coordination/
│   │   │   └── CaptureCoordinator.swift         # state machine
│   │   ├── Menubar/
│   │   │   └── MenubarController.swift          # NSStatusItem + menu
│   │   ├── Hotkey/
│   │   │   └── HotkeyManager.swift              # Carbon RegisterEventHotKey for ⌘⇧2
│   │   ├── Capture/
│   │   │   ├── CaptureService.swift             # ScreenCaptureKit wrapper
│   │   │   ├── RegionSelectionOverlay.swift     # borderless transparent window for rubber-band
│   │   │   └── DisplayPicker.swift              # tiny popover for full-screen mode
│   │   ├── Annotation/
│   │   │   ├── AnnotationModel.swift            # Element types, hit-testing, z-order
│   │   │   ├── AnnotationDocument.swift         # background CGImage + ordered elements
│   │   │   ├── UndoStack.swift                  # command pattern, ⌘Z/⌘⇧Z
│   │   │   ├── AnnotationEditor.swift           # SwiftUI editor (NSHostingView in NSWindow)
│   │   │   ├── AnnotationCanvas.swift           # SwiftUI Canvas + interactive elements
│   │   │   ├── ToolsPalette.swift               # SwiftUI tool picker + color/stroke pickers
│   │   │   └── Stickers.swift                   # built-in sticker pack registry
│   │   ├── Render/
│   │   │   └── Renderer.swift                   # AnnotationDocument → PNG Data via CGContext
│   │   ├── Onboarding/
│   │   │   └── OnboardingCoordinator.swift      # first-run permissions + wallet funding UI
│   │   ├── Funding/
│   │   │   └── FundingPanel.swift               # address QR + balances + retry button
│   │   ├── Services/
│   │   │   ├── ClipboardService.swift           # NSPasteboard wrapper
│   │   │   └── NotificationService.swift        # UserNotifications wrapper
│   │   └── Wallet/
│   │       └── WalletProvider.swift             # shared Keychain wallet for the app
│   └── cloudupsnap-cli/                       # Plan 1 — unchanged
└── Tests/
    └── CloudupSnapTests/                      # NEW test target for the GUI logic
        ├── AnnotationModelTests.swift
        ├── UndoStackTests.swift
        ├── RendererTests.swift                  # snapshot tests against golden PNGs
        ├── HotkeyManagerTests.swift             # mocked (Carbon registration is system-level)
        └── Fixtures/
            └── __Snapshots__/                   # auto-generated golden images
```

Total NEW Swift code: ~1500 LOC across 25 files. Most of the GUI tasks are SwiftUI + AppKit boilerplate. The hard parts are the region overlay (multi-monitor + Retina) and the Renderer (must match what the editor shows).

---

## Phase 0 — App scaffolding

### Task 1: Branch off and add the CloudupSnap executable target

**Files:**
- Modify: `Package.swift`

- [ ] **Step 1: Branch**

```
cd /Users/bongnam/dev/cloudupsnap
git checkout -b feature/macos-app feature/core-and-cli
git status
```

- [ ] **Step 2: Add the executable target + snapshot-testing dep**

Edit `Package.swift`. Add the dep:

```swift
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
```

Add the executable target and a tests target:

```swift
        .executableTarget(
            name: "CloudupSnap",
            dependencies: ["CloudupSnapCore"],
            resources: [.copy("App/Info.plist.template"), .copy("App/Assets")]
        ),
        .testTarget(
            name: "CloudupSnapTests",
            dependencies: [
                "CloudupSnap",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
```

Add to `products:`:

```swift
        .executable(name: "CloudupSnap", targets: ["CloudupSnap"]),
```

- [ ] **Step 3: Add a placeholder source so the target compiles**

`Sources/CloudupSnap/Placeholder.swift`:

```swift
// Placeholder so the executable target compiles before the real @main lands.
@main
struct Placeholder {
    static func main() {}
}
```

- [ ] **Step 4: Verify build**

```
swift build --product CloudupSnap
```

Expected: success.

- [ ] **Step 5: Commit**

```
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -am "$(cat <<'EOF'
Add CloudupSnap executable target + snapshot-testing dep

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Info.plist template + app bundling script

**Files:**
- Create: `Sources/CloudupSnap/App/Info.plist.template`
- Create: `scripts/bundle.sh`
- Modify: `Makefile`

- [ ] **Step 1: Write `Sources/CloudupSnap/App/Info.plist.template`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>CloudupSnap</string>
  <key>CFBundleIdentifier</key><string>com.bongnam.cloudupsnap</string>
  <key>CFBundleName</key><string>CloudupSnap</string>
  <key>CFBundleDisplayName</key><string>CloudupSnap</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Steve Dufresne</string>
  <key>NSScreenCaptureDescription</key>
  <string>CloudupSnap captures regions of your screen to annotate and share.</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>CloudupSnap sends notifications and posts to the clipboard.</string>
</dict>
</plist>
```

- [ ] **Step 2: Write `scripts/bundle.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
APP_NAME="CloudupSnap"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/build/$APP_NAME.app"
TEMPLATE="$ROOT/Sources/CloudupSnap/App/Info.plist.template"

cd "$ROOT"
swift build -c release --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$TEMPLATE" "$APP_DIR/Contents/Info.plist"

# Copy any bundled resources (sticker assets, etc.) the executable target produced
if [ -d "$BUILD_DIR/CloudupSnap_CloudupSnap.bundle" ]; then
  cp -R "$BUILD_DIR/CloudupSnap_CloudupSnap.bundle" "$APP_DIR/Contents/Resources/"
fi

echo "Built: $APP_DIR"
```

Make it executable:

```
chmod +x scripts/bundle.sh
```

- [ ] **Step 3: Add Makefile target**

Append to `Makefile`:

```makefile
app:
	./scripts/bundle.sh

run-app: app
	open build/CloudupSnap.app
```

- [ ] **Step 4: Verify `make app`**

```
make app
ls build/CloudupSnap.app/Contents/
ls build/CloudupSnap.app/Contents/MacOS/
```

Expected: `CloudupSnap.app/Contents/{Info.plist, MacOS/CloudupSnap, Resources/...}`.

- [ ] **Step 5: Verify launching it doesn't crash**

```
open build/CloudupSnap.app
```

The app should launch silently (LSUIElement = no Dock icon). Confirm via:

```
pgrep CloudupSnap && echo "running" || echo "not running"
```

Kill it: `pkill CloudupSnap`.

- [ ] **Step 6: Commit**

```
git add Sources/CloudupSnap/App/Info.plist.template scripts/bundle.sh Makefile
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add Info.plist template and app-bundling script

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 1 — Wallet balance helpers (extends Plan 1)

### Task 3: Wallet.balanceETH and Wallet.balanceUSDC

**Files:**
- Create: `Sources/CloudupSnapCore/Wallet/Wallet+Balance.swift`
- Create: `Tests/CloudupSnapCoreTests/WalletBalanceTests.swift`

The `FundingPanel` needs to show both balances. The `EthereumRPC` helpers from Plan 1 cover ETH; USDC requires an `eth_call` to `balanceOf(address)`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

@Test func walletBalanceETH() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "t", account: "a")
    let rpc = MockEthereumRPC()
    rpc.canned["eth_getBalance"] = "0xde0b6b3a7640000"  // 1 ETH in wei
    let balance = try await wallet.balanceETH(rpc: rpc)
    #expect(balance == Decimal(string: "1.0"))
}

@Test func walletBalanceUSDC() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "t", account: "a")
    let rpc = MockEthereumRPC()
    // 1,234,567 raw units = 1.234567 USDC (6 decimals)
    rpc.canned["eth_call"] = "0x000000000000000000000000000000000000000000000000000000000012d687"
    let contract = EthereumAddress(bytes: Data(repeating: 0x01, count: 20))
    let balance = try await wallet.balanceUSDC(contract: contract, decimals: 6, rpc: rpc)
    #expect(balance == Decimal(string: "1.234567"))
}
```

- [ ] **Step 2: Implement**

`Sources/CloudupSnapCore/Wallet/Wallet+Balance.swift`:

```swift
import Foundation

public extension Wallet {
    /// Balance in ETH (1 ETH = 1e18 wei). Result is a `Decimal` for UI display.
    func balanceETH(rpc: EthereumRPC) async throws -> Decimal {
        let q: HexQuantity = try await rpc.call("eth_getBalance", params: [address.hexString(), "latest"])
        return weiToDecimal(q.uint64, decimals: 18)
    }

    /// Balance in tokens of `contract`. Uses ERC-20 `balanceOf(address)`.
    func balanceUSDC(contract: EthereumAddress, decimals: Int, rpc: EthereumRPC) async throws -> Decimal {
        // Selector for balanceOf(address): 0x70a08231
        var data = Data([0x70, 0xa0, 0x82, 0x31])
        data.append(Data(count: 12))   // left-pad address to 32 bytes
        data.append(address.bytes)
        let resultHex: String = try await rpc.call("eth_call", params: [[
            "to": contract.hexString(),
            "data": data.hexEncodedString(prefix: true),
        ], "latest"])
        var raw = resultHex
        if raw.hasPrefix("0x") { raw = String(raw.dropFirst(2)) }
        // Take the rightmost 16 hex chars (8 bytes) as a UInt64. ERC-20 balances within
        // human-actionable range fit easily.
        let suffix = String(raw.suffix(16))
        let units = UInt64(suffix, radix: 16) ?? 0
        return weiToDecimal(units, decimals: decimals)
    }

    private func weiToDecimal(_ wei: UInt64, decimals: Int) -> Decimal {
        var divisor = Decimal(1)
        for _ in 0..<decimals { divisor *= 10 }
        return Decimal(wei) / divisor
    }
}
```

- [ ] **Step 3: Run, expect pass**

```
swift test --filter WalletBalanceTests
```

- [ ] **Step 4: Commit**

```
git add Sources/CloudupSnapCore/Wallet/Wallet+Balance.swift Tests/CloudupSnapCoreTests/WalletBalanceTests.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add Wallet.balanceETH and Wallet.balanceUSDC for FundingPanel

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2 — Foundation services

### Task 4: ClipboardService

**Files:**
- Create: `Sources/CloudupSnap/Services/ClipboardService.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import Foundation

public struct ClipboardService {
    public init() {}
    public func copy(_ url: URL) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(url.absoluteString, forType: .string)
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Services/ClipboardService.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add ClipboardService wrapping NSPasteboard

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: NotificationService

**Files:**
- Create: `Sources/CloudupSnap/Services/NotificationService.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import UserNotifications

public actor NotificationService {
    public static let shared = NotificationService()

    public func ensureAuthorization() async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    public func toast(title: String, body: String) async {
        await ensureAuthorization()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(req)
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Services/NotificationService.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add NotificationService wrapping UserNotifications

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3 — Annotation model

### Task 6: AnnotationModel — element types and document

**Files:**
- Create: `Sources/CloudupSnap/Annotation/AnnotationModel.swift`
- Create: `Sources/CloudupSnap/Annotation/AnnotationDocument.swift`
- Create: `Tests/CloudupSnapTests/AnnotationModelTests.swift`

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
import CoreGraphics
@testable import CloudupSnap

@Test func annotationDocumentAddsAndRemovesElements() {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    let id = doc.add(.line(start: .zero, end: CGPoint(x: 50, y: 50), style: .defaultStroke))
    #expect(doc.elements.count == 1)
    doc.remove(id: id)
    #expect(doc.elements.isEmpty)
}

@Test func annotationDocumentHitTestsTopElementFirst() {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    let bottom = doc.add(.rect(frame: CGRect(x: 0, y: 0, width: 100, height: 100), style: .defaultStroke))
    let top = doc.add(.rect(frame: CGRect(x: 10, y: 10, width: 30, height: 30), style: .defaultStroke))
    #expect(doc.hitTest(CGPoint(x: 20, y: 20)) == top)
    #expect(doc.hitTest(CGPoint(x: 80, y: 80)) == bottom)
}
```

- [ ] **Step 2: Implement AnnotationModel**

`Sources/CloudupSnap/Annotation/AnnotationModel.swift`:

```swift
import Foundation
import CoreGraphics

public struct ElementStyle: Equatable, Sendable {
    public var strokeColor: CGColor
    public var strokeWidth: CGFloat
    public var fillColor: CGColor?
    public var fontSize: CGFloat
    public var blurRadius: CGFloat

    public static let defaultStroke = ElementStyle(
        strokeColor: CGColor(red: 1, green: 0, blue: 0, alpha: 1),
        strokeWidth: 3,
        fillColor: nil,
        fontSize: 16,
        blurRadius: 12
    )
}

public enum ElementPayload: Equatable, Sendable {
    case line(start: CGPoint, end: CGPoint)
    case rect(frame: CGRect)
    case ellipse(frame: CGRect)
    case text(frame: CGRect, content: String)
    case pen(frame: CGRect, points: [CGPoint])
    case blur(frame: CGRect)
    case sticker(frame: CGRect, id: String)
}

public struct Element: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var payload: ElementPayload
    public var style: ElementStyle

    public init(payload: ElementPayload, style: ElementStyle = .defaultStroke) {
        self.id = UUID()
        self.payload = payload
        self.style = style
    }

    public var frame: CGRect {
        switch payload {
        case .line(let s, let e):
            return CGRect(x: min(s.x, e.x), y: min(s.y, e.y),
                          width: abs(e.x - s.x), height: abs(e.y - s.y)).insetBy(dx: -8, dy: -8)
        case .rect(let f), .ellipse(let f), .text(let f, _), .pen(let f, _), .blur(let f), .sticker(let f, _):
            return f
        }
    }

    public func hitTest(_ p: CGPoint) -> Bool { frame.contains(p) }
}

public extension Element {
    /// Sugar constructors used by the editor.
    static func line(start: CGPoint, end: CGPoint, style: ElementStyle) -> Element {
        Element(payload: .line(start: start, end: end), style: style)
    }
    static func rect(frame: CGRect, style: ElementStyle) -> Element {
        Element(payload: .rect(frame: frame), style: style)
    }
    static func ellipse(frame: CGRect, style: ElementStyle) -> Element {
        Element(payload: .ellipse(frame: frame), style: style)
    }
    static func text(frame: CGRect, content: String, style: ElementStyle) -> Element {
        Element(payload: .text(frame: frame, content: content), style: style)
    }
    static func pen(frame: CGRect, points: [CGPoint], style: ElementStyle) -> Element {
        Element(payload: .pen(frame: frame, points: points), style: style)
    }
    static func blur(frame: CGRect, style: ElementStyle = .defaultStroke) -> Element {
        Element(payload: .blur(frame: frame), style: style)
    }
    static func sticker(frame: CGRect, id: String) -> Element {
        Element(payload: .sticker(frame: frame, id: id), style: .defaultStroke)
    }
}
```

- [ ] **Step 3: Implement AnnotationDocument**

`Sources/CloudupSnap/Annotation/AnnotationDocument.swift`:

```swift
import Foundation
import CoreGraphics

public struct AnnotationDocument: Sendable {
    public let background: CGImage?
    public let size: CGSize
    public private(set) var elements: [Element] = []

    public init(background: CGImage?, size: CGSize) {
        self.background = background
        self.size = size
    }

    @discardableResult
    public mutating func add(_ element: Element) -> UUID {
        elements.append(element)
        return element.id
    }

    @discardableResult
    public mutating func add(_ payload: ElementPayload, style: ElementStyle = .defaultStroke) -> UUID {
        add(Element(payload: payload, style: style))
    }

    public mutating func remove(id: UUID) {
        elements.removeAll { $0.id == id }
    }

    public mutating func update(_ element: Element) {
        if let i = elements.firstIndex(where: { $0.id == element.id }) {
            elements[i] = element
        }
    }

    /// Returns the topmost element whose frame contains `point`, or nil.
    public func hitTest(_ point: CGPoint) -> UUID? {
        for el in elements.reversed() where el.hitTest(point) {
            return el.id
        }
        return nil
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter AnnotationModelTests
```

- [ ] **Step 5: Commit**

```
git add Sources/CloudupSnap/Annotation Tests/CloudupSnapTests/AnnotationModelTests.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add AnnotationModel and AnnotationDocument with hit-testing

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: UndoStack — command pattern over AnnotationDocument

**Files:**
- Create: `Sources/CloudupSnap/Annotation/UndoStack.swift`
- Create: `Tests/CloudupSnapTests/UndoStackTests.swift`

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
import CoreGraphics
@testable import CloudupSnap

@Test func undoStackRoundTripsAdd() {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    var stack = UndoStack()
    let element = Element.rect(frame: CGRect(x: 0, y: 0, width: 10, height: 10), style: .defaultStroke)
    stack.perform(.add(element), on: &doc)
    #expect(doc.elements.count == 1)
    stack.undo(on: &doc)
    #expect(doc.elements.isEmpty)
    stack.redo(on: &doc)
    #expect(doc.elements.count == 1)
}

@Test func undoStackCapsAt50() {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    var stack = UndoStack(capacity: 50)
    for i in 0..<60 {
        let e = Element.rect(frame: CGRect(x: CGFloat(i), y: 0, width: 10, height: 10), style: .defaultStroke)
        stack.perform(.add(e), on: &doc)
    }
    #expect(stack.undoDepth == 50)
}
```

- [ ] **Step 2: Implement**

`Sources/CloudupSnap/Annotation/UndoStack.swift`:

```swift
import Foundation

public enum AnnotationCommand: Sendable {
    case add(Element)
    case remove(Element)
    case update(old: Element, new: Element)
}

public struct UndoStack {
    public let capacity: Int
    private var undoStack: [AnnotationCommand] = []
    private var redoStack: [AnnotationCommand] = []

    public init(capacity: Int = 50) { self.capacity = capacity }

    public var undoDepth: Int { undoStack.count }
    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    public mutating func perform(_ command: AnnotationCommand, on doc: inout AnnotationDocument) {
        apply(command, on: &doc)
        undoStack.append(command)
        if undoStack.count > capacity { undoStack.removeFirst(undoStack.count - capacity) }
        redoStack.removeAll()
    }

    public mutating func undo(on doc: inout AnnotationDocument) {
        guard let cmd = undoStack.popLast() else { return }
        apply(invert(cmd), on: &doc)
        redoStack.append(cmd)
    }

    public mutating func redo(on doc: inout AnnotationDocument) {
        guard let cmd = redoStack.popLast() else { return }
        apply(cmd, on: &doc)
        undoStack.append(cmd)
    }

    private func apply(_ command: AnnotationCommand, on doc: inout AnnotationDocument) {
        switch command {
        case .add(let e): doc.add(e)
        case .remove(let e): doc.remove(id: e.id)
        case .update(_, let new): doc.update(new)
        }
    }

    private func invert(_ command: AnnotationCommand) -> AnnotationCommand {
        switch command {
        case .add(let e): return .remove(e)
        case .remove(let e): return .add(e)
        case .update(let old, let new): return .update(old: new, new: old)
        }
    }
}
```

- [ ] **Step 3: Run, expect pass**

```
swift test --filter UndoStackTests
```

- [ ] **Step 4: Commit**

```
git add Sources/CloudupSnap/Annotation/UndoStack.swift Tests/CloudupSnapTests/UndoStackTests.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add UndoStack with command pattern and 50-entry cap

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4 — Renderer

### Task 8: Renderer — flatten AnnotationDocument to PNG

**Files:**
- Create: `Sources/CloudupSnap/Render/Renderer.swift`
- Create: `Tests/CloudupSnapTests/RendererTests.swift`

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
import CoreGraphics
import SnapshotTesting
@testable import CloudupSnap

@Test func rendererProducesNonZeroPNG() throws {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 100, height: 100))
    doc.add(.rect(frame: CGRect(x: 10, y: 10, width: 80, height: 80), style: .defaultStroke))
    let png = try Renderer.flatten(doc)
    #expect(png.count > 100)
    #expect(png.prefix(8) == Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
}

@Test func rendererSnapshotsBasicShapes() throws {
    var doc = AnnotationDocument(background: nil, size: CGSize(width: 200, height: 200))
    doc.add(.rect(frame: CGRect(x: 20, y: 20, width: 60, height: 60), style: .defaultStroke))
    doc.add(.ellipse(frame: CGRect(x: 100, y: 20, width: 60, height: 60), style: .defaultStroke))
    doc.add(.line(start: CGPoint(x: 20, y: 120), end: CGPoint(x: 180, y: 180), style: .defaultStroke))
    let png = try Renderer.flatten(doc)
    assertSnapshot(of: png, as: .data, named: "basic-shapes")
}
```

- [ ] **Step 2: Implement**

`Sources/CloudupSnap/Render/Renderer.swift`:

```swift
import Foundation
import CoreGraphics
import AppKit

public enum RendererError: Error {
    case contextCreationFailed
    case pngEncodeFailed
}

public enum Renderer {
    public static func flatten(_ doc: AnnotationDocument) throws -> Data {
        let width = Int(doc.size.width)
        let height = Int(doc.size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RendererError.contextCreationFailed }

        // Flip so y-down matches AppKit drawing semantics
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)

        // White background fallback (transparent if you'd prefer)
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: doc.size))

        if let bg = doc.background {
            ctx.draw(bg, in: CGRect(origin: .zero, size: doc.size))
        }

        for element in doc.elements {
            draw(element, in: ctx, docSize: doc.size, background: doc.background)
        }

        guard let cg = ctx.makeImage() else { throw RendererError.pngEncodeFailed }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw RendererError.pngEncodeFailed
        }
        return png
    }

    private static func draw(_ element: Element, in ctx: CGContext, docSize: CGSize, background: CGImage?) {
        ctx.saveGState()
        ctx.setStrokeColor(element.style.strokeColor)
        ctx.setLineWidth(element.style.strokeWidth)
        if let fill = element.style.fillColor { ctx.setFillColor(fill) }
        switch element.payload {
        case .line(let s, let e):
            ctx.move(to: s); ctx.addLine(to: e); ctx.strokePath()
        case .rect(let f):
            if element.style.fillColor != nil { ctx.fill(f) }
            ctx.stroke(f)
        case .ellipse(let f):
            if element.style.fillColor != nil { ctx.fillEllipse(in: f) }
            ctx.strokeEllipse(in: f)
        case .text(let f, let content):
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: element.style.fontSize),
                .foregroundColor: NSColor(cgColor: element.style.strokeColor) ?? NSColor.red,
            ]
            let attr = NSAttributedString(string: content, attributes: attrs)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            attr.draw(in: f)
            NSGraphicsContext.restoreGraphicsState()
        case .pen(_, let points):
            guard let first = points.first else { break }
            ctx.move(to: first)
            for pt in points.dropFirst() { ctx.addLine(to: pt) }
            ctx.strokePath()
        case .blur(let f):
            if let bg = background {
                let bgRect = CGRect(origin: .zero, size: docSize)
                // Crop the background to f, apply CIFilter Gaussian blur, draw back
                let ci = CIImage(cgImage: bg)
                let blurred = ci.clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: element.style.blurRadius])
                    .cropped(to: CGRect(origin: .zero, size: docSize))
                let ciCtx = CIContext()
                if let cropped = ciCtx.createCGImage(blurred, from: f.intersection(bgRect)) {
                    ctx.draw(cropped, in: f.intersection(bgRect))
                }
            } else {
                ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
                ctx.fill(f)
            }
        case .sticker(let f, let id):
            if let image = Stickers.image(for: id) {
                ctx.draw(image, in: f)
            }
        }
        ctx.restoreGState()
    }
}
```

(`Stickers.image(for:)` is defined in Task 9.)

- [ ] **Step 3: Run, expect pass**

```
swift test --filter RendererTests
```

The first snapshot test will FAIL with a "no recorded snapshot" message and write a baseline image. Run the test once more — it should pass against its own baseline.

- [ ] **Step 4: Commit**

```
git add Sources/CloudupSnap/Render Tests/CloudupSnapTests/RendererTests.swift Tests/CloudupSnapTests/Fixtures
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add Renderer with snapshot tests for basic shapes

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Stickers — built-in sticker pack registry

**Files:**
- Create: `Sources/CloudupSnap/Annotation/Stickers.swift`

The sticker pack is rendered on-demand from Unicode emoji + SF Symbols, so no PNG assets need to be shipped.

- [ ] **Step 1: Implement**

```swift
import Foundation
import AppKit
import CoreGraphics

public enum Stickers {
    /// Identifiers exposed to the editor. Three groups:
    /// - emoji-N: an emoji rendered at request size
    /// - arrow-N: SF Symbol arrow in 8 directions
    /// - pin-N:   numbered pin 1–9 (SF Symbol "N.circle.fill")
    public static let allIDs: [String] = (1...40).map { "emoji-\($0)" }
        + (0...7).map { "arrow-\($0)" }
        + (1...9).map { "pin-\($0)" }

    public static func image(for id: String) -> CGImage? {
        if id.hasPrefix("emoji-") {
            let n = Int(id.dropFirst("emoji-".count)) ?? 1
            return renderText(emojiChar(n), size: 64)
        }
        if id.hasPrefix("arrow-") {
            let n = Int(id.dropFirst("arrow-".count)) ?? 0
            let names = ["arrow.up","arrow.up.right","arrow.right","arrow.down.right",
                         "arrow.down","arrow.down.left","arrow.left","arrow.up.left"]
            return renderSymbol(names[n % 8], size: 64)
        }
        if id.hasPrefix("pin-") {
            let n = Int(id.dropFirst("pin-".count)) ?? 1
            return renderSymbol("\(n).circle.fill", size: 64)
        }
        return nil
    }

    private static func emojiChar(_ n: Int) -> String {
        let pool = ["😀","😂","🤔","🙃","😎","🤩","😇","🥳","🤯","😅",
                    "🔥","💥","✨","🎉","💯","👀","👉","👈","✅","❌",
                    "❤️","💔","⭐️","⚠️","🚨","💡","🔒","🔑","📌","📎",
                    "🎯","🏆","🎁","🎵","☕️","🍕","🐶","🐱","🐢","🦄"]
        return pool[(n - 1) % pool.count]
    }

    private static func renderText(_ text: String, size: CGFloat) -> CGImage? {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size * 0.85)]
        (text as NSString).draw(at: NSPoint(x: size * 0.07, y: size * 0.05), withAttributes: attrs)
        image.unlockFocus()
        var rect = NSRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    private static func renderSymbol(_ name: String, size: CGFloat) -> CGImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.85, weight: .bold)
            .applying(.init(paletteColors: [.systemRed]))
        let resized = symbol.withSymbolConfiguration(config) ?? symbol
        var rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        return resized.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Annotation/Stickers.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add Stickers registry with emoji + SF Symbol arrows and pins

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 5 — Screen capture

### Task 10: CaptureService — ScreenCaptureKit wrapper for full-screen and window

**Files:**
- Create: `Sources/CloudupSnap/Capture/CaptureService.swift`

ScreenCaptureKit's `SCScreenshotManager.captureImage(contentFilter:configuration:)` returns a `CGImage` for a one-shot still. We support three modes: full-screen, single window, and region (region uses full-screen + cropping in Task 11).

- [ ] **Step 1: Implement**

```swift
import Foundation
import ScreenCaptureKit
import CoreGraphics

public enum CaptureMode: Sendable {
    case region
    case window
    case fullScreen
}

public enum CaptureError: Error {
    case permissionDenied
    case noDisplays
    case captureFailed
    case cancelled
}

public actor CaptureService {
    public init() {}

    public func captureFullScreen() async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else { throw CaptureError.noDisplays }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * NSScreen.main!.backingScaleFactor)
        config.height = Int(CGFloat(display.height) * NSScreen.main!.backingScaleFactor)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    public func captureWindow(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * NSScreen.main!.backingScaleFactor)
        config.height = Int(window.frame.height * NSScreen.main!.backingScaleFactor)
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    public func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.current
    }
}

extension CaptureService {
    /// Convenience: crop a captured CGImage to the user-selected region in points.
    /// Caller is responsible for accounting for backing scale.
    public func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        image.cropping(to: rect)
    }
}

import AppKit  // for NSScreen
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

If `import ScreenCaptureKit` fails, the target needs macOS 14+ (already declared). Should work as-is.

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Capture/CaptureService.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add CaptureService wrapping ScreenCaptureKit for full-screen and window capture

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: RegionSelectionOverlay — borderless rubber-band selection

**Files:**
- Create: `Sources/CloudupSnap/Capture/RegionSelectionOverlay.swift`

A borderless transparent `NSWindow` covering all screens, hosting a `MouseTrackingView` that:
- On mouse-down, records the start point.
- On mouse-drag, draws a darkened overlay + transparent rect for the selection.
- On mouse-up, calls a completion with the selection rect (in screen coordinates) or `nil` on Esc.

The capture flow is: show overlay → wait for selection → take full-screen capture → crop to selection.

- [ ] **Step 1: Implement**

```swift
import AppKit
import Foundation

@MainActor
public final class RegionSelectionOverlay {
    private var window: NSWindow?
    private var completion: ((CGRect?) -> Void)?

    public init() {}

    public func present(completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .screenSaver
        win.ignoresMouseEvents = false
        win.hasShadow = false
        let view = SelectionView(frame: screen.frame) { [weak self] rect in
            self?.finish(rect)
        }
        win.contentView = view
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func finish(_ rect: CGRect?) {
        window?.orderOut(nil)
        window = nil
        let cb = completion
        completion = nil
        cb?(rect)
    }
}

private final class SelectionView: NSView {
    private var startPoint: NSPoint?
    private var currentRect: NSRect = .zero
    private let onComplete: (CGRect?) -> Void

    init(frame: NSRect, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onComplete(nil)
        }
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let s = startPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        currentRect = NSRect(x: min(s.x, p.x), y: min(s.y, p.y),
                             width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard currentRect.width > 4, currentRect.height > 4, let screen = window?.screen else {
            onComplete(nil); return
        }
        // Convert local rect to global screen rect
        let global = NSRect(
            x: screen.frame.origin.x + currentRect.origin.x,
            y: screen.frame.origin.y + currentRect.origin.y,
            width: currentRect.width, height: currentRect.height
        )
        onComplete(global)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything
        NSColor(white: 0, alpha: 0.35).setFill()
        bounds.fill()
        // Clear the selected rect
        if currentRect != .zero {
            NSColor.clear.setFill()
            NSBezierPath(rect: currentRect).fill()
            NSColor.systemBlue.setStroke()
            let path = NSBezierPath(rect: currentRect)
            path.lineWidth = 2
            path.stroke()
        }
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Capture/RegionSelectionOverlay.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add RegionSelectionOverlay for borderless rubber-band selection

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 6 — Annotation editor UI

### Task 12: ToolsPalette — tool picker SwiftUI view

**Files:**
- Create: `Sources/CloudupSnap/Annotation/ToolsPalette.swift`

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import AppKit

public enum Tool: String, CaseIterable, Identifiable {
    case select, arrow, line, rect, ellipse, text, pen, blur, sticker
    public var id: String { rawValue }
    public var systemImage: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rect: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .pen: return "pencil.tip"
        case .blur: return "drop.fill"
        case .sticker: return "smiley"
        }
    }
}

public struct ToolsPalette: View {
    @Binding public var selectedTool: Tool
    @Binding public var strokeColor: Color
    @Binding public var strokeWidth: CGFloat
    public var onUpload: () -> Void
    public var onCancel: () -> Void
    public var onUndo: () -> Void
    public var onRedo: () -> Void

    public init(
        selectedTool: Binding<Tool>,
        strokeColor: Binding<Color>,
        strokeWidth: Binding<CGFloat>,
        onUpload: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void
    ) {
        self._selectedTool = selectedTool
        self._strokeColor = strokeColor
        self._strokeWidth = strokeWidth
        self.onUpload = onUpload
        self.onCancel = onCancel
        self.onUndo = onUndo
        self.onRedo = onRedo
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(Tool.allCases) { tool in
                Button { selectedTool = tool } label: {
                    Image(systemName: tool.systemImage)
                        .frame(width: 28, height: 28)
                        .background(selectedTool == tool ? Color.accentColor.opacity(0.2) : .clear)
                        .cornerRadius(4)
                }.buttonStyle(.plain)
            }
            Divider().frame(height: 24)
            ColorPicker("", selection: $strokeColor).labelsHidden().frame(width: 28)
            Stepper("", value: $strokeWidth, in: 1...12, step: 1).labelsHidden().frame(width: 28)
            Divider().frame(height: 24)
            Button(action: onUndo) { Image(systemName: "arrow.uturn.backward") }.keyboardShortcut("z")
            Button(action: onRedo) { Image(systemName: "arrow.uturn.forward") }.keyboardShortcut("z", modifiers: [.command, .shift])
            Spacer()
            Button("Cancel", action: onCancel).keyboardShortcut(.escape, modifiers: [])
            Button("Upload", action: onUpload).keyboardShortcut(.return).buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.thinMaterial)
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Annotation/ToolsPalette.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add ToolsPalette SwiftUI view for tool picker + style + undo/upload

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: AnnotationCanvas — SwiftUI Canvas with interactive elements

**Files:**
- Create: `Sources/CloudupSnap/Annotation/AnnotationCanvas.swift`

The canvas hosts the background image and live-draws elements as the user drags. It owns ephemeral "in-progress" element state and commits to the document on mouse-up.

- [ ] **Step 1: Implement**

```swift
import SwiftUI
import CoreGraphics
import AppKit

public struct AnnotationCanvas: View {
    @Binding public var document: AnnotationDocument
    public var tool: Tool
    public var strokeColor: Color
    public var strokeWidth: CGFloat
    public var onCommit: (Element) -> Void
    public var onUpdate: (Element) -> Void

    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var penPoints: [CGPoint] = []
    @State private var selectedID: UUID?

    public init(
        document: Binding<AnnotationDocument>,
        tool: Tool,
        strokeColor: Color,
        strokeWidth: CGFloat,
        onCommit: @escaping (Element) -> Void,
        onUpdate: @escaping (Element) -> Void
    ) {
        self._document = document
        self.tool = tool
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.onCommit = onCommit
        self.onUpdate = onUpdate
    }

    public var body: some View {
        Canvas { context, size in
            if let bg = document.background {
                context.draw(Image(decorative: bg, scale: 1), in: CGRect(origin: .zero, size: size))
            }
            for element in document.elements {
                drawElement(element, in: context)
            }
            if let s = dragStart, let c = dragCurrent {
                drawPreview(start: s, current: c, in: context)
            }
        }
        .frame(width: document.size.width, height: document.size.height)
        .background(Color.white)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStart == nil { dragStart = value.startLocation }
                    dragCurrent = value.location
                    if tool == .pen { penPoints.append(value.location) }
                }
                .onEnded { value in
                    if let s = dragStart {
                        commitElement(from: s, to: value.location)
                    }
                    dragStart = nil; dragCurrent = nil; penPoints.removeAll()
                }
        )
    }

    private func currentStyle() -> ElementStyle {
        var s = ElementStyle.defaultStroke
        s.strokeColor = NSColor(strokeColor).cgColor
        s.strokeWidth = strokeWidth
        return s
    }

    private func commitElement(from start: CGPoint, to end: CGPoint) {
        let frame = CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
        let style = currentStyle()
        let element: Element?
        switch tool {
        case .select: element = nil
        case .arrow, .line: element = Element.line(start: start, end: end, style: style)
        case .rect: element = Element.rect(frame: frame, style: style)
        case .ellipse: element = Element.ellipse(frame: frame, style: style)
        case .text:
            element = Element.text(frame: frame, content: "Type here", style: style)
        case .pen:
            element = Element.pen(frame: frame, points: penPoints, style: style)
        case .blur:
            element = Element.blur(frame: frame)
        case .sticker:
            // sticker placement is via a separate popover, not the canvas drag
            element = nil
        }
        if let e = element { onCommit(e) }
    }

    private func drawElement(_ element: Element, in context: GraphicsContext) {
        switch element.payload {
        case .line(let s, let e):
            var path = Path(); path.move(to: s); path.addLine(to: e)
            context.stroke(path, with: .color(Color(cgColor: element.style.strokeColor)),
                           lineWidth: element.style.strokeWidth)
        case .rect(let f):
            let path = Path(roundedRect: f, cornerRadius: 0)
            context.stroke(path, with: .color(Color(cgColor: element.style.strokeColor)),
                           lineWidth: element.style.strokeWidth)
        case .ellipse(let f):
            context.stroke(Path(ellipseIn: f), with: .color(Color(cgColor: element.style.strokeColor)),
                           lineWidth: element.style.strokeWidth)
        case .text(let f, let content):
            context.draw(Text(content).font(.system(size: element.style.fontSize)).foregroundColor(Color(cgColor: element.style.strokeColor)),
                         in: f)
        case .pen(_, let points):
            var path = Path()
            if let first = points.first { path.move(to: first); for p in points.dropFirst() { path.addLine(to: p) } }
            context.stroke(path, with: .color(Color(cgColor: element.style.strokeColor)),
                           lineWidth: element.style.strokeWidth)
        case .blur(let f):
            context.fill(Path(f), with: .color(.gray.opacity(0.3)))
            context.stroke(Path(f), with: .color(.gray), lineWidth: 1)
        case .sticker(let f, let id):
            if let img = Stickers.image(for: id) {
                context.draw(Image(decorative: img, scale: 1), in: f)
            }
        }
    }

    private func drawPreview(start: CGPoint, current: CGPoint, in context: GraphicsContext) {
        let style = currentStyle()
        let color = Color(cgColor: style.strokeColor)
        switch tool {
        case .arrow, .line:
            var p = Path(); p.move(to: start); p.addLine(to: current)
            context.stroke(p, with: .color(color), lineWidth: style.strokeWidth)
        case .rect:
            context.stroke(Path(CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y))),
                with: .color(color), lineWidth: style.strokeWidth)
        case .ellipse:
            context.stroke(Path(ellipseIn: CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y))),
                with: .color(color), lineWidth: style.strokeWidth)
        case .pen:
            var p = Path()
            if let first = penPoints.first { p.move(to: first); for pt in penPoints.dropFirst() { p.addLine(to: pt) } }
            context.stroke(p, with: .color(color), lineWidth: style.strokeWidth)
        default:
            break
        }
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Annotation/AnnotationCanvas.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add AnnotationCanvas with drag-to-draw for all element types

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 14: AnnotationEditor — borderless NSWindow hosting the SwiftUI editor

**Files:**
- Create: `Sources/CloudupSnap/Annotation/AnnotationEditor.swift`

A controller that owns an NSWindow, an `AnnotationDocument`, an `UndoStack`, and the SwiftUI view tree. Exposes a completion handler called with either the final `AnnotationDocument` or nil on cancel.

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI
import CoreGraphics

@MainActor
public final class AnnotationEditor {
    private var window: NSWindow?
    private var completion: ((AnnotationDocument?) -> Void)?

    public init() {}

    public func present(background: CGImage, completion: @escaping (AnnotationDocument?) -> Void) {
        self.completion = completion
        let size = CGSize(width: background.width, height: background.height)
        let doc = AnnotationDocument(background: background, size: size)
        let host = AnnotationEditorRoot(initialDoc: doc, onUpload: { [weak self] d in self?.finish(d) },
                                       onCancel: { [weak self] in self?.finish(nil) })
        let view = NSHostingView(rootView: host)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        win.title = "Annotate"
        win.contentView = view
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }

    private func finish(_ doc: AnnotationDocument?) {
        window?.orderOut(nil)
        window = nil
        let cb = completion
        completion = nil
        cb?(doc)
    }
}

@MainActor
struct AnnotationEditorRoot: View {
    @State var document: AnnotationDocument
    @State var undoStack = UndoStack()
    @State var tool: Tool = .arrow
    @State var strokeColor: Color = .red
    @State var strokeWidth: CGFloat = 3
    let onUpload: (AnnotationDocument) -> Void
    let onCancel: () -> Void

    init(initialDoc: AnnotationDocument, onUpload: @escaping (AnnotationDocument) -> Void, onCancel: @escaping () -> Void) {
        self._document = State(initialValue: initialDoc)
        self.onUpload = onUpload
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            ToolsPalette(
                selectedTool: $tool,
                strokeColor: $strokeColor,
                strokeWidth: $strokeWidth,
                onUpload: { onUpload(document) },
                onCancel: onCancel,
                onUndo: { undoStack.undo(on: &document) },
                onRedo: { undoStack.redo(on: &document) }
            )
            AnnotationCanvas(
                document: $document,
                tool: tool,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                onCommit: { e in undoStack.perform(.add(e), on: &document) },
                onUpdate: { e in undoStack.perform(.update(old: e, new: e), on: &document) }
            )
        }
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Annotation/AnnotationEditor.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add AnnotationEditor NSWindow controller hosting the SwiftUI tree

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 7 — Glue UI

### Task 15: WalletProvider — shared Keychain wallet for the app

**Files:**
- Create: `Sources/CloudupSnap/Wallet/WalletProvider.swift`

- [ ] **Step 1: Implement**

```swift
import Foundation
import CloudupSnapCore

public enum WalletProvider {
    public static let service = "com.bongnam.cloudupsnap"
    public static let account = "default"

    public static func wallet() throws -> Wallet {
        try Wallet.loadOrCreate(keychain: MacOSKeychainStore(), service: service, account: account)
    }
}
```

- [ ] **Step 2: Commit**

```
git add Sources/CloudupSnap/Wallet/WalletProvider.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add WalletProvider sharing the Keychain wallet with the CLI

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 16: HotkeyManager — ⌘⇧2 global hotkey via Carbon

**Files:**
- Create: `Sources/CloudupSnap/Hotkey/HotkeyManager.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import Carbon.HIToolbox

@MainActor
public final class HotkeyManager {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (() -> Void)?

    public init() {}

    public func register(onPress: @escaping () -> Void) {
        self.onPress = onPress
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData = userData else { return noErr }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { mgr.onPress?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        var hotKeyID = EventHotKeyID(signature: OSType(0x5343534F), id: 1)  // 'SCSO'
        // ⌘⇧2 → keyCode 19 (digit 2 on US layout), modifiers: cmdKey | shiftKey
        RegisterEventHotKey(UInt32(kVK_ANSI_2), UInt32(cmdKey | shiftKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
    }

    deinit {
        if let r = ref { UnregisterEventHotKey(r) }
        if let h = handler { RemoveEventHandler(h) }
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Hotkey/HotkeyManager.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add HotkeyManager registering ⌘⇧2 via Carbon

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 17: MenubarController — NSStatusItem + menu

**Files:**
- Create: `Sources/CloudupSnap/Menubar/MenubarController.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit

@MainActor
public final class MenubarController {
    private let statusItem: NSStatusItem
    public var onCaptureRegion: (() -> Void)?
    public var onCaptureWindow: (() -> Void)?
    public var onCaptureFullScreen: (() -> Void)?
    public var onOpenFundingPanel: (() -> Void)?
    public var onQuit: (() -> Void)?

    public init() {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "CloudupSnap")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let region = NSMenuItem(title: "Capture Region (⌘⇧2)", action: #selector(captureRegion), keyEquivalent: "")
        region.target = self
        let window = NSMenuItem(title: "Capture Window…", action: #selector(captureWindow), keyEquivalent: "")
        window.target = self
        let full = NSMenuItem(title: "Capture Full Screen", action: #selector(captureFullScreen), keyEquivalent: "")
        full.target = self
        let wallet = NSMenuItem(title: "Wallet…", action: #selector(openFunding), keyEquivalent: "")
        wallet.target = self
        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        for item in [region, window, full, .separator(), wallet, .separator(), quit] {
            menu.addItem(item)
        }
        statusItem.menu = menu
    }

    @objc private func captureRegion() { onCaptureRegion?() }
    @objc private func captureWindow() { onCaptureWindow?() }
    @objc private func captureFullScreen() { onCaptureFullScreen?() }
    @objc private func openFunding() { onOpenFundingPanel?() }
    @objc private func quit() { onQuit?(); NSApp.terminate(nil) }
}
```

- [ ] **Step 2: Commit**

```
git add Sources/CloudupSnap/Menubar/MenubarController.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add MenubarController with NSStatusItem and menu

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 18: FundingPanel — wallet address + QR + balances + retry

**Files:**
- Create: `Sources/CloudupSnap/Funding/FundingPanel.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI
import CoreImage.CIFilterBuiltins
import CloudupSnapCore

@MainActor
public final class FundingPanel {
    private var window: NSWindow?
    public init() {}

    public func present(address: String, balanceUSDC: Decimal, balanceETH: Decimal, onRetry: (() -> Void)? = nil) {
        let root = FundingPanelView(address: address, balanceUSDC: balanceUSDC, balanceETH: balanceETH, onRetry: onRetry)
        let view = NSHostingView(rootView: root)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Wallet"
        win.contentView = view
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct FundingPanelView: View {
    let address: String
    let balanceUSDC: Decimal
    let balanceETH: Decimal
    let onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Text("Fund your wallet on Base Sepolia").font(.headline)
            if let qr = qrImage(for: address) {
                Image(nsImage: qr).resizable().interpolation(.none).frame(width: 200, height: 200)
            }
            HStack(spacing: 4) {
                Text(address).font(.system(.body, design: .monospaced)).truncationMode(.middle).lineLimit(1)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(address, forType: .string)
                }.buttonStyle(.borderless)
            }
            HStack(spacing: 16) {
                VStack { Text("USDC").font(.caption); Text(String(format: "%@", balanceUSDC.description)).font(.system(.body, design: .monospaced)) }
                VStack { Text("ETH").font(.caption); Text(String(format: "%@", balanceETH.description)).font(.system(.body, design: .monospaced)) }
            }
            Text("Fund with Base Sepolia ETH (for gas) + USDC (for upload fees).")
                .font(.footnote).multilineTextAlignment(.center).foregroundColor(.secondary)
            if let onRetry = onRetry {
                Button("I've funded — retry upload", action: onRetry).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func qrImage(for text: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let ci = filter.outputImage else { return nil }
        let scaled = ci.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let rep = NSCIImageRep(ciImage: scaled)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Funding/FundingPanel.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add FundingPanel with wallet address, QR, balances, retry

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 19: OnboardingCoordinator — first-run permission prompts + wallet funding

**Files:**
- Create: `Sources/CloudupSnap/Onboarding/OnboardingCoordinator.swift`

- [ ] **Step 1: Implement**

```swift
import AppKit
import SwiftUI
import ScreenCaptureKit

@MainActor
public final class OnboardingCoordinator {
    private var window: NSWindow?
    public init() {}

    public static var hasRun: Bool {
        get { UserDefaults.standard.bool(forKey: "onboarding.done") }
        set { UserDefaults.standard.set(newValue, forKey: "onboarding.done") }
    }

    public func presentIfNeeded(walletAddress: String) {
        guard !Self.hasRun else { return }
        let root = OnboardingView(walletAddress: walletAddress, onDone: { [weak self] in
            Self.hasRun = true
            self?.window?.close()
            self?.window = nil
        })
        let view = NSHostingView(rootView: root)
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
                           styleMask: [.titled, .closable], backing: .buffered, defer: false)
        win.title = "Welcome to CloudupSnap"
        win.contentView = view
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

struct OnboardingView: View {
    let walletAddress: String
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Welcome to CloudupSnap").font(.title)
            Text("CloudupSnap needs two permissions and a small amount of testnet funds to work.")

            Divider()

            Text("1. Screen Recording").font(.headline)
            HStack {
                Text("Required to capture screen regions.")
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            }

            Text("2. Accessibility").font(.headline)
            HStack {
                Text("Required for the ⌘⇧2 global hotkey.")
                Button("Open System Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }

            Divider()

            Text("3. Fund your wallet").font(.headline)
            Text("Each upload costs ~$0.05 in testnet USDC on Base Sepolia.")
            Text(walletAddress).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            HStack {
                Link("Coinbase CDP Faucet", destination: URL(string: "https://portal.cdp.coinbase.com/products/faucet")!)
                Link("Circle USDC Faucet", destination: URL(string: "https://faucet.circle.com/")!)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Get started", action: onDone).buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
```

- [ ] **Step 2: Commit**

```
git add Sources/CloudupSnap/Onboarding/OnboardingCoordinator.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add OnboardingCoordinator first-run window

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 8 — Wiring it together

### Task 20: CaptureCoordinator — state machine

**Files:**
- Create: `Sources/CloudupSnap/Coordination/CaptureCoordinator.swift`

Owns: CaptureService, RegionSelectionOverlay, AnnotationEditor, Uploader, ClipboardService, NotificationService, FundingPanel.

State transitions per spec:
- Idle → Selecting on `startCapture(mode:)`
- Selecting → Editing on user selection (CGImage)
- Selecting → Idle on Esc / capture failure
- Editing → Uploading on user upload
- Editing → Idle on user cancel
- Uploading → Done → Idle on success (URL copied, toast)
- Uploading → Editing on failure (with FundingPanel on `insufficientFunds`/`settlementReverted`)

- [ ] **Step 1: Implement**

```swift
import AppKit
import Foundation
import CloudupSnapCore
import ScreenCaptureKit
import CoreGraphics

@MainActor
public final class CaptureCoordinator {
    private let capture = CaptureService()
    private let regionOverlay = RegionSelectionOverlay()
    private let editor = AnnotationEditor()
    private let clipboard = ClipboardService()
    private let funding = FundingPanel()
    private var inFlight = false

    public init() {}

    public func startCapture(mode: CaptureMode) {
        guard !inFlight else { return }
        inFlight = true
        switch mode {
        case .region:
            regionOverlay.present { [weak self] selectedRect in
                guard let self else { return }
                guard let rect = selectedRect else { self.inFlight = false; return }
                Task { await self.captureRegionAndEdit(rect: rect) }
            }
        case .fullScreen:
            Task { await self.captureFullAndEdit() }
        case .window:
            Task { await self.captureWindowAndEdit() }
        }
    }

    private func captureRegionAndEdit(rect: CGRect) async {
        do {
            let full = try await capture.captureFullScreen()
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let scaled = CGRect(x: rect.origin.x * scale, y: rect.origin.y * scale,
                                width: rect.width * scale, height: rect.height * scale)
            guard let cropped = full.cropping(to: scaled) else { inFlight = false; return }
            openEditor(with: cropped)
        } catch {
            await NotificationService.shared.toast(title: "Capture failed", body: "\(error)")
            inFlight = false
        }
    }

    private func captureFullAndEdit() async {
        do {
            let full = try await capture.captureFullScreen()
            openEditor(with: full)
        } catch {
            await NotificationService.shared.toast(title: "Capture failed", body: "\(error)")
            inFlight = false
        }
    }

    private func captureWindowAndEdit() async {
        do {
            let content = try await capture.shareableContent()
            guard let win = content.windows.first(where: { $0.isOnScreen && $0.owningApplication?.applicationName != "CloudupSnap" }) else {
                inFlight = false; return
            }
            let img = try await capture.captureWindow(win)
            openEditor(with: img)
        } catch {
            await NotificationService.shared.toast(title: "Capture failed", body: "\(error)")
            inFlight = false
        }
    }

    private func openEditor(with background: CGImage) {
        editor.present(background: background) { [weak self] doc in
            guard let self else { return }
            guard let doc = doc else { self.inFlight = false; return }
            Task { await self.flattenAndUpload(doc: doc) }
        }
    }

    private func flattenAndUpload(doc: AnnotationDocument) async {
        do {
            let png = try Renderer.flatten(doc)
            let wallet = try WalletProvider.wallet()
            let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
            let payment = PaymentClient(
                wallet: wallet, rpc: rpc,
                capUSD: Decimal(string: "0.50")!,
                receiptPoll: ReceiptPollPolicy(interval: 2.0, timeout: 120.0)
            )
            let mcp = MCPClient(transport: StreamableHTTPTransport(
                endpoint: URL(string: "https://api.stage-cloudup.com/mcp/public")!))
            let uploader = Uploader(mcp: mcp, payment: payment)
            let url = try await uploader.upload(data: png, filename: "screenshot.png", mime: "image/png")
            clipboard.copy(url)
            await NotificationService.shared.toast(title: "Copied", body: url.absoluteString)
        } catch let e as PaymentError {
            await handlePaymentError(e)
        } catch {
            await NotificationService.shared.toast(title: "Upload failed", body: "\(error)")
        }
        inFlight = false
    }

    private func handlePaymentError(_ e: PaymentError) async {
        switch e {
        case .settlementReverted, .settlementTimeout, .insufficientFunds:
            do {
                let wallet = try WalletProvider.wallet()
                let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
                let usdcContract = EthereumAddress(bytes: try Data(hexString: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"))
                async let usdc = wallet.balanceUSDC(contract: usdcContract, decimals: 6, rpc: rpc)
                async let eth = wallet.balanceETH(rpc: rpc)
                let (u, e2) = (try await usdc, try await eth)
                funding.present(address: wallet.address.hexString(), balanceUSDC: u, balanceETH: e2)
            } catch {
                await NotificationService.shared.toast(title: "Wallet error", body: "\(error)")
            }
        default:
            await NotificationService.shared.toast(title: "Upload failed", body: "\(e)")
        }
    }

    public func openFundingPanel() {
        Task {
            do {
                let wallet = try WalletProvider.wallet()
                let rpc = HTTPEthereumRPC(endpoint: URL(string: "https://sepolia.base.org")!)
                let usdcContract = EthereumAddress(bytes: try Data(hexString: "0x036CbD53842c5426634e7929541eC2318f3dCF7e"))
                async let usdc = wallet.balanceUSDC(contract: usdcContract, decimals: 6, rpc: rpc)
                async let eth = wallet.balanceETH(rpc: rpc)
                let (u, e) = (try await usdc, try await eth)
                funding.present(address: wallet.address.hexString(), balanceUSDC: u, balanceETH: e)
            } catch {}
        }
    }
}
```

- [ ] **Step 2: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnap/Coordination/CaptureCoordinator.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add CaptureCoordinator state machine wiring capture → editor → upload

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 9 — App entry point

### Task 21: CloudupSnapApp — @main + AppDelegate

**Files:**
- Modify (overwrite): `Sources/CloudupSnap/Placeholder.swift` (rename to `CloudupSnapApp.swift`)

- [ ] **Step 1: Delete placeholder**

```
git rm Sources/CloudupSnap/Placeholder.swift
```

- [ ] **Step 2: Create the real entry point**

`Sources/CloudupSnap/App/CloudupSnapApp.swift`:

```swift
import AppKit
import CloudupSnapCore

@main
final class CloudupSnapApp: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = CloudupSnapApp()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // ensures LSUIElement behavior at runtime too
        app.run()
    }

    let menubar = MenubarController()
    let hotkey = HotkeyManager()
    let onboarding = OnboardingCoordinator()
    let coordinator = CaptureCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menubar.onCaptureRegion = { [weak self] in self?.coordinator.startCapture(mode: .region) }
        menubar.onCaptureWindow = { [weak self] in self?.coordinator.startCapture(mode: .window) }
        menubar.onCaptureFullScreen = { [weak self] in self?.coordinator.startCapture(mode: .fullScreen) }
        menubar.onOpenFundingPanel = { [weak self] in self?.coordinator.openFundingPanel() }

        hotkey.register { [weak self] in self?.coordinator.startCapture(mode: .region) }

        if let wallet = try? WalletProvider.wallet() {
            onboarding.presentIfNeeded(walletAddress: wallet.address.hexString())
        }
    }
}
```

- [ ] **Step 3: Verify build**

```
swift build --product CloudupSnap
```

- [ ] **Step 4: Verify the app launches and shows a menubar icon**

```
make app
open build/CloudupSnap.app
```

You should see a scissors icon in the menubar. Click it to see the menu. The first launch should show the onboarding window.

- [ ] **Step 5: Commit**

```
git add Sources/CloudupSnap/App/CloudupSnapApp.swift
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Add CloudupSnapApp @main with menubar + hotkey + coordinator wiring

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase 10 — Manual end-to-end verification

### Task 22: Smoke test

**Files:** none

- [ ] **Step 1: Grant permissions**
  - System Settings → Privacy & Security → Screen Recording → enable CloudupSnap.
  - System Settings → Privacy & Security → Accessibility → enable CloudupSnap.
  - Quit and relaunch the app after granting (macOS requires this).

- [ ] **Step 2: Press ⌘⇧2**
  - A dimmed overlay should appear across the screen.
  - Click-drag to select a region.
  - The annotation editor opens with your selection as the background.

- [ ] **Step 3: Annotate**
  - Try every tool: arrow, line, rect, ellipse, text, pen, blur.
  - Press ⌘Z to undo. Press ⌘⇧Z to redo. Confirm both work.

- [ ] **Step 4: Upload**
  - Press the Upload button (or ⌘↩).
  - Within a few seconds, a notification appears: "Copied: https://stage-cloudup.com/s/…".
  - Open the URL in a browser; verify the screenshot is there.

- [ ] **Step 5: Funding panel**
  - From the menubar, click Wallet…
  - Verify the wallet address + QR + USDC + ETH balances display correctly.

- [ ] **Step 6: Update README**

Append to `README.md`:

```markdown
## Running the macOS app

    make app
    open build/CloudupSnap.app

Grant Screen Recording + Accessibility permissions in System Settings on first run.
Press ⌘⇧2 anywhere to capture, annotate, and upload.
```

```
git add README.md
git -c user.email=steve.dufresne@a8c.com -c user.name="Steve Dufresne" commit -m "$(cat <<'EOF'
Document macOS app build and run instructions

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Spec coverage check

This plan implements the following spec components from `docs/superpowers/specs/2026-05-12-cloudupsnap-design.md`:

- `MenubarController` — Task 17
- `HotkeyManager` — Task 16
- `OnboardingCoordinator` — Task 19
- `CaptureCoordinator` — Task 20
- `CaptureService` — Task 10
- `AnnotationEditor` — Task 14 (window) + Task 13 (canvas) + Task 12 (palette)
- `AnnotationModel` — Task 6
- `UndoStack` — Task 7
- `Renderer` — Task 8 + Task 9 (stickers)
- `ClipboardService` — Task 4
- `NotificationService` — Task 5
- `FundingPanel` — Task 18
- App scaffolding + Info.plist + bundling — Tasks 1, 2, 21
- Wallet balance helpers — Task 3
- Manual end-to-end verification — Task 22

## Risks called out in the spec, addressed here

- **Capture overlay across multi-monitor + Retina.** Task 11 uses `NSScreen` coordinates; Task 20 multiplies by `backingScaleFactor` when cropping. Manual test on multi-monitor in Task 22.
- **Renderer correctness.** Task 8 includes snapshot tests; the editor and renderer use the same `Element` model so divergence is unlikely.
- **Wallet sharing.** Task 15 + the existing Plan 1 `MacOSKeychainStore` ensure the app and CLI share the same key.

## What we punt

- Configurable hotkey, configurable max-spend cap → future Settings pane.
- Wallet recovery / export → future enhancement.
- Recordings → Plan 3.
- Signed / notarized / App Store distribution → out of scope.
