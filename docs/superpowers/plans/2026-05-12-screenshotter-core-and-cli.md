# Screenshotter Core + CLI Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Swift package that uploads files to Cloudup's MCP server, paying per-upload in USDC on Base Sepolia via MPP/x402. Ship a CLI binary (`screenshotter-cli`) that demonstrates an end-to-end paid upload and returns a share URL.

**Architecture:** Pure Swift library (`ScreenshotterCore`) with no UI dependencies, exposing a single high-level surface: `Uploader.upload(data:filename:mime:) async throws -> URL`. Under the hood: `Uploader` → `MCPClient` (JSON-RPC over Streamable HTTP) → `PaymentClient` (handles 402 challenges) → `Wallet` (Keychain-stored secp256k1 key, EIP-712 signing). The CLI target is a thin shell around `Uploader`.

**Tech Stack:**
- Swift 6, Swift Package Manager (no Xcode project required)
- `swift-testing` for unit tests (`@Test` macros), XCTest for one Keychain integration test (XCTest is friendlier for setUp/tearDown)
- Dependencies (SwiftPM):
  - `github.com/GigaBitcoin/secp256k1.swift` — ECDSA signing
  - `github.com/krzyzanowskim/CryptoSwift` — keccak256
- Apple frameworks: Foundation, Security (Keychain), CryptoKit
- Reference implementation for the MPP/x402 protocol: `github:tellyworth/mpp-remote`

**Spec:** `docs/superpowers/specs/2026-05-12-screenshotter-design.md`

**Note on testing framework:** the spec mentions "XCTest" generically; this plan uses `swift-testing` for the bulk of unit tests (cleaner ergonomics for Swift 6) and XCTest for the one Keychain integration test where setUp/tearDown matters.

---

## File Structure

```
/Users/bongnam/dev/screenshotter/
├── Package.swift
├── README.md
├── .gitignore
├── Sources/
│   ├── ScreenshotterCore/
│   │   ├── HexAndHash/
│   │   │   ├── HexCoding.swift           # Data ↔ hex String
│   │   │   └── Keccak.swift              # keccak256(_:Data) -> Data
│   │   ├── Wallet/
│   │   │   ├── Secp256k1Signer.swift     # libsecp256k1 wrapper, keygen + sign
│   │   │   ├── EthereumAddress.swift     # 20-byte address derived from pubkey
│   │   │   ├── EIP712.swift              # typed-data hashing
│   │   │   ├── KeychainStore.swift       # protocol + macOS implementation
│   │   │   └── Wallet.swift              # façade: address, signEIP712
│   │   ├── MCP/
│   │   │   ├── JSONRPC.swift             # Codable Request/Response/Error envelopes
│   │   │   ├── SSEReader.swift           # Server-Sent Events parser
│   │   │   ├── MCPTransport.swift        # protocol over an async HTTP body
│   │   │   ├── StreamableHTTPTransport.swift  # URLSession-backed transport
│   │   │   └── MCPClient.swift           # initialize + callTool surface
│   │   ├── Payment/
│   │   │   ├── PaymentQuote.swift        # parsed MPP 402 challenge payload
│   │   │   ├── PaymentError.swift        # typed errors (capExceeded, etc.)
│   │   │   └── PaymentClient.swift       # orchestrates handle → sign → retry
│   │   └── Uploader/
│   │       └── Uploader.swift            # public façade: upload(...) -> URL
│   └── screenshotter-cli/
│       └── main.swift                    # parses argv, calls Uploader, prints URL
├── Tests/
│   ├── ScreenshotterCoreTests/
│   │   ├── Fixtures/
│   │   │   ├── EIP712Vectors.swift       # static known-good test vectors
│   │   │   ├── MPPQuoteSamples.swift     # canned 402 payloads
│   │   │   └── MockMCPTransport.swift    # in-memory mock for unit tests
│   │   ├── HexAndHashTests.swift
│   │   ├── Secp256k1SignerTests.swift
│   │   ├── EthereumAddressTests.swift
│   │   ├── EIP712Tests.swift
│   │   ├── WalletTests.swift
│   │   ├── JSONRPCTests.swift
│   │   ├── SSEReaderTests.swift
│   │   ├── MCPClientTests.swift
│   │   ├── PaymentQuoteTests.swift
│   │   ├── PaymentClientTests.swift
│   │   ├── UploaderTests.swift
│   │   └── UploaderIntegrationTests.swift  # gated on SCREENSHOTTER_INTEGRATION=1
│   └── KeychainStoreTests/
│       └── KeychainStoreTests.swift      # XCTest target, gated on environment
├── docs/
│   └── superpowers/
│       ├── specs/2026-05-12-screenshotter-design.md
│       ├── plans/2026-05-12-screenshotter-core-and-cli.md
│       └── protocol/mpp-x402.md          # written in Task 4 from the reference impl
```

---

## Phase 0 — Scaffolding

### Task 1: Initialize the Swift package

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `README.md`
- Create: `Sources/ScreenshotterCore/Empty.swift` (placeholder so the target compiles)
- Create: `Tests/ScreenshotterCoreTests/EmptyTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Screenshotter",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ScreenshotterCore", targets: ["ScreenshotterCore"]),
        .executable(name: "screenshotter-cli", targets: ["screenshotter-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.18.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
    ],
    targets: [
        .target(
            name: "ScreenshotterCore",
            dependencies: [
                .product(name: "secp256k1", package: "secp256k1.swift"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
            ]
        ),
        .executableTarget(
            name: "screenshotter-cli",
            dependencies: ["ScreenshotterCore"]
        ),
        .testTarget(
            name: "ScreenshotterCoreTests",
            dependencies: ["ScreenshotterCore"]
        ),
    ]
)
```

- [ ] **Step 2: Write `.gitignore`**

```
.build/
.swiftpm/
*.xcodeproj/
.DS_Store
*.swp
```

- [ ] **Step 3: Write minimal `README.md`**

```markdown
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
```

- [ ] **Step 4: Write placeholder Swift sources**

`Sources/ScreenshotterCore/Empty.swift`:

```swift
// Intentionally empty. This file exists so the target compiles before
// we add real sources. Delete when the first real source lands.
```

`Tests/ScreenshotterCoreTests/EmptyTests.swift`:

```swift
import Testing

@Test func packageBuilds() {
    #expect(Bool(true))
}
```

- [ ] **Step 5: Run build + test**

Run:
```
swift build
swift test
```

Expected: build succeeds; one test passes ("Test packageBuilds passed").

If `swift test` fails because `swift-testing` isn't found, ensure you're on Swift 6.0+ (`swift --version`). Swift 6 ships with `swift-testing` built in.

- [ ] **Step 6: Commit**

```
git add Package.swift .gitignore README.md Sources Tests
git commit -m "Scaffold Swift package with library + CLI targets"
```

---

### Task 2: Add a Makefile for common dev commands

**Files:**
- Create: `Makefile`

- [ ] **Step 1: Write `Makefile`**

```makefile
.PHONY: build test clean cli integration

build:
	swift build

test:
	swift test

cli:
	swift run screenshotter-cli $(ARGS)

integration:
	SCREENSHOTTER_INTEGRATION=1 swift test

clean:
	swift package clean
	rm -rf .build
```

- [ ] **Step 2: Verify**

Run:
```
make build
make test
```

Expected: both succeed; `make test` shows the EmptyTests passing.

- [ ] **Step 3: Commit**

```
git add Makefile
git commit -m "Add Makefile with build/test/cli/integration targets"
```

---

## Phase 1 — Protocol research

### Task 3: Document the MPP/x402 protocol from `mpp-remote`

**Files:**
- Create: `docs/superpowers/protocol/mpp-x402.md`

This task is research, not implementation. The output is a protocol document that subsequent tasks reference.

- [ ] **Step 1: Clone `mpp-remote` to a scratch directory**

```
mkdir -p /tmp/mpp-research
cd /tmp/mpp-research
git clone https://github.com/tellyworth/mpp-remote.git
cd mpp-remote
ls -la
```

If the repo is private, ask the user for read access or for a tarball. The package is referenced from `~/.claude.json` as `github:tellyworth/mpp-remote`, so npm-level access likely works (`npm pack github:tellyworth/mpp-remote` produces a tarball even for private repos when authenticated).

- [ ] **Step 2: Identify and read the payment-handling code**

Open every `.js`, `.ts`, or `.mjs` file in the repo. Specifically look for:
- Where a 402 response is detected (status code, JSON-RPC error code `-32042`, or both).
- The shape of the challenge payload (look for `eip712`, `domain`, `types`, `primaryType`, `message` fields, or analogous).
- How the payment header is named (commonly `X-PAYMENT`, but verify).
- How the signed payload is encoded (raw r/s/v, RLP-encoded transaction, EIP-712 signature struct, etc.).
- Whether the retry is a new HTTP request or an existing-stream continuation.
- The maximum-amount enforcement (look for `MAX_AMOUNT_USD` or analogous).
- The wallet derivation path (typically the private key in env var maps directly to an Ethereum keypair).

- [ ] **Step 3: Write `docs/superpowers/protocol/mpp-x402.md`**

The document should contain, at minimum:

1. **402 challenge detection:** exact match conditions (HTTP status, JSON-RPC error code, error message format).
2. **Challenge payload schema:** the JSON shape, field by field, with types and example values.
3. **EIP-712 typed-data structure:** domain, types, primaryType, message — all field names and types verbatim.
4. **Signature encoding:** how to format `r`, `s`, `v` (or `yParity`) into the header value.
5. **Header name and format:** e.g., `X-PAYMENT: <base64-encoded-json>` or `X-PAYMENT: 0x<rsv-hex>`. Verify exact.
6. **Retry semantics:** new HTTP request? Same connection? Idempotency considerations.
7. **Wallet derivation:** how the env-var private key maps to an Ethereum address (standard secp256k1 → keccak256 of uncompressed pubkey → last 20 bytes, but confirm).
8. **At least one fully-worked example:** an input challenge, the wallet key, the signed header value, and the expected retry request. This becomes the test vector for Task 9 and Task 16.

- [ ] **Step 4: Commit**

```
git add docs/superpowers/protocol/mpp-x402.md
git commit -m "Document MPP/x402 protocol from mpp-remote reference implementation"
```

---

## Phase 2 — Wallet

### Task 4: Hex encoding utilities

**Files:**
- Create: `Sources/ScreenshotterCore/HexAndHash/HexCoding.swift`
- Create: `Tests/ScreenshotterCoreTests/HexAndHashTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ScreenshotterCoreTests/HexAndHashTests.swift`:

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func hexEncodingRoundTrip() throws {
    let data = Data([0x00, 0xff, 0xab, 0xcd])
    #expect(data.hexEncodedString() == "00ffabcd")
    #expect(data.hexEncodedString(prefix: true) == "0x00ffabcd")
    #expect(try Data(hexString: "0x00ffabcd") == data)
    #expect(try Data(hexString: "00FFABCD") == data)
}

@Test func hexEncodingRejectsInvalid() {
    #expect(throws: HexError.self) { try Data(hexString: "0xZZ") }
    #expect(throws: HexError.self) { try Data(hexString: "abc") } // odd length
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter HexAndHashTests
```

Expected: fails with "no such method `hexEncodedString`" and `Data(hexString:)`.

- [ ] **Step 3: Implement**

`Sources/ScreenshotterCore/HexAndHash/HexCoding.swift`:

```swift
import Foundation

public enum HexError: Error, Equatable {
    case oddLength
    case invalidCharacter(Character)
}

public extension Data {
    func hexEncodedString(prefix: Bool = false) -> String {
        let body = map { String(format: "%02x", $0) }.joined()
        return prefix ? "0x" + body : body
    }

    init(hexString: String) throws {
        var s = hexString
        if s.hasPrefix("0x") || s.hasPrefix("0X") {
            s = String(s.dropFirst(2))
        }
        guard s.count % 2 == 0 else { throw HexError.oddLength }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(s.count / 2)
        var index = s.startIndex
        while index < s.endIndex {
            let next = s.index(index, offsetBy: 2)
            guard let byte = UInt8(s[index..<next], radix: 16) else {
                throw HexError.invalidCharacter(s[index])
            }
            bytes.append(byte)
            index = next
        }
        self = Data(bytes)
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter HexAndHashTests
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/HexAndHash/HexCoding.swift Tests/ScreenshotterCoreTests/HexAndHashTests.swift
git commit -m "Add Data hex encoding/decoding utilities"
```

---

### Task 5: keccak256

**Files:**
- Create: `Sources/ScreenshotterCore/HexAndHash/Keccak.swift`
- Modify: `Tests/ScreenshotterCoreTests/HexAndHashTests.swift`

- [ ] **Step 1: Add failing test**

Append to `Tests/ScreenshotterCoreTests/HexAndHashTests.swift`:

```swift
@Test func keccak256KnownVectors() throws {
    // Empty input vector
    let empty = Data().keccak256()
    #expect(empty.hexEncodedString() == "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")

    // ASCII "abc" vector
    let abc = "abc".data(using: .utf8)!.keccak256()
    #expect(abc.hexEncodedString() == "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45")
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter HexAndHashTests
```

Expected: fails — `keccak256()` not defined on `Data`.

- [ ] **Step 3: Implement**

`Sources/ScreenshotterCore/HexAndHash/Keccak.swift`:

```swift
import Foundation
import CryptoSwift

public extension Data {
    /// Keccak-256 (used by Ethereum). NOT the same as SHA3-256 standardized by NIST,
    /// which has a different padding rule.
    func keccak256() -> Data {
        Data(self.sha3(.keccak256))
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter HexAndHashTests
```

Expected: all three tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/HexAndHash/Keccak.swift Tests/ScreenshotterCoreTests/HexAndHashTests.swift
git commit -m "Add keccak256 extension on Data using CryptoSwift"
```

---

### Task 6: secp256k1 keypair and signing

**Files:**
- Create: `Sources/ScreenshotterCore/Wallet/Secp256k1Signer.swift`
- Create: `Tests/ScreenshotterCoreTests/Secp256k1SignerTests.swift`

The `secp256k1.swift` package's API has evolved; this plan uses the surface as of v0.18+. If the API differs in the version resolved, update the calls accordingly and document in a comment.

- [ ] **Step 1: Write the failing test**

`Tests/ScreenshotterCoreTests/Secp256k1SignerTests.swift`:

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func signerProducesValidSignature() throws {
    // Known private key from Ethereum test vector (not a real funded key)
    let privKey = try Data(hexString: "0x4646464646464646464646464646464646464646464646464646464646464646")
    let signer = try Secp256k1Signer(privateKey: privKey)

    // A 32-byte digest to sign (arbitrary)
    let digest = try Data(hexString: "0xdaf5a779ae972f972197303d7b574746c7ef83eadac0f2791ad23db92e4c8e53")

    let sig = try signer.signRecoverable(digest: digest)
    #expect(sig.r.count == 32)
    #expect(sig.s.count == 32)
    #expect(sig.v == 0 || sig.v == 1)  // recovery id is 0 or 1
}

@Test func signerExposesPublicKey() throws {
    let privKey = try Data(hexString: "0x4646464646464646464646464646464646464646464646464646464646464646")
    let signer = try Secp256k1Signer(privateKey: privKey)
    // Uncompressed pubkey is 65 bytes (0x04 || X || Y)
    #expect(signer.publicKeyUncompressed.count == 65)
    #expect(signer.publicKeyUncompressed[0] == 0x04)
}

@Test func signerGeneratesNewKey() throws {
    let a = try Secp256k1Signer.generate()
    let b = try Secp256k1Signer.generate()
    #expect(a.privateKey != b.privateKey)
    #expect(a.privateKey.count == 32)
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter Secp256k1SignerTests
```

Expected: fails — type `Secp256k1Signer` undefined.

- [ ] **Step 3: Implement**

`Sources/ScreenshotterCore/Wallet/Secp256k1Signer.swift`:

```swift
import Foundation
import secp256k1

public struct RecoverableSignature: Equatable {
    public let r: Data        // 32 bytes
    public let s: Data        // 32 bytes
    public let v: UInt8       // recovery id: 0 or 1
}

public enum Secp256k1Error: Error {
    case invalidPrivateKeyLength
    case signingFailed
    case keyGenerationFailed
}

public struct Secp256k1Signer {
    public let privateKey: Data            // 32 bytes
    public let publicKeyUncompressed: Data // 65 bytes (0x04 || X || Y)

    public init(privateKey: Data) throws {
        guard privateKey.count == 32 else { throw Secp256k1Error.invalidPrivateKeyLength }
        let key = try secp256k1.Signing.PrivateKey(dataRepresentation: privateKey)
        self.privateKey = privateKey
        // .format == .uncompressed yields the 65-byte form
        self.publicKeyUncompressed = Data(key.publicKey.rawRepresentation)
    }

    public static func generate() throws -> Secp256k1Signer {
        let key = try secp256k1.Signing.PrivateKey()
        return try Secp256k1Signer(privateKey: Data(key.dataRepresentation))
    }

    /// Sign a precomputed 32-byte digest. The digest is signed as-is, no extra hashing.
    public func signRecoverable(digest: Data) throws -> RecoverableSignature {
        guard digest.count == 32 else { throw Secp256k1Error.signingFailed }
        let key = try secp256k1.Recovery.PrivateKey(dataRepresentation: privateKey)
        let signature = try key.signature(for: digest)
        // signature.dataRepresentation is 65 bytes: r (32) || s (32) || v (1)
        let raw = Data(signature.dataRepresentation)
        guard raw.count == 65 else { throw Secp256k1Error.signingFailed }
        return RecoverableSignature(
            r: raw.subdata(in: 0..<32),
            s: raw.subdata(in: 32..<64),
            v: raw[64]
        )
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter Secp256k1SignerTests
```

Expected: all three tests pass. If the secp256k1 API differs in the resolved version (e.g., recovery types are named differently), adapt the calls — the public surface of `Secp256k1Signer` should remain identical so dependent code is unaffected.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/Wallet/Secp256k1Signer.swift Tests/ScreenshotterCoreTests/Secp256k1SignerTests.swift
git commit -m "Add Secp256k1Signer with key generation and recoverable signing"
```

---

### Task 7: Ethereum address derivation

**Files:**
- Create: `Sources/ScreenshotterCore/Wallet/EthereumAddress.swift`
- Create: `Tests/ScreenshotterCoreTests/EthereumAddressTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func addressFromKnownPrivateKey() throws {
    // Vitalik's test private key (publicly known, never use for real funds):
    // priv 0x4646464646464646464646464646464646464646464646464646464646464646
    // addr 0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f
    let priv = try Data(hexString: "0x4646464646464646464646464646464646464646464646464646464646464646")
    let signer = try Secp256k1Signer(privateKey: priv)
    let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
    #expect(address.hexString() == "0x9d8a62f656a8d1615c1294fd71e9cfb3e4855a4f")
}

@Test func addressRejectsBadPublicKey() {
    #expect(throws: EthereumAddressError.self) {
        _ = try EthereumAddress(uncompressedPublicKeyOrThrow: Data([0x04, 0x01, 0x02]))
    }
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter EthereumAddressTests
```

Expected: fails — `EthereumAddress` undefined.

- [ ] **Step 3: Implement**

`Sources/ScreenshotterCore/Wallet/EthereumAddress.swift`:

```swift
import Foundation

public enum EthereumAddressError: Error {
    case badPublicKeyLength
}

public struct EthereumAddress: Equatable, Hashable {
    /// 20 raw bytes.
    public let bytes: Data

    public init(bytes: Data) {
        precondition(bytes.count == 20)
        self.bytes = bytes
    }

    /// Derive from a 65-byte uncompressed secp256k1 public key (0x04 || X || Y).
    public init(uncompressedPublicKey: Data) {
        precondition(uncompressedPublicKey.count == 65 && uncompressedPublicKey[0] == 0x04)
        // Hash the 64-byte X||Y (drop the leading 0x04), take the last 20 bytes.
        let xy = uncompressedPublicKey.suffix(64)
        let hash = Data(xy).keccak256()
        self.bytes = hash.suffix(20)
    }

    public init(uncompressedPublicKeyOrThrow pub: Data) throws {
        guard pub.count == 65, pub[0] == 0x04 else { throw EthereumAddressError.badPublicKeyLength }
        self.init(uncompressedPublicKey: pub)
    }

    /// Lowercase 0x-prefixed hex string. (EIP-55 mixed-case checksumming not needed for our use.)
    public func hexString() -> String {
        bytes.hexEncodedString(prefix: true)
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter EthereumAddressTests
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/Wallet/EthereumAddress.swift Tests/ScreenshotterCoreTests/EthereumAddressTests.swift
git commit -m "Derive Ethereum addresses from uncompressed secp256k1 public keys"
```

---

### Task 8: KeychainStore protocol + macOS implementation

**Files:**
- Create: `Sources/ScreenshotterCore/Wallet/KeychainStore.swift`
- Create: `Tests/ScreenshotterCoreTests/Fixtures/InMemoryKeychainStore.swift`

This task defines an abstraction. The real Keychain implementation is tested via a separate gated XCTest target (Task 8b) because Keychain has machine-level side effects unsuitable for fast unit runs.

- [ ] **Step 1: Define the protocol and the in-memory mock first**

`Sources/ScreenshotterCore/Wallet/KeychainStore.swift`:

```swift
import Foundation
import Security

public protocol KeychainStore: Sendable {
    func read(account: String, service: String) throws -> Data?
    func write(_ data: Data, account: String, service: String) throws
    func delete(account: String, service: String) throws
}

public enum KeychainError: Error {
    case osStatus(OSStatus)
}

public struct MacOSKeychainStore: KeychainStore {
    public init() {}

    public func read(account: String, service: String) throws -> Data? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var ref: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &ref)
        switch status {
        case errSecSuccess:
            return ref as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.osStatus(status)
        }
    }

    public func write(_ data: Data, account: String, service: String) throws {
        let attrs: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let addStatus = SecItemAdd(attrs as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ]
            let updateAttrs: [CFString: Any] = [kSecValueData: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttrs as CFDictionary)
            if updateStatus != errSecSuccess {
                throw KeychainError.osStatus(updateStatus)
            }
        } else if addStatus != errSecSuccess {
            throw KeychainError.osStatus(addStatus)
        }
    }

    public func delete(account: String, service: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.osStatus(status)
        }
    }
}
```

`Tests/ScreenshotterCoreTests/Fixtures/InMemoryKeychainStore.swift`:

```swift
import Foundation
@testable import ScreenshotterCore

final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()

    private func key(account: String, service: String) -> String { "\(service)/\(account)" }

    func read(account: String, service: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key(account: account, service: service)]
    }
    func write(_ data: Data, account: String, service: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key(account: account, service: service)] = data
    }
    func delete(account: String, service: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage.removeValue(forKey: key(account: account, service: service))
    }
}
```

- [ ] **Step 2: Verify the build still succeeds**

```
swift build
```

Expected: success (no new tests yet — the abstraction is used in Task 10).

- [ ] **Step 3: Commit**

```
git add Sources/ScreenshotterCore/Wallet/KeychainStore.swift Tests/ScreenshotterCoreTests/Fixtures/InMemoryKeychainStore.swift
git commit -m "Define KeychainStore protocol with macOS implementation and in-memory mock"
```

---

### Task 8b: KeychainStore integration test (XCTest, gated)

**Files:**
- Modify: `Package.swift` to add a second test target
- Create: `Tests/KeychainStoreTests/KeychainStoreTests.swift`

This target uses XCTest because it needs setUp/tearDown to clean up real Keychain entries. It's gated on an env var so CI runs that lack Keychain access don't fail.

- [ ] **Step 1: Update `Package.swift`**

In the `targets:` array, add at the end:

```swift
        .testTarget(
            name: "KeychainStoreTests",
            dependencies: ["ScreenshotterCore"]
        ),
```

- [ ] **Step 2: Write the test**

`Tests/KeychainStoreTests/KeychainStoreTests.swift`:

```swift
import XCTest
@testable import ScreenshotterCore

final class KeychainStoreTests: XCTestCase {
    let service = "com.bongnam.screenshotter.tests"
    let account = "integration-test-\(UUID().uuidString)"
    let sut = MacOSKeychainStore()

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["SCREENSHOTTER_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Set SCREENSHOTTER_KEYCHAIN_TESTS=1 to run Keychain integration tests.")
        }
        try? sut.delete(account: account, service: service)
    }

    override func tearDown() async throws {
        try? sut.delete(account: account, service: service)
    }

    func testRoundTrip() throws {
        let data = Data([0xde, 0xad, 0xbe, 0xef])
        try sut.write(data, account: account, service: service)
        let read = try sut.read(account: account, service: service)
        XCTAssertEqual(read, data)
    }

    func testOverwrite() throws {
        try sut.write(Data([0x01]), account: account, service: service)
        try sut.write(Data([0x02]), account: account, service: service)
        XCTAssertEqual(try sut.read(account: account, service: service), Data([0x02]))
    }

    func testDelete() throws {
        try sut.write(Data([0x01]), account: account, service: service)
        try sut.delete(account: account, service: service)
        XCTAssertNil(try sut.read(account: account, service: service))
    }
}
```

- [ ] **Step 3: Run with env var set**

```
SCREENSHOTTER_KEYCHAIN_TESTS=1 swift test --filter KeychainStoreTests
```

Expected: three tests pass. The first run may prompt for permission to access the keychain (which is fine).

- [ ] **Step 4: Run without env var, expect skipped**

```
swift test --filter KeychainStoreTests
```

Expected: three tests skipped (XCTSkip).

- [ ] **Step 5: Commit**

```
git add Package.swift Tests/KeychainStoreTests/KeychainStoreTests.swift
git commit -m "Add gated XCTest integration tests for MacOSKeychainStore"
```

---

### Task 9: EIP-712 typed-data hashing

**Files:**
- Create: `Sources/ScreenshotterCore/Wallet/EIP712.swift`
- Create: `Tests/ScreenshotterCoreTests/EIP712Tests.swift`
- Create: `Tests/ScreenshotterCoreTests/Fixtures/EIP712Vectors.swift`

EIP-712 is defined in https://eips.ethereum.org/EIPS/eip-712. The exact MPP typed-data schema is captured in `docs/superpowers/protocol/mpp-x402.md` (Task 3). The implementation here is the **generic** hasher that the MPP schema will plug into. **At minimum**, the implementation must handle the field types used by MPP: `address`, `uint256`, `string`, `bytes`, plus nested typed structs. Arrays are unlikely in MPP and can be added if `mpp-x402.md` requires them.

- [ ] **Step 1: Add the vectors file**

`Tests/ScreenshotterCoreTests/Fixtures/EIP712Vectors.swift`:

```swift
import Foundation

/// Canonical EIP-712 example from the spec:
/// https://eips.ethereum.org/EIPS/eip-712#specification-of-the-eth_signtypeddata-json-rpc
enum EIP712Vectors {
    static let mailExampleJSON = """
    {
      "types": {
        "EIP712Domain": [
          {"name":"name","type":"string"},
          {"name":"version","type":"string"},
          {"name":"chainId","type":"uint256"},
          {"name":"verifyingContract","type":"address"}
        ],
        "Person": [
          {"name":"name","type":"string"},
          {"name":"wallet","type":"address"}
        ],
        "Mail": [
          {"name":"from","type":"Person"},
          {"name":"to","type":"Person"},
          {"name":"contents","type":"string"}
        ]
      },
      "primaryType": "Mail",
      "domain": {
        "name": "Ether Mail",
        "version": "1",
        "chainId": 1,
        "verifyingContract": "0xCcCCccccCCCCcCCCCCCcCcCccCcCCCcCcccccccC"
      },
      "message": {
        "from": {"name":"Cow","wallet":"0xCD2a3d9F938E13CD947Ec05AbC7FE734Df8DD826"},
        "to":   {"name":"Bob","wallet":"0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB"},
        "contents": "Hello, Bob!"
      }
    }
    """

    /// The final EIP-712 digest for the Mail example, per the spec.
    /// keccak256("\\x19\\x01" || domainSeparator || hashStruct(message))
    static let mailExampleDigestHex = "0xbe609aee343fb3c4b28e1df9e632fca64fcfaede20f02e86244efddf30957bd2"
}
```

- [ ] **Step 2: Write the failing test**

`Tests/ScreenshotterCoreTests/EIP712Tests.swift`:

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func eip712CanonicalMailExample() throws {
    let data = EIP712Vectors.mailExampleJSON.data(using: .utf8)!
    let typedData = try JSONDecoder().decode(EIP712TypedData.self, from: data)
    let digest = try typedData.encodedDigest()
    #expect(digest.hexEncodedString(prefix: true) == EIP712Vectors.mailExampleDigestHex)
}
```

- [ ] **Step 3: Run, expect fail**

```
swift test --filter EIP712Tests
```

Expected: fails — `EIP712TypedData` undefined.

- [ ] **Step 4: Implement**

`Sources/ScreenshotterCore/Wallet/EIP712.swift`:

```swift
import Foundation

public enum EIP712Error: Error {
    case unknownType(String)
    case unsupportedFieldType(String)
    case missingField(String)
    case malformedNumber(String)
    case malformedAddress(String)
}

public struct EIP712TypeField: Codable, Hashable {
    public let name: String
    public let type: String
}

/// A generic JSON value (since EIP-712 message fields are heterogeneous).
public enum EIP712Value: Codable, Hashable {
    case string(String)
    case number(String)   // keep as string to avoid precision loss for uint256
    case bool(Bool)
    case object([String: EIP712Value])
    case array([EIP712Value])
    case null

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let n = try? c.decode(Double.self) {
            // Preserve integer-ness in our string form when possible
            if n.rounded() == n && abs(n) < 1e15 {
                self = .number(String(Int64(n)))
            } else {
                self = .number(String(n))
            }
            return
        }
        if let arr = try? c.decode([EIP712Value].self) { self = .array(arr); return }
        if let dict = try? c.decode([String: EIP712Value].self) { self = .object(dict); return }
        self = .null
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .number(let n):
            // Emit as JSON number when representable, else fall back to string
            // (uint256 values that exceed Int64.max — uncommon for MPP USDC amounts).
            if let i = Int64(n) {
                try c.encode(i)
            } else if let d = Double(n) {
                try c.encode(d)
            } else {
                try c.encode(n)
            }
        case .bool(let b):   try c.encode(b)
        case .object(let o): try c.encode(o)
        case .array(let a):  try c.encode(a)
        case .null:          try c.encodeNil()
        }
    }

    public var stringValue: String? { if case .string(let s) = self { return s } else { return nil } }
    public var objectValue: [String: EIP712Value]? { if case .object(let o) = self { return o } else { return nil } }
}

public struct EIP712TypedData: Codable {
    public let types: [String: [EIP712TypeField]]
    public let primaryType: String
    public let domain: [String: EIP712Value]
    public let message: [String: EIP712Value]

    public init(
        types: [String: [EIP712TypeField]],
        primaryType: String,
        domain: [String: EIP712Value],
        message: [String: EIP712Value]
    ) {
        self.types = types
        self.primaryType = primaryType
        self.domain = domain
        self.message = message
    }

    /// keccak256("\x19\x01" || domainSeparator || hashStruct(message))
    public func encodedDigest() throws -> Data {
        let domainSep = try hashStruct(type: "EIP712Domain", data: domain)
        let messageHash = try hashStruct(type: primaryType, data: message)
        var preimage = Data([0x19, 0x01])
        preimage.append(domainSep)
        preimage.append(messageHash)
        return preimage.keccak256()
    }

    // MARK: EIP-712 internals

    func hashStruct(type: String, data: [String: EIP712Value]) throws -> Data {
        let typeHash = try encodeType(primary: type).data(using: .utf8)!.keccak256()
        var encoded = typeHash
        guard let fields = types[type] else { throw EIP712Error.unknownType(type) }
        for field in fields {
            guard let value = data[field.name] else { throw EIP712Error.missingField(field.name) }
            encoded.append(try encodeValue(type: field.type, value: value))
        }
        return encoded.keccak256()
    }

    func encodeType(primary: String) throws -> String {
        var dependencies: Set<String> = []
        try collectDependencies(of: primary, into: &dependencies)
        dependencies.remove(primary)
        let ordered = [primary] + dependencies.sorted()
        return ordered.map { name -> String in
            guard let fields = types[name] else { return "" }
            let inner = fields.map { "\($0.type) \($0.name)" }.joined(separator: ",")
            return "\(name)(\(inner))"
        }.joined()
    }

    func collectDependencies(of type: String, into set: inout Set<String>) throws {
        guard let fields = types[type] else { return }
        for field in fields {
            let baseType = field.type.replacingOccurrences(of: "[]", with: "")
            if types[baseType] != nil, !set.contains(baseType) {
                set.insert(baseType)
                try collectDependencies(of: baseType, into: &set)
            }
        }
    }

    func encodeValue(type: String, value: EIP712Value) throws -> Data {
        // Nested struct
        if let _ = types[type] {
            guard case .object(let obj) = value else { throw EIP712Error.missingField(type) }
            return try hashStruct(type: type, data: obj)
        }
        switch type {
        case "string":
            guard case .string(let s) = value else { throw EIP712Error.unsupportedFieldType(type) }
            return s.data(using: .utf8)!.keccak256()
        case "bytes":
            guard case .string(let hex) = value else { throw EIP712Error.unsupportedFieldType(type) }
            return try Data(hexString: hex).keccak256()
        case "bool":
            guard case .bool(let b) = value else { throw EIP712Error.unsupportedFieldType(type) }
            return leftPad(Data([b ? 1 : 0]), to: 32)
        case "address":
            guard case .string(let s) = value else { throw EIP712Error.malformedAddress(type) }
            let raw = try Data(hexString: s)
            guard raw.count == 20 else { throw EIP712Error.malformedAddress(s) }
            return leftPad(raw, to: 32)
        default:
            // uintN / intN — encode as 32-byte big-endian. We require values as decimal strings.
            if type.hasPrefix("uint") || type.hasPrefix("int") {
                guard case .number(let n) = value else { throw EIP712Error.unsupportedFieldType(type) }
                guard let big = UInt256(decimalString: n) else { throw EIP712Error.malformedNumber(n) }
                return big.bigEndianData(width: 32)
            }
            throw EIP712Error.unsupportedFieldType(type)
        }
    }

    private func leftPad(_ d: Data, to width: Int) -> Data {
        if d.count >= width { return d }
        return Data(count: width - d.count) + d
    }
}

/// Minimal 256-bit unsigned integer parser tailored for EIP-712 encoding.
/// Uses native UInt64 limbs for values that fit (MPP amounts in micro-USDC are well within UInt64);
/// for larger values, falls back to a simple big-int routine. This avoids a heavy big-int dependency.
struct UInt256 {
    /// Big-endian byte representation, 0-padded later.
    let bytes: [UInt8]

    init?(decimalString s: String) {
        // Convert decimal string to big-endian bytes via base-10 repeated divmod.
        let digits = s.compactMap { $0.wholeNumberValue }
        guard digits.count == s.count, !digits.isEmpty else { return nil }
        var current = digits
        var out: [UInt8] = []
        while !current.allSatisfy({ $0 == 0 }) {
            var remainder = 0
            var next: [Int] = []
            next.reserveCapacity(current.count)
            for d in current {
                let acc = remainder * 10 + d
                next.append(acc / 256)
                remainder = acc % 256
            }
            // Trim leading zeros in `next`
            while next.first == 0 && next.count > 1 { next.removeFirst() }
            current = next
            out.append(UInt8(remainder))
        }
        if out.isEmpty { out = [0] }
        self.bytes = out.reversed()  // little-endian collection reversed = big-endian
    }

    func bigEndianData(width: Int) -> Data {
        precondition(bytes.count <= width, "value too large for width=\(width)")
        var d = Data(count: width - bytes.count)
        d.append(contentsOf: bytes)
        return d
    }
}
```

- [ ] **Step 5: Run, expect pass**

```
swift test --filter EIP712Tests
```

Expected: the mail-example digest matches. If it doesn't match exactly, the most common bug is in `encodeType` ordering — EIP-712 sorts referenced types alphabetically. Double-check against `encodeType` in the spec text.

- [ ] **Step 6: Commit**

```
git add Sources/ScreenshotterCore/Wallet/EIP712.swift Tests/ScreenshotterCoreTests/EIP712Tests.swift Tests/ScreenshotterCoreTests/Fixtures/EIP712Vectors.swift
git commit -m "Implement generic EIP-712 typed-data hashing with canonical mail-example test"
```

---

### Task 10: Wallet façade

**Files:**
- Create: `Sources/ScreenshotterCore/Wallet/Wallet.swift`
- Create: `Tests/ScreenshotterCoreTests/WalletTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ScreenshotterCoreTests/WalletTests.swift`:

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func walletGeneratesAndPersists() throws {
    let store = InMemoryKeychainStore()
    let a = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let b = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    #expect(a.address == b.address)
    #expect(a.address.bytes.count == 20)
}

@Test func walletSignsEIP712() throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let data = EIP712Vectors.mailExampleJSON.data(using: .utf8)!
    let typed = try JSONDecoder().decode(EIP712TypedData.self, from: data)
    let sig = try wallet.signEIP712(typed)
    #expect(sig.r.count == 32)
    #expect(sig.s.count == 32)
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter WalletTests
```

Expected: fails — `Wallet` undefined.

- [ ] **Step 3: Implement**

`Sources/ScreenshotterCore/Wallet/Wallet.swift`:

```swift
import Foundation

public struct Wallet {
    public let address: EthereumAddress
    private let signer: Secp256k1Signer

    public static func loadOrCreate(
        keychain: KeychainStore,
        service: String,
        account: String
    ) throws -> Wallet {
        let privKey: Data
        if let existing = try keychain.read(account: account, service: service) {
            privKey = existing
        } else {
            let fresh = try Secp256k1Signer.generate()
            try keychain.write(fresh.privateKey, account: account, service: service)
            privKey = fresh.privateKey
        }
        let signer = try Secp256k1Signer(privateKey: privKey)
        let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
        return Wallet(address: address, signer: signer)
    }

    public func signEIP712(_ typedData: EIP712TypedData) throws -> RecoverableSignature {
        let digest = try typedData.encodedDigest()
        return try signer.signRecoverable(digest: digest)
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter WalletTests
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/Wallet/Wallet.swift Tests/ScreenshotterCoreTests/WalletTests.swift
git commit -m "Add Wallet façade: load-or-create from Keychain, signEIP712"
```

---

## Phase 3 — MCP transport

### Task 11: JSON-RPC 2.0 framing types

**Files:**
- Create: `Sources/ScreenshotterCore/MCP/JSONRPC.swift`
- Create: `Tests/ScreenshotterCoreTests/JSONRPCTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/ScreenshotterCoreTests/JSONRPCTests.swift`:

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func jsonRPCRequestRoundTrip() throws {
    let req = JSONRPCRequest(
        id: .number(1),
        method: "tools/call",
        params: ["name": .string("quick_upload")]
    )
    let data = try JSONEncoder().encode(req)
    let decoded = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
    #expect(decoded.method == "tools/call")
    #expect(decoded.params?["name"] == .string("quick_upload"))
}

@Test func jsonRPCResponseSuccessDecode() throws {
    let json = #"{"jsonrpc":"2.0","id":1,"result":{"item_id":"abc"}}"#.data(using: .utf8)!
    let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: json)
    if case .success(let value) = resp.outcome {
        #expect(value.objectValue?["item_id"] == .string("abc"))
    } else {
        Issue.record("expected success outcome")
    }
}

@Test func jsonRPCResponseErrorDecode() throws {
    let json = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required","data":{"foo":"bar"}}}"#.data(using: .utf8)!
    let resp = try JSONDecoder().decode(JSONRPCResponse.self, from: json)
    if case .failure(let err) = resp.outcome {
        #expect(err.code == -32042)
        #expect(err.message == "payment required")
    } else {
        Issue.record("expected failure outcome")
    }
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter JSONRPCTests
```

Expected: fails — types undefined.

- [ ] **Step 3: Implement**

`Sources/ScreenshotterCore/MCP/JSONRPC.swift`:

```swift
import Foundation

public enum JSONRPCID: Codable, Hashable {
    case number(Int)
    case string(String)

    public init(from d: Decoder) throws {
        let c = try d.singleValueContainer()
        if let i = try? c.decode(Int.self) { self = .number(i); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.typeMismatch(JSONRPCID.self,
            .init(codingPath: d.codingPath, debugDescription: "id must be int or string"))
    }
    public func encode(to e: Encoder) throws {
        var c = e.singleValueContainer()
        switch self {
        case .number(let i): try c.encode(i)
        case .string(let s): try c.encode(s)
        }
    }
}

public struct JSONRPCRequest: Codable {
    public let jsonrpc = "2.0"
    public let id: JSONRPCID
    public let method: String
    public let params: [String: EIP712Value]?

    public init(id: JSONRPCID, method: String, params: [String: EIP712Value]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }

    enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(jsonrpc, forKey: .jsonrpc)
        try c.encode(id, forKey: .id)
        try c.encode(method, forKey: .method)
        try c.encodeIfPresent(params, forKey: .params)
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(JSONRPCID.self, forKey: .id)
        self.method = try c.decode(String.self, forKey: .method)
        self.params = try c.decodeIfPresent([String: EIP712Value].self, forKey: .params)
    }
}

public struct JSONRPCError: Codable, Error {
    public let code: Int
    public let message: String
    public let data: EIP712Value?
}

public struct JSONRPCResponse: Codable {
    public let id: JSONRPCID?
    public enum Outcome { case success(EIP712Value), failure(JSONRPCError) }
    public let outcome: Outcome

    enum CodingKeys: String, CodingKey { case id, result, error }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(JSONRPCID.self, forKey: .id)
        if let err = try c.decodeIfPresent(JSONRPCError.self, forKey: .error) {
            self.outcome = .failure(err)
        } else {
            let value = try c.decodeIfPresent(EIP712Value.self, forKey: .result) ?? .null
            self.outcome = .success(value)
        }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id)
        switch outcome {
        case .success(let v): try c.encode(v, forKey: .result)
        case .failure(let e): try c.encode(e, forKey: .error)
        }
    }
}
```

(`EIP712Value` is reused here as our general JSON value type — it already handles strings, numbers, bools, objects, arrays, and null. A name like `JSONValue` would be cleaner; a renaming PR is fine future work.)

- [ ] **Step 4: Run, expect pass**

```
swift test --filter JSONRPCTests
```

Expected: all three tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/MCP/JSONRPC.swift Tests/ScreenshotterCoreTests/JSONRPCTests.swift
git commit -m "Add JSON-RPC 2.0 Codable types for MCP transport"
```

---

### Task 12: Server-Sent Events parser

**Files:**
- Create: `Sources/ScreenshotterCore/MCP/SSEReader.swift`
- Create: `Tests/ScreenshotterCoreTests/SSEReaderTests.swift`

The SSE format is line-oriented: each `\n\n` separates an event. Lines beginning with `data:` accumulate; `event:` sets the event type; `id:` sets the last-event id; comments start with `:`. We only need `data:` for MCP responses.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func sseReaderParsesSingleDataEvent() async throws {
    let stream = AsyncStream<Data> { cont in
        cont.yield("data: {\"hello\":\"world\"}\n\n".data(using: .utf8)!)
        cont.finish()
    }
    var events: [SSEEvent] = []
    for try await event in SSEReader(byteStream: stream).events {
        events.append(event)
    }
    #expect(events.count == 1)
    #expect(events[0].data == "{\"hello\":\"world\"}")
}

@Test func sseReaderHandlesMultilineData() async throws {
    let payload = "data: line1\ndata: line2\n\n"
    let stream = AsyncStream<Data> { cont in
        cont.yield(payload.data(using: .utf8)!)
        cont.finish()
    }
    var events: [SSEEvent] = []
    for try await event in SSEReader(byteStream: stream).events { events.append(event) }
    #expect(events.count == 1)
    #expect(events[0].data == "line1\nline2")
}

@Test func sseReaderHandlesChunkedDelivery() async throws {
    let stream = AsyncStream<Data> { cont in
        cont.yield("data: hel".data(using: .utf8)!)
        cont.yield("lo\n\n".data(using: .utf8)!)
        cont.finish()
    }
    var events: [SSEEvent] = []
    for try await event in SSEReader(byteStream: stream).events { events.append(event) }
    #expect(events.count == 1)
    #expect(events[0].data == "hello")
}

@Test func sseReaderIgnoresComments() async throws {
    let stream = AsyncStream<Data> { cont in
        cont.yield(": heartbeat\n\ndata: x\n\n".data(using: .utf8)!)
        cont.finish()
    }
    var events: [SSEEvent] = []
    for try await event in SSEReader(byteStream: stream).events { events.append(event) }
    #expect(events.count == 1)
    #expect(events[0].data == "x")
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter SSEReaderTests
```

Expected: fails — `SSEReader`, `SSEEvent` undefined.

- [ ] **Step 3: Implement**

`Sources/ScreenshotterCore/MCP/SSEReader.swift`:

```swift
import Foundation

public struct SSEEvent: Equatable {
    public let event: String     // "message" by default
    public let data: String
    public let id: String?
}

public struct SSEReader {
    private let byteStream: AsyncStream<Data>
    public init(byteStream: AsyncStream<Data>) { self.byteStream = byteStream }

    public var events: AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var buffer = ""
                var pendingData: [String] = []
                var pendingEvent: String = "message"
                var pendingId: String? = nil

                func flushIfReady() {
                    if !pendingData.isEmpty {
                        let event = SSEEvent(
                            event: pendingEvent,
                            data: pendingData.joined(separator: "\n"),
                            id: pendingId
                        )
                        continuation.yield(event)
                        pendingData.removeAll()
                        pendingEvent = "message"
                    }
                }

                do {
                    for await chunk in byteStream {
                        if let s = String(data: chunk, encoding: .utf8) {
                            buffer.append(s)
                        }
                        while let nl = buffer.firstIndex(of: "\n") {
                            let line = String(buffer[..<nl])
                            buffer.removeSubrange(buffer.startIndex...nl)
                            if line.isEmpty {
                                flushIfReady()
                            } else if line.hasPrefix(":") {
                                continue // comment
                            } else if line.hasPrefix("data:") {
                                let payload = line.dropFirst("data:".count).drop { $0 == " " }
                                pendingData.append(String(payload))
                            } else if line.hasPrefix("event:") {
                                pendingEvent = String(line.dropFirst("event:".count).drop { $0 == " " })
                            } else if line.hasPrefix("id:") {
                                pendingId = String(line.dropFirst("id:".count).drop { $0 == " " })
                            }
                        }
                    }
                    flushIfReady()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter SSEReaderTests
```

Expected: four tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/MCP/SSEReader.swift Tests/ScreenshotterCoreTests/SSEReaderTests.swift
git commit -m "Add SSEReader for Server-Sent Events with chunked input"
```

---

### Task 13: MCPTransport protocol + Streamable HTTP implementation

**Files:**
- Create: `Sources/ScreenshotterCore/MCP/MCPTransport.swift`
- Create: `Sources/ScreenshotterCore/MCP/StreamableHTTPTransport.swift`

This task is split into two files because the protocol is testable (mock transport) while the URLSession implementation is integration-tested via `Uploader`.

- [ ] **Step 1: Define the transport protocol**

`Sources/ScreenshotterCore/MCP/MCPTransport.swift`:

```swift
import Foundation

public protocol MCPTransport: Sendable {
    /// Send a JSON-RPC request; receive either a single response or a stream that eventually yields one.
    /// Implementations may add a payment header on retry; the closure lets PaymentClient inject it.
    func send(
        request: JSONRPCRequest,
        extraHeaders: [String: String]
    ) async throws -> JSONRPCResponse
}
```

- [ ] **Step 2: Implement the URLSession-backed transport**

`Sources/ScreenshotterCore/MCP/StreamableHTTPTransport.swift`:

```swift
import Foundation

public struct StreamableHTTPTransport: MCPTransport {
    public let endpoint: URL
    public let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func send(
        request: JSONRPCRequest,
        extraHeaders: [String: String]
    ) async throws -> JSONRPCResponse {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        for (k, v) in extraHeaders { urlRequest.setValue(v, forHTTPHeaderField: k) }
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("text/event-stream") {
            // SSE response: collect first JSON-RPC response from the stream
            let stream = AsyncStream<Data> { cont in
                Task {
                    do {
                        for try await byte in bytes {
                            cont.yield(Data([byte]))
                        }
                        cont.finish()
                    } catch {
                        cont.finish()
                    }
                }
            }
            for try await event in SSEReader(byteStream: stream).events {
                if let data = event.data.data(using: .utf8) {
                    if let resp = try? JSONDecoder().decode(JSONRPCResponse.self, from: data) {
                        return resp
                    }
                }
            }
            throw URLError(.badServerResponse)
        } else {
            // Single JSON response
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            return try JSONDecoder().decode(JSONRPCResponse.self, from: data)
        }
    }
}
```

- [ ] **Step 3: Verify build**

```
swift build
```

Expected: success. No tests yet for this file — it's tested via `UploaderIntegrationTests` (Task 17).

- [ ] **Step 4: Commit**

```
git add Sources/ScreenshotterCore/MCP/MCPTransport.swift Sources/ScreenshotterCore/MCP/StreamableHTTPTransport.swift
git commit -m "Add MCPTransport protocol and Streamable HTTP implementation"
```

---

### Task 14: MCPClient

**Files:**
- Create: `Sources/ScreenshotterCore/MCP/MCPClient.swift`
- Create: `Tests/ScreenshotterCoreTests/Fixtures/MockMCPTransport.swift`
- Create: `Tests/ScreenshotterCoreTests/MCPClientTests.swift`

- [ ] **Step 1: Write the mock transport fixture**

`Tests/ScreenshotterCoreTests/Fixtures/MockMCPTransport.swift`:

```swift
import Foundation
@testable import ScreenshotterCore

final class MockMCPTransport: MCPTransport, @unchecked Sendable {
    private(set) var receivedRequests: [(request: JSONRPCRequest, headers: [String: String])] = []
    var queuedResponses: [JSONRPCResponse] = []

    func send(
        request: JSONRPCRequest,
        extraHeaders: [String: String]
    ) async throws -> JSONRPCResponse {
        receivedRequests.append((request, extraHeaders))
        guard !queuedResponses.isEmpty else { fatalError("no queued response") }
        return queuedResponses.removeFirst()
    }
}
```

- [ ] **Step 2: Write the failing test**

`Tests/ScreenshotterCoreTests/MCPClientTests.swift`:

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func mcpClientCallsToolAndDecodesResult() async throws {
    let transport = MockMCPTransport()
    // Queue a success response: {"item_id":"abc"}
    let resultJSON = #"{"jsonrpc":"2.0","id":1,"result":{"item_id":"abc","share_url":"https://x.test/abc"}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: resultJSON.data(using: .utf8)!)
    ]
    let client = MCPClient(transport: transport)
    let result = try await client.callTool(name: "quick_upload", arguments: [
        "filename": .string("x.png")
    ])
    #expect(result.objectValue?["item_id"] == .string("abc"))
    #expect(transport.receivedRequests.count == 1)
    #expect(transport.receivedRequests[0].request.method == "tools/call")
}

@Test func mcpClientThrowsJSONRPCError() async throws {
    let transport = MockMCPTransport()
    let errJSON = #"{"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required"}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: errJSON.data(using: .utf8)!)
    ]
    let client = MCPClient(transport: transport)
    await #expect(throws: JSONRPCError.self) {
        _ = try await client.callTool(name: "quick_upload", arguments: [:])
    }
}
```

- [ ] **Step 3: Run, expect fail**

```
swift test --filter MCPClientTests
```

Expected: fails — `MCPClient` undefined.

- [ ] **Step 4: Implement**

`Sources/ScreenshotterCore/MCP/MCPClient.swift`:

```swift
import Foundation

public actor MCPClient {
    public let transport: MCPTransport
    private var nextId = 1

    public init(transport: MCPTransport) {
        self.transport = transport
    }

    /// Call a tool. Throws `JSONRPCError` on a failure response (including payment-required).
    /// The caller (PaymentClient) inspects the error and may retry with `extraHeaders` populated.
    public func callTool(
        name: String,
        arguments: [String: EIP712Value],
        extraHeaders: [String: String] = [:]
    ) async throws -> EIP712Value {
        let id = nextId; nextId += 1
        let req = JSONRPCRequest(
            id: .number(id),
            method: "tools/call",
            params: [
                "name": .string(name),
                "arguments": .object(arguments),
            ]
        )
        let resp = try await transport.send(request: req, extraHeaders: extraHeaders)
        switch resp.outcome {
        case .success(let v): return v
        case .failure(let err): throw err
        }
    }
}
```

- [ ] **Step 5: Run, expect pass**

```
swift test --filter MCPClientTests
```

Expected: both tests pass.

- [ ] **Step 6: Commit**

```
git add Sources/ScreenshotterCore/MCP/MCPClient.swift Tests/ScreenshotterCoreTests/Fixtures/MockMCPTransport.swift Tests/ScreenshotterCoreTests/MCPClientTests.swift
git commit -m "Add MCPClient with mock-tested callTool"
```

---

## Phase 4 — Payment

### Task 15: PaymentQuote parsing

**Files:**
- Create: `Sources/ScreenshotterCore/Payment/PaymentQuote.swift`
- Create: `Tests/ScreenshotterCoreTests/Fixtures/MPPQuoteSamples.swift`
- Create: `Tests/ScreenshotterCoreTests/PaymentQuoteTests.swift`

The exact schema is documented in `docs/superpowers/protocol/mpp-x402.md` (Task 3). This task assumes the schema includes at minimum: an EIP-712 typed-data block, a USD amount, and an asset identifier. **Replace the sample below with a real captured payload from Task 3 before running the test.**

- [ ] **Step 1: Add the fixture (placeholder real payload from Task 3 here)**

`Tests/ScreenshotterCoreTests/Fixtures/MPPQuoteSamples.swift`:

```swift
import Foundation

/// Replace this with a real captured 402 payload from mpp-remote (Task 3).
/// The shape below is illustrative — adjust to match the documented protocol.
enum MPPQuoteSamples {
    static let basicQuoteJSON = """
    {
      "amountUSD": "0.05",
      "asset": "USDC",
      "chainId": 84532,
      "typedData": {
        "types": {
          "EIP712Domain": [
            {"name":"name","type":"string"},
            {"name":"version","type":"string"},
            {"name":"chainId","type":"uint256"},
            {"name":"verifyingContract","type":"address"}
          ],
          "TransferWithAuthorization": [
            {"name":"from","type":"address"},
            {"name":"to","type":"address"},
            {"name":"value","type":"uint256"},
            {"name":"validAfter","type":"uint256"},
            {"name":"validBefore","type":"uint256"},
            {"name":"nonce","type":"bytes32"}
          ]
        },
        "primaryType": "TransferWithAuthorization",
        "domain": {
          "name": "USD Coin",
          "version": "2",
          "chainId": 84532,
          "verifyingContract": "0x036CbD53842c5426634e7929541eC2318f3dCF7e"
        },
        "message": {
          "from": "0x3E64B7838e791d5E2b766C7AFae5C3f2D57F9Cc7",
          "to": "0xc5F06701bd664159620F1a83A64A57ebCEF9151b",
          "value": "50000",
          "validAfter": "0",
          "validBefore": "9999999999",
          "nonce": "0x0000000000000000000000000000000000000000000000000000000000000001"
        }
      }
    }
    """
}
```

The schema above uses `TransferWithAuthorization` because that matched the data we observed in the failed upload (USDC contract, `transfer(address,uint256)` calldata, value `0xc350` = 50000 = 0.05 USDC with 6 decimals). **Confirm against Task 3's protocol notes before implementing.** If MPP uses `bytes32` for `nonce`, ensure the EIP-712 hasher (Task 9) handles it — `bytes32` encodes as the raw 32 bytes, not keccak'd.

- [ ] **Step 2: Extend EIP712 hasher to handle `bytes32`**

If Task 9's hasher doesn't yet handle `bytesN` (fixed-size byte arrays), add it.

In `EIP712.swift`, add a case in `encodeValue` before the `uint`/`int` block:

```swift
        if type.hasPrefix("bytes") && type != "bytes" {
            // Fixed-size bytesN (1..32). Encoded as the raw bytes, left-aligned and zero-padded.
            guard case .string(let hex) = value else { throw EIP712Error.unsupportedFieldType(type) }
            let raw = try Data(hexString: hex)
            // Right-pad to 32 (bytesN is left-aligned, so already-correct hex of length N right-pads with zeros)
            if raw.count >= 32 { return raw.prefix(32) }
            return raw + Data(count: 32 - raw.count)
        }
```

Also add a quick test in `EIP712Tests.swift` for `bytes32` encoding via a tiny typed-data fixture.

- [ ] **Step 3: Write the failing test**

`Tests/ScreenshotterCoreTests/PaymentQuoteTests.swift`:

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func paymentQuoteParsesAmount() throws {
    let data = MPPQuoteSamples.basicQuoteJSON.data(using: .utf8)!
    let quote = try JSONDecoder().decode(PaymentQuote.self, from: data)
    #expect(quote.amountUSD == 0.05)
    #expect(quote.asset == "USDC")
    #expect(quote.typedData.primaryType == "TransferWithAuthorization")
}

@Test func paymentQuoteHashesDigest() throws {
    let data = MPPQuoteSamples.basicQuoteJSON.data(using: .utf8)!
    let quote = try JSONDecoder().decode(PaymentQuote.self, from: data)
    let digest = try quote.typedData.encodedDigest()
    #expect(digest.count == 32)
}
```

- [ ] **Step 4: Run, expect fail**

```
swift test --filter PaymentQuoteTests
```

Expected: fails — `PaymentQuote` undefined.

- [ ] **Step 5: Implement**

`Sources/ScreenshotterCore/Payment/PaymentQuote.swift`:

```swift
import Foundation

public struct PaymentQuote: Codable {
    public let amountUSD: Decimal
    public let asset: String
    public let chainId: Int
    public let typedData: EIP712TypedData

    enum CodingKeys: String, CodingKey { case amountUSD, asset, chainId, typedData }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let amountString = try c.decode(String.self, forKey: .amountUSD)
        guard let amount = Decimal(string: amountString) else {
            throw DecodingError.dataCorruptedError(forKey: .amountUSD, in: c,
                debugDescription: "amountUSD must be numeric string")
        }
        self.amountUSD = amount
        self.asset = try c.decode(String.self, forKey: .asset)
        self.chainId = try c.decode(Int.self, forKey: .chainId)
        self.typedData = try c.decode(EIP712TypedData.self, forKey: .typedData)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(amountUSD.description, forKey: .amountUSD)
        try c.encode(asset, forKey: .asset)
        try c.encode(chainId, forKey: .chainId)
        try c.encode(typedData, forKey: .typedData)
    }
}
```

- [ ] **Step 6: Run, expect pass**

```
swift test --filter PaymentQuoteTests
```

Expected: both tests pass. If decoding fails because the actual MPP schema differs from the placeholder, **stop and revise the fixture and decoder to match the protocol notes from Task 3.**

- [ ] **Step 7: Commit**

```
git add Sources/ScreenshotterCore/Payment/PaymentQuote.swift Tests/ScreenshotterCoreTests/Fixtures/MPPQuoteSamples.swift Tests/ScreenshotterCoreTests/PaymentQuoteTests.swift
git commit -m "Add PaymentQuote parsing for MPP 402 challenge payloads"
```

---

### Task 16: PaymentError types

**Files:**
- Create: `Sources/ScreenshotterCore/Payment/PaymentError.swift`

- [ ] **Step 1: Implement**

`Sources/ScreenshotterCore/Payment/PaymentError.swift`:

```swift
import Foundation

public enum PaymentError: Error, Equatable {
    case capExceeded(quotedUSD: Decimal, capUSD: Decimal)
    case insufficientFunds(quotedUSDC: Decimal, haveUSDC: Decimal?, haveETH: Decimal?)
    case signatureFailed(String)
    case malformedQuote(String)
    case other(String)
}
```

- [ ] **Step 2: Verify build**

```
swift build
```

Expected: success.

- [ ] **Step 3: Commit**

```
git add Sources/ScreenshotterCore/Payment/PaymentError.swift
git commit -m "Add PaymentError typed errors for FundingPanel routing"
```

---

### Task 17: PaymentClient

**Files:**
- Create: `Sources/ScreenshotterCore/Payment/PaymentClient.swift`
- Create: `Tests/ScreenshotterCoreTests/PaymentClientTests.swift`

The PaymentClient takes a `JSONRPCError` (parsed from the 402 response by MCPClient), extracts the embedded `PaymentQuote`, validates the cap, signs the quote, and produces the payment header. **The exact header name and value format come from `docs/superpowers/protocol/mpp-x402.md` (Task 3).** The implementation below assumes header `X-PAYMENT` with value `0x` + 65-byte hex (r||s||v); update if the protocol notes specify otherwise.

- [ ] **Step 1: Write the failing test**

`Tests/ScreenshotterCoreTests/PaymentClientTests.swift`:

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func paymentClientSignsQuoteUnderCap() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let client = PaymentClient(wallet: wallet, capUSD: 0.50)

    let quoteData = MPPQuoteSamples.basicQuoteJSON.data(using: .utf8)!
    let quote = try JSONDecoder().decode(PaymentQuote.self, from: quoteData)

    let header = try client.signQuote(quote)
    #expect(header.name == "X-PAYMENT")
    #expect(header.value.hasPrefix("0x"))
    #expect(header.value.count == 2 + 65 * 2)  // 0x + 65 bytes hex
}

@Test func paymentClientRejectsOverCap() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let client = PaymentClient(wallet: wallet, capUSD: 0.01)

    let quoteData = MPPQuoteSamples.basicQuoteJSON.data(using: .utf8)!  // 0.05 USD
    let quote = try JSONDecoder().decode(PaymentQuote.self, from: quoteData)

    do {
        _ = try client.signQuote(quote)
        Issue.record("expected capExceeded")
    } catch PaymentError.capExceeded(let quoted, let cap) {
        #expect(quoted == 0.05)
        #expect(cap == 0.01)
    } catch {
        Issue.record("wrong error: \(error)")
    }
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter PaymentClientTests
```

Expected: fails — `PaymentClient` undefined.

- [ ] **Step 3: Implement**

`Sources/ScreenshotterCore/Payment/PaymentClient.swift`:

```swift
import Foundation

public struct PaymentHeader: Equatable {
    public let name: String
    public let value: String
}

public struct PaymentClient {
    public let wallet: Wallet
    public let capUSD: Decimal
    public let headerName: String

    public init(wallet: Wallet, capUSD: Decimal = Decimal(string: "0.50")!, headerName: String = "X-PAYMENT") {
        self.wallet = wallet
        self.capUSD = capUSD
        self.headerName = headerName
    }

    /// Sign a quote and return a payment header to attach on the retry.
    /// Verify the exact header value format against `docs/superpowers/protocol/mpp-x402.md`.
    public func signQuote(_ quote: PaymentQuote) throws -> PaymentHeader {
        guard quote.amountUSD <= capUSD else {
            throw PaymentError.capExceeded(quotedUSD: quote.amountUSD, capUSD: capUSD)
        }
        let sig: RecoverableSignature
        do {
            sig = try wallet.signEIP712(quote.typedData)
        } catch {
            throw PaymentError.signatureFailed("\(error)")
        }
        // Encode r || s || v as 0x-prefixed hex
        var raw = Data()
        raw.append(sig.r)
        raw.append(sig.s)
        raw.append(sig.v)
        return PaymentHeader(name: headerName, value: raw.hexEncodedString(prefix: true))
    }

    /// Extract a PaymentQuote from a JSON-RPC error (code -32042 or similar).
    public func extractQuote(from error: JSONRPCError) throws -> PaymentQuote {
        guard let data = error.data else {
            throw PaymentError.malformedQuote("missing data field in 402 response")
        }
        let asJSON = try JSONEncoder().encode(data)
        do {
            return try JSONDecoder().decode(PaymentQuote.self, from: asJSON)
        } catch {
            throw PaymentError.malformedQuote("\(error)")
        }
    }

    /// True if the given error indicates payment is required.
    /// Update the matcher to whatever Task 3's protocol notes specify.
    public func isPaymentRequired(_ error: JSONRPCError) -> Bool {
        error.code == -32042
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter PaymentClientTests
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/Payment/PaymentClient.swift Tests/ScreenshotterCoreTests/PaymentClientTests.swift
git commit -m "Add PaymentClient: signs MPP quotes under cap, produces payment header"
```

---

## Phase 5 — Uploader

### Task 18: Uploader façade

**Files:**
- Create: `Sources/ScreenshotterCore/Uploader/Uploader.swift`
- Create: `Tests/ScreenshotterCoreTests/UploaderTests.swift`

The Uploader composes MCPClient + PaymentClient. The flow:

1. Call `quick_upload` with no payment header.
2. On JSON-RPC error: check `isPaymentRequired`. If so, extract the quote, sign, retry once with the payment header.
3. On success, decode `share_url` from the result and return it.

- [ ] **Step 1: Write the failing test**

`Tests/ScreenshotterCoreTests/UploaderTests.swift`:

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test func uploaderPaysAndReturnsShareURL() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let payment = PaymentClient(wallet: wallet)
    let transport = MockMCPTransport()

    // First response: 402 with embedded quote
    let quoteJSON = MPPQuoteSamples.basicQuoteJSON
    let challengeJSON = """
    {"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required","data":\(quoteJSON)}}
    """
    // Second response: success with share_url
    let successJSON = #"{"jsonrpc":"2.0","id":2,"result":{"item_id":"abc","share_url":"https://stage-cloudup.com/s/abc"}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: challengeJSON.data(using: .utf8)!),
        try JSONDecoder().decode(JSONRPCResponse.self, from: successJSON.data(using: .utf8)!),
    ]

    let mcp = MCPClient(transport: transport)
    let uploader = Uploader(mcp: mcp, payment: payment)
    let url = try await uploader.upload(
        data: Data([0x89, 0x50, 0x4e, 0x47]),  // tiny "PNG"
        filename: "x.png",
        mime: "image/png"
    )
    #expect(url.absoluteString == "https://stage-cloudup.com/s/abc")
    #expect(transport.receivedRequests.count == 2)
    #expect(transport.receivedRequests[1].headers["X-PAYMENT"]?.hasPrefix("0x") == true)
}

@Test func uploaderSurfacesCapExceeded() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let payment = PaymentClient(wallet: wallet, capUSD: 0.01)  // too low for 0.05 quote
    let transport = MockMCPTransport()

    let quoteJSON = MPPQuoteSamples.basicQuoteJSON
    let challengeJSON = """
    {"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required","data":\(quoteJSON)}}
    """
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: challengeJSON.data(using: .utf8)!),
    ]

    let mcp = MCPClient(transport: transport)
    let uploader = Uploader(mcp: mcp, payment: payment)
    await #expect(throws: PaymentError.self) {
        _ = try await uploader.upload(data: Data(), filename: "x.png", mime: "image/png")
    }
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter UploaderTests
```

Expected: fails — `Uploader` undefined.

- [ ] **Step 3: Implement**

`Sources/ScreenshotterCore/Uploader/Uploader.swift`:

```swift
import Foundation

public struct Uploader {
    public let mcp: MCPClient
    public let payment: PaymentClient

    public init(mcp: MCPClient, payment: PaymentClient) {
        self.mcp = mcp
        self.payment = payment
    }

    /// Upload bytes to Cloudup via `quick_upload`. Handles the MPP/x402 payment dance.
    public func upload(data: Data, filename: String, mime: String) async throws -> URL {
        let args: [String: EIP712Value] = [
            "filename": .string(filename),
            "mime": .string(mime),
            "content_base64": .string(data.base64EncodedString()),
        ]
        do {
            let result = try await mcp.callTool(name: "quick_upload", arguments: args)
            return try extractShareURL(from: result)
        } catch let err as JSONRPCError where payment.isPaymentRequired(err) {
            let quote = try payment.extractQuote(from: err)
            let header = try payment.signQuote(quote)
            let result = try await mcp.callTool(
                name: "quick_upload",
                arguments: args,
                extraHeaders: [header.name: header.value]
            )
            return try extractShareURL(from: result)
        }
    }

    private func extractShareURL(from value: EIP712Value) throws -> URL {
        guard case .object(let obj) = value,
              case .string(let s) = obj["share_url"] ?? .null,
              let url = URL(string: s) else {
            throw PaymentError.other("response missing share_url")
        }
        return url
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter UploaderTests
```

Expected: both tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/Uploader/Uploader.swift Tests/ScreenshotterCoreTests/UploaderTests.swift
git commit -m "Add Uploader: composes MCP + Payment to deliver paid uploads"
```

---

### Task 19: CLI binary

**Files:**
- Create: `Sources/screenshotter-cli/main.swift`

- [ ] **Step 1: Write the CLI**

`Sources/screenshotter-cli/main.swift`:

```swift
import Foundation
import ScreenshotterCore

@main
struct CLI {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write("error: \(error)\n".data(using: .utf8)!)
            exit(1)
        }
    }

    static func run() async throws {
        let args = CommandLine.arguments
        guard args.count >= 3, args[1] == "upload" else {
            print("usage: screenshotter-cli upload <path>")
            print("       screenshotter-cli address")
            if args.count >= 2, args[1] == "address" {
                let wallet = try defaultWallet()
                print(wallet.address.hexString())
            }
            exit(args.count >= 2 && args[1] == "address" ? 0 : 2)
        }
        let path = args[2]
        let fileURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: fileURL)
        let filename = fileURL.lastPathComponent
        let mime = mimeType(for: fileURL.pathExtension)

        let wallet = try defaultWallet()
        let payment = PaymentClient(wallet: wallet)
        let endpoint = URL(string: ProcessInfo.processInfo.environment["MCP_ENDPOINT"]
            ?? "https://api.stage-cloudup.com/mcp/public")!
        let transport = StreamableHTTPTransport(endpoint: endpoint)
        let mcp = MCPClient(transport: transport)
        let uploader = Uploader(mcp: mcp, payment: payment)

        FileHandle.standardError.write("uploading \(filename) (\(data.count) bytes) from \(wallet.address.hexString())\n".data(using: .utf8)!)
        let url = try await uploader.upload(data: data, filename: filename, mime: mime)
        print(url.absoluteString)
    }

    static func defaultWallet() throws -> Wallet {
        try Wallet.loadOrCreate(
            keychain: MacOSKeychainStore(),
            service: "com.bongnam.screenshotter",
            account: "default"
        )
    }

    static func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }
}
```

- [ ] **Step 2: Build**

```
swift build
```

Expected: success. The CLI binary is at `.build/debug/screenshotter-cli`.

- [ ] **Step 3: Try `address` subcommand (no upload, just prints wallet address)**

```
swift run screenshotter-cli address
```

Expected: prints a 0x-prefixed Ethereum address. The first run may prompt for Keychain access — accept.

- [ ] **Step 4: Commit**

```
git add Sources/screenshotter-cli/main.swift
git commit -m "Add screenshotter-cli executable with upload and address subcommands"
```

---

## Phase 6 — End-to-end integration

### Task 20: Integration test against live Cloudup

**Files:**
- Create: `Tests/ScreenshotterCoreTests/UploaderIntegrationTests.swift`

- [ ] **Step 1: Write the test**

```swift
import Testing
import Foundation
@testable import ScreenshotterCore

@Test(.disabled(
    if: ProcessInfo.processInfo.environment["SCREENSHOTTER_INTEGRATION"] != "1"
       || ProcessInfo.processInfo.environment["SCREENSHOTTER_TEST_WALLET_KEY"] == nil,
    "Set SCREENSHOTTER_INTEGRATION=1 and SCREENSHOTTER_TEST_WALLET_KEY=0x... to run"
))
func integrationPaidUploadAgainstCloudupStage() async throws {
    let keyHex = ProcessInfo.processInfo.environment["SCREENSHOTTER_TEST_WALLET_KEY"]!
    let endpoint = URL(string: ProcessInfo.processInfo.environment["MCP_ENDPOINT"]
        ?? "https://api.stage-cloudup.com/mcp/public")!

    let priv = try Data(hexString: keyHex)
    let signer = try Secp256k1Signer(privateKey: priv)
    let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
    let wallet = TestWallet(address: address, signer: signer)
    let payment = PaymentClient(wallet: wallet)
    let mcp = MCPClient(transport: StreamableHTTPTransport(endpoint: endpoint))
    let uploader = Uploader(mcp: mcp, payment: payment)

    // Minimal valid PNG (1x1 transparent)
    let pngHex = "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da636400000000050001a5f645080000000049454e44ae426082"
    let png = try Data(hexString: pngHex)

    let url = try await uploader.upload(data: png, filename: "integration.png", mime: "image/png")
    #expect(url.absoluteString.contains("stage-cloudup.com"))
}

/// Wrapper used by the integration test: takes a private key from env var,
/// implements WalletProtocol without touching Keychain.
struct TestWallet: WalletProtocol {
    let address: EthereumAddress
    let signer: Secp256k1Signer
    func signEIP712(_ typedData: EIP712TypedData) throws -> RecoverableSignature {
        try signer.signRecoverable(digest: try typedData.encodedDigest())
    }
}
```

Hmm — to use a `TestWallet` we need `PaymentClient` to accept a protocol, not the concrete `Wallet`. Adjust:

- [ ] **Step 2: Refactor `Wallet` into a protocol + struct**

In `Sources/ScreenshotterCore/Wallet/Wallet.swift`, change:

```swift
public protocol WalletProtocol {
    var address: EthereumAddress { get }
    func signEIP712(_ typedData: EIP712TypedData) throws -> RecoverableSignature
}

public struct Wallet: WalletProtocol {
    public let address: EthereumAddress
    private let signer: Secp256k1Signer

    public init(address: EthereumAddress, signer: Secp256k1Signer) {
        self.address = address
        self.signer = signer
    }

    public static func loadOrCreate(
        keychain: KeychainStore,
        service: String,
        account: String
    ) throws -> Wallet {
        let privKey: Data
        if let existing = try keychain.read(account: account, service: service) {
            privKey = existing
        } else {
            let fresh = try Secp256k1Signer.generate()
            try keychain.write(fresh.privateKey, account: account, service: service)
            privKey = fresh.privateKey
        }
        let signer = try Secp256k1Signer(privateKey: privKey)
        let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
        return Wallet(address: address, signer: signer)
    }

    public func signEIP712(_ typedData: EIP712TypedData) throws -> RecoverableSignature {
        let digest = try typedData.encodedDigest()
        return try signer.signRecoverable(digest: digest)
    }
}
```

In `Sources/ScreenshotterCore/Payment/PaymentClient.swift`, change the property type from `Wallet` to `WalletProtocol`:

```swift
public struct PaymentClient {
    public let wallet: WalletProtocol
    public let capUSD: Decimal
    public let headerName: String

    public init(wallet: WalletProtocol, capUSD: Decimal = Decimal(string: "0.50")!, headerName: String = "X-PAYMENT") {
        self.wallet = wallet
        self.capUSD = capUSD
        self.headerName = headerName
    }
    // ...rest unchanged
}
```

Update the integration test's `TestWallet`:

```swift
struct TestWallet: WalletProtocol {
    let address: EthereumAddress
    let signer: Secp256k1Signer
    func signEIP712(_ typedData: EIP712TypedData) throws -> RecoverableSignature {
        try signer.signRecoverable(digest: try typedData.encodedDigest())
    }
}
```

- [ ] **Step 3: Run unit tests to confirm no regressions**

```
swift test
```

Expected: all unit tests still pass.

- [ ] **Step 4: Run the integration test (only if you have a funded test wallet)**

```
SCREENSHOTTER_INTEGRATION=1 \
SCREENSHOTTER_TEST_WALLET_KEY=0xYOUR_FUNDED_TESTNET_KEY \
swift test --filter UploaderIntegrationTests
```

Expected: the test passes and returns a Cloudup stage share URL.

If you don't yet have a funded test wallet:
- Run `swift run screenshotter-cli address` to get the CLI's wallet address.
- Fund it from a Base Sepolia faucet (Coinbase CDP or Circle), with at least 0.10 USDC + a tiny bit of ETH for gas.
- Run the CLI directly: `swift run screenshotter-cli upload some-file.png`. The CLI uses the same code paths as the integration test.

- [ ] **Step 5: Commit**

```
git add Sources/ScreenshotterCore/Wallet/Wallet.swift Sources/ScreenshotterCore/Payment/PaymentClient.swift Tests/ScreenshotterCoreTests/UploaderIntegrationTests.swift
git commit -m "Add gated integration test for paid upload against Cloudup stage"
```

---

### Task 21: Manual end-to-end verification

**Files:** none (verification only)

- [ ] **Step 1: Build the CLI**

```
swift build -c release
```

Expected: release binary at `.build/release/screenshotter-cli`.

- [ ] **Step 2: Get the wallet address**

```
.build/release/screenshotter-cli address
```

Expected: prints a 0x-prefixed Ethereum address.

- [ ] **Step 3: Fund the wallet**

Go to https://portal.cdp.coinbase.com/products/faucet (Base Sepolia network) and request both ETH and USDC for the address above. Wait ~30 seconds for confirmations.

- [ ] **Step 4: Upload a test image**

Create a tiny PNG (or any file) for testing:

```
# A trivial PNG; you can also use any existing image.
echo "test" > /tmp/screenshotter-test.txt
.build/release/screenshotter-cli upload /tmp/screenshotter-test.txt
```

Expected: prints a Cloudup share URL to stdout, e.g.:

```
uploading screenshotter-test.txt (5 bytes) from 0xabcd...
https://stage-cloudup.com/s/SOMESHORTCODE/SOMEITEM
```

- [ ] **Step 5: Verify the link works**

Open the printed URL in a browser. Verify the file is downloadable.

- [ ] **Step 6: Document in README**

Append to `README.md`:

```markdown
## Verified end-to-end

The CLI has been verified against Cloudup stage on Base Sepolia:
- Wallet generation + Keychain persistence: working.
- MPP/x402 payment signing: working (signs and pays via X-PAYMENT header).
- Upload + share URL retrieval: working.

See `docs/superpowers/protocol/mpp-x402.md` for the protocol notes used to
implement payment signing.
```

- [ ] **Step 7: Commit the README update**

```
git add README.md
git commit -m "Document verified end-to-end CLI upload flow"
```

---

## Spec coverage check

This plan implements the following components from the spec (`docs/superpowers/specs/2026-05-12-screenshotter-design.md`):

- `Wallet` — Tasks 4–10
- `MCPClient` — Tasks 11–14
- `PaymentClient` — Tasks 15–17
- `Uploader` — Task 18

The following spec components are **intentionally deferred to Plan 2** (the macOS app):
- `MenubarController`, `HotkeyManager`, `OnboardingCoordinator`, `CaptureCoordinator`, `CaptureService`, `AnnotationEditor`, `AnnotationModel`, `UndoStack`, `Renderer`, `ClipboardService`, `NotificationService`, `FundingPanel`
- Balance-query methods on `Wallet` (`balanceUSDC`, `balanceETH`) — needed only by `FundingPanel` in Plan 2.

The CLI built in Task 19 is itself outside the spec but is a useful demoable artifact that proves Plan 1 works end-to-end.

## Risks called out in the spec, addressed here

- **`PaymentClient` byte-correctness against the MPP reference.** Task 3 reads the reference and pins protocol details into a doc; Tasks 15–18 implement against those notes; Task 20 cross-validates by paying a real Cloudup stage upload. If the unit-tested signatures pass but the integration test fails, the gap is in `mpp-x402.md` — fix and re-run.
- **MCP Streamable HTTP transport correctness.** Tasks 11–14 cover JSON-RPC and SSE in isolation; Task 20's integration test exercises the live transport.

## What we punt to Plan 2

- App scaffolding (LSUIElement Info.plist, .app bundling script).
- ScreenCaptureKit integration.
- The annotation editor.
- The undo/redo command stack.
- Global hotkey + menubar UI.
- Onboarding window, funding panel, toast notifications.
- Balance RPC queries.

Plan 2 will build directly on top of the `ScreenshotterCore` library — `Uploader` is the single integration point.
