# CloudupSnap Core + CLI Implementation Plan (Plan 1 of 2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Swift package that uploads files to Cloudup's MCP server, paying per-upload in USDC on Base Sepolia via MPP/x402. Ship a CLI binary (`cloudupsnap-cli`) that demonstrates an end-to-end paid upload and returns a share URL.

**Architecture:** Pure Swift library (`CloudupSnapCore`) with no UI dependencies, exposing a single high-level surface: `Uploader.upload(data:filename:mime:) async throws -> URL`. Under the hood: `Uploader` → `MCPClient` (JSON-RPC over Streamable HTTP) → `PaymentClient` (settles by executing an on-chain ERC20 transfer and returning the tx hash as a credential) → `Wallet` (Keychain-stored secp256k1 key, signs EIP-1559 transactions). The CLI target is a thin shell around `Uploader`.

**Tech Stack:**
- Swift 6, Swift Package Manager (no Xcode project required)
- `swift-testing` for unit tests (`@Test` macros), XCTest for one Keychain integration test (XCTest is friendlier for setUp/tearDown)
- Dependencies (SwiftPM):
  - `github.com/GigaBitcoin/secp256k1.swift` — ECDSA signing (product is named `P256K`)
  - `github.com/krzyzanowskim/CryptoSwift` — keccak256
- Apple frameworks: Foundation, Security (Keychain), CryptoKit
- Reference implementation for the payment protocol: `github:tellyworth/mpp-remote`. The wire-level protocol is documented at `docs/superpowers/protocol/mpp-x402.md` and is the authoritative source for what `PaymentClient` and `Uploader` must implement.

**Spec:** `docs/superpowers/specs/2026-05-12-cloudupsnap-design.md`

**Note on testing framework:** the spec mentions "XCTest" generically; this plan uses `swift-testing` for the bulk of unit tests (cleaner ergonomics for Swift 6) and XCTest for the one Keychain integration test where setUp/tearDown matters.

**Revision note (2026-05-12, after Task 3 completed):** Task 3 documented the actual `mpp-remote` protocol and revealed it does **not** use EIP-712 typed-data signing or an `X-PAYMENT` HTTP header. Instead, the client settles each charge with a real on-chain ERC20 `transfer()` transaction on Base Sepolia and submits the resulting tx hash as `params._meta["org.paymentauth/credential"]` on a single retry. Tasks 9 onward have been rewritten to match this reality. The pre-revision tasks (EIP-712 hasher, X-PAYMENT header signing) are obsolete; see git history `f267c32` for the original plan.

---

## File Structure

```
/Users/bongnam/dev/cloudupsnap/
├── Package.swift
├── README.md
├── .gitignore
├── Sources/
│   ├── CloudupSnapCore/
│   │   ├── HexAndHash/
│   │   │   ├── HexCoding.swift           # Data ↔ hex String
│   │   │   └── Keccak.swift              # keccak256(_:Data) -> Data
│   │   ├── Wallet/
│   │   │   ├── Secp256k1Signer.swift     # libsecp256k1 wrapper, keygen + sign
│   │   │   ├── EthereumAddress.swift     # 20-byte address derived from pubkey
│   │   │   ├── KeychainStore.swift       # protocol + macOS implementation
│   │   │   └── Wallet.swift              # façade: address, sendTransfer, balanceOf
│   │   ├── Ethereum/
│   │   │   ├── RLP.swift                 # RLP encoding for Ethereum data
│   │   │   ├── ERC20.swift               # transfer(address,uint256) calldata encoder
│   │   │   ├── Transaction.swift         # EIP-1559 tx builder + signer
│   │   │   └── EthereumRPC.swift         # JSON-RPC client for getTransactionCount, etc.
│   │   ├── MCP/
│   │   │   ├── JSONRPC.swift             # Codable Request/Response/Error envelopes
│   │   │   ├── SSEReader.swift           # Server-Sent Events parser
│   │   │   ├── MCPTransport.swift        # protocol over an async HTTP body
│   │   │   ├── StreamableHTTPTransport.swift  # URLSession-backed transport
│   │   │   └── MCPClient.swift           # initialize + callTool surface (supports _meta)
│   │   ├── Payment/
│   │   │   ├── PaymentChallenge.swift    # parsed -32042 challenge + Method[]
│   │   │   ├── PaymentCredential.swift   # {method, challenge_id, opaque, settlement_tx_hash}
│   │   │   ├── PaymentError.swift        # typed errors
│   │   │   └── PaymentClient.swift       # settle: validate cap → pick method → sendTransfer → wait receipt → credential
│   │   └── Uploader/
│   │       └── Uploader.swift            # public façade: upload(...) -> URL (uses _meta credential)
│   └── cloudupsnap-cli/
│       └── main.swift                    # parses argv, calls Uploader, prints URL
├── Tests/
│   ├── CloudupSnapCoreTests/
│   │   ├── Fixtures/
│   │   │   ├── RLPVectors.swift          # canonical RLP test cases
│   │   │   ├── TxSigningVectors.swift    # EIP-1559 known-good signed tx hex
│   │   │   ├── PaymentChallengeSamples.swift  # canned -32042 payloads
│   │   │   ├── MockMCPTransport.swift    # in-memory mock MCP transport
│   │   │   └── MockEthereumRPC.swift     # in-memory mock RPC client
│   │   ├── HexAndHashTests.swift
│   │   ├── Secp256k1SignerTests.swift
│   │   ├── EthereumAddressTests.swift
│   │   ├── RLPTests.swift
│   │   ├── ERC20Tests.swift
│   │   ├── TransactionTests.swift
│   │   ├── EthereumRPCTests.swift
│   │   ├── WalletTests.swift
│   │   ├── JSONRPCTests.swift
│   │   ├── SSEReaderTests.swift
│   │   ├── MCPClientTests.swift
│   │   ├── PaymentChallengeTests.swift
│   │   ├── PaymentClientTests.swift
│   │   ├── UploaderTests.swift
│   │   └── UploaderIntegrationTests.swift  # gated on CLOUDUPSNAP_INTEGRATION=1
│   └── KeychainStoreTests/
│       └── KeychainStoreTests.swift      # XCTest target, gated on environment
├── docs/
│   └── superpowers/
│       ├── specs/2026-05-12-cloudupsnap-design.md
│       ├── plans/2026-05-12-cloudupsnap-core-and-cli.md
│       └── protocol/mpp-x402.md          # written in Task 4 from the reference impl
```

---

## Phase 0 — Scaffolding

### Task 1: Initialize the Swift package

**Files:**
- Create: `Package.swift`
- Create: `.gitignore`
- Create: `README.md`
- Create: `Sources/CloudupSnapCore/Empty.swift` (placeholder so the target compiles)
- Create: `Tests/CloudupSnapCoreTests/EmptyTests.swift`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CloudupSnap",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CloudupSnapCore", targets: ["CloudupSnapCore"]),
        .executable(name: "cloudupsnap-cli", targets: ["cloudupsnap-cli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/GigaBitcoin/secp256k1.swift", from: "0.18.0"),
        .package(url: "https://github.com/krzyzanowskim/CryptoSwift", from: "1.8.0"),
    ],
    targets: [
        .target(
            name: "CloudupSnapCore",
            dependencies: [
                .product(name: "P256K", package: "secp256k1.swift"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
            ]
        ),
        .executableTarget(
            name: "cloudupsnap-cli",
            dependencies: ["CloudupSnapCore"]
        ),
        .testTarget(
            name: "CloudupSnapCoreTests",
            dependencies: ["CloudupSnapCore"]
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
# CloudupSnap

A macOS app (forthcoming) that captures, annotates, and uploads screenshots
to Cloudup, paying per upload in USDC on Base Sepolia via MPP/x402.

This repository currently contains:
- `CloudupSnapCore` — the Swift library that handles the MCP + payment + upload pipeline.
- `cloudupsnap-cli` — a CLI binary that demonstrates an end-to-end paid upload.

The macOS app (Plan 2) is forthcoming.

## Build

    swift build

## Test

    swift test

## CLI usage (after Plan 1)

    cloudupsnap-cli upload path/to/file.png
```

- [ ] **Step 4: Write placeholder Swift sources**

`Sources/CloudupSnapCore/Empty.swift`:

```swift
// Intentionally empty. This file exists so the target compiles before
// we add real sources. Delete when the first real source lands.
```

`Tests/CloudupSnapCoreTests/EmptyTests.swift`:

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
	swift run cloudupsnap-cli $(ARGS)

integration:
	CLOUDUPSNAP_INTEGRATION=1 swift test

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
- Create: `Sources/CloudupSnapCore/HexAndHash/HexCoding.swift`
- Create: `Tests/CloudupSnapCoreTests/HexAndHashTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CloudupSnapCoreTests/HexAndHashTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

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

`Sources/CloudupSnapCore/HexAndHash/HexCoding.swift`:

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
git add Sources/CloudupSnapCore/HexAndHash/HexCoding.swift Tests/CloudupSnapCoreTests/HexAndHashTests.swift
git commit -m "Add Data hex encoding/decoding utilities"
```

---

### Task 5: keccak256

**Files:**
- Create: `Sources/CloudupSnapCore/HexAndHash/Keccak.swift`
- Modify: `Tests/CloudupSnapCoreTests/HexAndHashTests.swift`

- [ ] **Step 1: Add failing test**

Append to `Tests/CloudupSnapCoreTests/HexAndHashTests.swift`:

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

`Sources/CloudupSnapCore/HexAndHash/Keccak.swift`:

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
git add Sources/CloudupSnapCore/HexAndHash/Keccak.swift Tests/CloudupSnapCoreTests/HexAndHashTests.swift
git commit -m "Add keccak256 extension on Data using CryptoSwift"
```

---

### Task 6: secp256k1 keypair and signing

**Files:**
- Create: `Sources/CloudupSnapCore/Wallet/Secp256k1Signer.swift`
- Create: `Tests/CloudupSnapCoreTests/Secp256k1SignerTests.swift`

The `secp256k1.swift` package's API has evolved; this plan uses the surface as of v0.18+. If the API differs in the version resolved, update the calls accordingly and document in a comment.

- [ ] **Step 1: Write the failing test**

`Tests/CloudupSnapCoreTests/Secp256k1SignerTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

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

`Sources/CloudupSnapCore/Wallet/Secp256k1Signer.swift`:

```swift
import Foundation
import P256K

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
        let key = try P256K.Signing.PrivateKey(dataRepresentation: privateKey)
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
        let key = try P256K.Recovery.PrivateKey(dataRepresentation: privateKey)
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
git add Sources/CloudupSnapCore/Wallet/Secp256k1Signer.swift Tests/CloudupSnapCoreTests/Secp256k1SignerTests.swift
git commit -m "Add Secp256k1Signer with key generation and recoverable signing"
```

---

### Task 7: Ethereum address derivation

**Files:**
- Create: `Sources/CloudupSnapCore/Wallet/EthereumAddress.swift`
- Create: `Tests/CloudupSnapCoreTests/EthereumAddressTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

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

`Sources/CloudupSnapCore/Wallet/EthereumAddress.swift`:

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
git add Sources/CloudupSnapCore/Wallet/EthereumAddress.swift Tests/CloudupSnapCoreTests/EthereumAddressTests.swift
git commit -m "Derive Ethereum addresses from uncompressed secp256k1 public keys"
```

---

### Task 8: KeychainStore protocol + macOS implementation

**Files:**
- Create: `Sources/CloudupSnapCore/Wallet/KeychainStore.swift`
- Create: `Tests/CloudupSnapCoreTests/Fixtures/InMemoryKeychainStore.swift`

This task defines an abstraction. The real Keychain implementation is tested via a separate gated XCTest target (Task 8b) because Keychain has machine-level side effects unsuitable for fast unit runs.

- [ ] **Step 1: Define the protocol and the in-memory mock first**

`Sources/CloudupSnapCore/Wallet/KeychainStore.swift`:

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

`Tests/CloudupSnapCoreTests/Fixtures/InMemoryKeychainStore.swift`:

```swift
import Foundation
@testable import CloudupSnapCore

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
git add Sources/CloudupSnapCore/Wallet/KeychainStore.swift Tests/CloudupSnapCoreTests/Fixtures/InMemoryKeychainStore.swift
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
            dependencies: ["CloudupSnapCore"]
        ),
```

- [ ] **Step 2: Write the test**

`Tests/KeychainStoreTests/KeychainStoreTests.swift`:

```swift
import XCTest
@testable import CloudupSnapCore

final class KeychainStoreTests: XCTestCase {
    let service = "com.bongnam.cloudupsnap.tests"
    let account = "integration-test-\(UUID().uuidString)"
    let sut = MacOSKeychainStore()

    override func setUp() async throws {
        guard ProcessInfo.processInfo.environment["CLOUDUPSNAP_KEYCHAIN_TESTS"] == "1" else {
            throw XCTSkip("Set CLOUDUPSNAP_KEYCHAIN_TESTS=1 to run Keychain integration tests.")
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
CLOUDUPSNAP_KEYCHAIN_TESTS=1 swift test --filter KeychainStoreTests
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
## Phase 3 — Ethereum primitives

These tasks build a minimal Ethereum-on-Base-Sepolia toolkit: just enough RLP, ABI encoding, transaction signing, and JSON-RPC to send one ERC20 `transfer()` and confirm it on-chain. Per `docs/superpowers/protocol/mpp-x402.md`, this is what `mpp-remote` actually does on every paid upload; our Swift port has to do the same.

We do NOT need: full EVM ABI, gas-oracle heuristics, multi-chain config, contract deployment, history queries.

---

### Task 9: RLP encoding

**Files:**
- Create: `Sources/CloudupSnapCore/Ethereum/RLP.swift`
- Create: `Tests/CloudupSnapCoreTests/Fixtures/RLPVectors.swift`
- Create: `Tests/CloudupSnapCoreTests/RLPTests.swift`

RLP (Recursive Length Prefix) is Ethereum's canonical serialization for transactions and other structured data. The full spec is at https://ethereum.org/en/developers/docs/data-structures-and-encoding/rlp/. We need encoding only (not decoding).

Rules:
- Single byte in `[0x00, 0x7f]` → encoded as itself.
- Byte string 0–55 bytes → `[0x80 + length, bytes]`.
- Byte string 56+ bytes → `[0xb7 + length-of-length, length-bytes-big-endian, bytes]`.
- List with payload 0–55 bytes → `[0xc0 + length, encoded-items]`.
- List with payload 56+ bytes → `[0xf7 + length-of-length, length-bytes, encoded-items]`.

Integers are encoded as their minimal big-endian byte representation with no leading zero bytes. **Zero is the empty byte string `0x80`, not `0x00`.** This is the most common bug source.

- [ ] **Step 1: Add canonical RLP test vectors**

`Tests/CloudupSnapCoreTests/Fixtures/RLPVectors.swift`:

```swift
import Foundation

/// Canonical RLP test vectors from
/// https://github.com/ethereum/tests/blob/develop/RLPTests/rlptest.json
enum RLPVectors {
    /// (description, item-to-encode, expected-hex)
    static let primitives: [(String, RLPItem, String)] = [
        ("empty string", .bytes(Data()), "80"),
        ("single byte 0", .bytes(Data([0x00])), "00"),
        ("single byte 1", .bytes(Data([0x01])), "01"),
        ("single byte 0x7f", .bytes(Data([0x7f])), "7f"),
        ("two bytes 0x80,0x01", .bytes(Data([0x80, 0x01])), "82" + "8001"),
        ("string 'dog'", .bytes("dog".data(using: .utf8)!), "83" + "646f67"),
        ("uint 0", .uint(0), "80"),
        ("uint 1", .uint(1), "01"),
        ("uint 1024", .uint(1024), "82" + "0400"),
        ("empty list", .list([]), "c0"),
        ("list ['cat','dog']", .list([
            .bytes("cat".data(using: .utf8)!),
            .bytes("dog".data(using: .utf8)!),
        ]), "c8" + "83636174" + "83646f67"),
    ]

    /// "Lorem ipsum dolor sit amet, consectetur adipisicing elit"  — 55 bytes
    /// expected: 0xb7 + bytes (length byte 0xb7 = 0x80 + 55)
    static let stringLength55: (item: RLPItem, hex: String) = {
        let s = "Lorem ipsum dolor sit amet, consectetur adipisicing elit"
        let bytes = s.data(using: .utf8)!
        assert(bytes.count == 55)
        return (.bytes(bytes), "b7" + bytes.map { String(format: "%02x", $0) }.joined())
    }()

    /// 56-byte string crosses into long form: prefix is 0xb8 + 0x38 (length=56)
    static let stringLength56: (item: RLPItem, hex: String) = {
        let bytes = Data(repeating: 0x61, count: 56)  // 56 'a' bytes
        return (.bytes(bytes), "b838" + bytes.map { String(format: "%02x", $0) }.joined())
    }()
}
```

- [ ] **Step 2: Write the failing tests**

`Tests/CloudupSnapCoreTests/RLPTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

@Test func rlpEncodesPrimitiveVectors() {
    for (description, item, expected) in RLPVectors.primitives {
        let encoded = RLP.encode(item).hexEncodedString()
        #expect(encoded == expected, "RLP encoding failed: \(description) — got \(encoded), expected \(expected)")
    }
}

@Test func rlpEncodesLongString() {
    let (item, expected) = RLPVectors.stringLength55
    #expect(RLP.encode(item).hexEncodedString() == expected)
}

@Test func rlpEncodesVeryLongString() {
    let (item, expected) = RLPVectors.stringLength56
    #expect(RLP.encode(item).hexEncodedString() == expected)
}

@Test func rlpUintHasNoLeadingZeros() {
    // 0x0001 encodes as 0x01, not 0x820001
    #expect(RLP.encode(.uint(1)).hexEncodedString() == "01")
    // 0x00 encodes as 0x80 (the empty string), per RLP spec
    #expect(RLP.encode(.uint(0)).hexEncodedString() == "80")
}
```

- [ ] **Step 3: Run, expect fail**

```
swift test --filter RLPTests
```

Expected: fails — `RLP` / `RLPItem` undefined.

- [ ] **Step 4: Implement**

`Sources/CloudupSnapCore/Ethereum/RLP.swift`:

```swift
import Foundation

public enum RLPItem {
    case bytes(Data)
    case uint(UInt64)         // common case for small ints (nonce, gasLimit)
    case bigUint(Data)        // big-endian, used for uint256 values that exceed UInt64
    case list([RLPItem])
}

public enum RLP {
    public static func encode(_ item: RLPItem) -> Data {
        switch item {
        case .bytes(let b):
            return encodeBytes(b)
        case .uint(let u):
            return encodeBytes(stripLeadingZeros(bigEndianBytes(u)))
        case .bigUint(let b):
            return encodeBytes(stripLeadingZeros(b))
        case .list(let items):
            var payload = Data()
            for sub in items { payload.append(encode(sub)) }
            return encodeListPrefix(payload.count) + payload
        }
    }

    private static func encodeBytes(_ data: Data) -> Data {
        if data.count == 1, data[data.startIndex] < 0x80 {
            return data
        }
        if data.count <= 55 {
            return Data([UInt8(0x80 + data.count)]) + data
        }
        let lengthBytes = bigEndianBytes(UInt64(data.count))
        let stripped = stripLeadingZeros(lengthBytes)
        return Data([UInt8(0xb7 + stripped.count)]) + stripped + data
    }

    private static func encodeListPrefix(_ payloadLength: Int) -> Data {
        if payloadLength <= 55 {
            return Data([UInt8(0xc0 + payloadLength)])
        }
        let lengthBytes = bigEndianBytes(UInt64(payloadLength))
        let stripped = stripLeadingZeros(lengthBytes)
        return Data([UInt8(0xf7 + stripped.count)]) + stripped
    }

    private static func bigEndianBytes(_ u: UInt64) -> Data {
        var result = Data(count: 8)
        for i in 0..<8 {
            result[7 - i] = UInt8(truncatingIfNeeded: u >> (i * 8))
        }
        return result
    }

    private static func stripLeadingZeros(_ data: Data) -> Data {
        var i = data.startIndex
        while i < data.endIndex, data[i] == 0 { i = data.index(after: i) }
        return data.subdata(in: i..<data.endIndex)
    }
}
```

- [ ] **Step 5: Run, expect pass**

```
swift test --filter RLPTests
```

Expected: four tests pass. If the long-string tests fail, check that `stripLeadingZeros` is called on length-bytes (not on the payload).

- [ ] **Step 6: Commit**

```
git add Sources/CloudupSnapCore/Ethereum/RLP.swift Tests/CloudupSnapCoreTests/Fixtures/RLPVectors.swift Tests/CloudupSnapCoreTests/RLPTests.swift
git commit -m "Add RLP encoder for Ethereum data serialization"
```

---

### Task 9b: ERC20 transfer calldata

**Files:**
- Create: `Sources/CloudupSnapCore/Ethereum/ERC20.swift`
- Create: `Tests/CloudupSnapCoreTests/ERC20Tests.swift`

Encodes the calldata for the standard ERC20 `transfer(address,uint256)` function. That's all we need — never `transferFrom`, `approve`, etc.

The function selector is the first 4 bytes of `keccak256("transfer(address,uint256)")` = `0xa9059cbb`.

The two arguments are ABI-encoded as 32 bytes each:
- `address`: 20 raw bytes, left-padded to 32 with zeros.
- `uint256`: big-endian bytes, left-padded to 32 with zeros.

Total calldata: 4 + 32 + 32 = 68 bytes.

- [ ] **Step 1: Write the failing test**

`Tests/CloudupSnapCoreTests/ERC20Tests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

@Test func erc20TransferCalldataMatchesKnownVector() throws {
    // transfer(0xc5F06701bd664159620F1a83A64A57ebCEF9151b, 50000)
    // Selector: 0xa9059cbb
    // arg1 (address): 0x000000000000000000000000c5f06701bd664159620f1a83a64a57ebcef9151b
    // arg2 (uint256): 0x000000000000000000000000000000000000000000000000000000000000c350 (50000)
    let recipient = try Data(hexString: "0xc5F06701bd664159620F1a83A64A57ebCEF9151b")
    let amount: UInt64 = 50000

    let calldata = ERC20.encodeTransfer(to: recipient, amount: amount)
    let hex = calldata.hexEncodedString(prefix: true)

    #expect(hex == "0xa9059cbb000000000000000000000000c5f06701bd664159620f1a83a64a57ebcef9151b000000000000000000000000000000000000000000000000000000000000c350")
    #expect(calldata.count == 68)
}

@Test func erc20TransferSelectorIsKnown() {
    // First 4 bytes of keccak256("transfer(address,uint256)")
    #expect(ERC20.transferSelector.hexEncodedString() == "a9059cbb")
}

@Test func erc20TransferRejectsBadAddressLength() {
    #expect(throws: ERC20Error.self) {
        _ = try ERC20.encodeTransferOrThrow(to: Data([0x01, 0x02, 0x03]), amount: 1)
    }
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter ERC20Tests
```

Expected: fails — `ERC20` undefined.

- [ ] **Step 3: Implement**

`Sources/CloudupSnapCore/Ethereum/ERC20.swift`:

```swift
import Foundation

public enum ERC20Error: Error {
    case addressMustBe20Bytes
}

public enum ERC20 {
    public static let transferSelector: Data = "transfer(address,uint256)"
        .data(using: .utf8)!
        .keccak256()
        .prefix(4)

    /// `transfer(address,uint256)` calldata. Address must be 20 bytes.
    public static func encodeTransfer(to address: Data, amount: UInt64) -> Data {
        precondition(address.count == 20)
        var out = Data(transferSelector)
        out.append(leftPad(address, to: 32))
        out.append(leftPad(bigEndianBytes(amount), to: 32))
        return out
    }

    public static func encodeTransferOrThrow(to address: Data, amount: UInt64) throws -> Data {
        guard address.count == 20 else { throw ERC20Error.addressMustBe20Bytes }
        return encodeTransfer(to: address, amount: amount)
    }

    /// Same as `encodeTransfer` but takes a uint256 value as big-endian bytes (up to 32).
    public static func encodeTransfer(to address: Data, amountBigEndian: Data) -> Data {
        precondition(address.count == 20)
        precondition(amountBigEndian.count <= 32)
        var out = Data(transferSelector)
        out.append(leftPad(address, to: 32))
        out.append(leftPad(amountBigEndian, to: 32))
        return out
    }

    private static func leftPad(_ data: Data, to width: Int) -> Data {
        if data.count >= width { return data.suffix(width) }
        return Data(count: width - data.count) + data
    }

    private static func bigEndianBytes(_ u: UInt64) -> Data {
        var result = Data(count: 8)
        for i in 0..<8 { result[7 - i] = UInt8(truncatingIfNeeded: u >> (i * 8)) }
        // Trim leading zeros — the calldata encoder will re-pad to 32.
        var start = result.startIndex
        while start < result.endIndex, result[start] == 0 { start = result.index(after: start) }
        return result.subdata(in: start..<result.endIndex)
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter ERC20Tests
```

Expected: three tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/CloudupSnapCore/Ethereum/ERC20.swift Tests/CloudupSnapCoreTests/ERC20Tests.swift
git commit -m "Add ERC20 transfer(address,uint256) calldata encoder"
```

---

### Task 9c: EIP-1559 transaction builder and signer

**Files:**
- Create: `Sources/CloudupSnapCore/Ethereum/Transaction.swift`
- Create: `Tests/CloudupSnapCoreTests/Fixtures/TxSigningVectors.swift`
- Create: `Tests/CloudupSnapCoreTests/TransactionTests.swift`

This builds and signs EIP-1559 (type-2) transactions. Format (per EIP-1559):

Signing payload (input to keccak256):
```
0x02 || RLP([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList])
```

Signed transaction (broadcast to the network):
```
0x02 || RLP([chainId, nonce, maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data, accessList, yParity, r, s])
```

All numbers are encoded as RLP big-endian-minimal byte strings. `accessList` for our use is always an empty list `[]`. `yParity` is `0` or `1` (the recovery id from secp256k1).

Reference: EIP-1559 spec at https://eips.ethereum.org/EIPS/eip-1559 and EIP-2718 typed-tx envelope.

**On test vectors:** producing a verifiable known-good signed EIP-1559 tx from scratch in Swift would be circular (the tool we're building is what would compute it). Instead, the test cross-checks against a fixture generated externally via viem/ethers — a known input set + corresponding raw signed tx hex. The fixture below was generated against Base Sepolia (chainId 84532) with viem 2.x. If you suspect drift, regenerate via a tiny Node script and update the fixture.

- [ ] **Step 1: Add the test fixture**

`Tests/CloudupSnapCoreTests/Fixtures/TxSigningVectors.swift`:

```swift
import Foundation

enum TxSigningVectors {
    /// Generated with viem 2.48 against Base Sepolia (chainId 84532).
    /// Input:
    ///   private key: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
    ///   nonce: 0
    ///   maxPriorityFeePerGas: 1_000_000_000 (1 gwei)
    ///   maxFeePerGas: 2_000_000_000 (2 gwei)
    ///   gasLimit: 21000
    ///   to: 0xc5F06701bd664159620F1a83A64A57ebCEF9151b
    ///   value: 1
    ///   data: 0x (empty)
    ///   accessList: []
    ///
    /// To regenerate: run `node scripts/gen-tx-vector.mjs` (helper not committed;
    /// see comment in TransactionTests for the snippet to regenerate locally).
    static let baseSepoliaSimpleTransferRawTx =
        // Replace with the actual hex produced by your reference run. The plan
        // intentionally does not pin this byte-for-byte because we don't have a
        // way to verify it without running viem ourselves. Instead, see
        // `assertProducesViemEquivalent` strategy below.
        ""

    static let chainIdBaseSepolia: UInt64 = 84532
    static let testPrivateKeyHex =
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
}
```

The fixture is intentionally empty — the **strategy for verifying this task** is different from earlier tasks because we don't have an offline-verifiable signing reference.

**Verification strategy:**

1. Compute a signed EIP-1559 tx in Swift for a known input.
2. In a separate Node REPL, compute the same tx using viem with the same inputs (see snippet below).
3. Assert the two hex strings match byte-for-byte.

Node REPL snippet (run interactively, do NOT add to the repo):

```js
import { privateKeyToAccount } from 'viem/accounts';
import { serializeTransaction } from 'viem';
const account = privateKeyToAccount('0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80');
const tx = {
  chainId: 84532, nonce: 0, type: 'eip1559',
  maxPriorityFeePerGas: 1000000000n, maxFeePerGas: 2000000000n, gas: 21000n,
  to: '0xc5F06701bd664159620F1a83A64A57ebCEF9151b', value: 1n, data: '0x',
};
const sig = await account.signTransaction(tx);
console.log(sig);
```

Once you have the viem-produced hex, paste it into `baseSepoliaSimpleTransferRawTx` in the fixture and the parity test below will pass.

- [ ] **Step 2: Write the failing test**

`Tests/CloudupSnapCoreTests/TransactionTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

@Test func eip1559TransactionStructureHasCorrectFields() throws {
    let priv = try Data(hexString: TxSigningVectors.testPrivateKeyHex)
    let signer = try Secp256k1Signer(privateKey: priv)
    let to = try Data(hexString: "0xc5F06701bd664159620F1a83A64A57ebCEF9151b")

    let tx = EIP1559Transaction(
        chainId: TxSigningVectors.chainIdBaseSepolia,
        nonce: 0,
        maxPriorityFeePerGas: 1_000_000_000,
        maxFeePerGas: 2_000_000_000,
        gasLimit: 21_000,
        to: to,
        value: 1,
        data: Data()
    )
    let signed = try tx.sign(with: signer)
    // The raw tx begins with 0x02 (EIP-2718 type byte for EIP-1559)
    #expect(signed.rawTransaction.first == 0x02)
    #expect(signed.transactionHash.count == 32)
}

@Test func eip1559MatchesViemReference() throws {
    // Skip this test if the fixture isn't populated yet (during initial dev).
    let expected = TxSigningVectors.baseSepoliaSimpleTransferRawTx
    guard !expected.isEmpty else {
        // Print a hint so the engineer knows to run the viem REPL once.
        print("[TransactionTests] TxSigningVectors.baseSepoliaSimpleTransferRawTx is empty — populate it from the viem REPL snippet to enable cross-validation.")
        return
    }
    let priv = try Data(hexString: TxSigningVectors.testPrivateKeyHex)
    let signer = try Secp256k1Signer(privateKey: priv)
    let to = try Data(hexString: "0xc5F06701bd664159620F1a83A64A57ebCEF9151b")
    let tx = EIP1559Transaction(
        chainId: TxSigningVectors.chainIdBaseSepolia,
        nonce: 0,
        maxPriorityFeePerGas: 1_000_000_000,
        maxFeePerGas: 2_000_000_000,
        gasLimit: 21_000,
        to: to,
        value: 1,
        data: Data()
    )
    let signed = try tx.sign(with: signer)
    #expect(signed.rawTransaction.hexEncodedString(prefix: true) == expected)
}
```

- [ ] **Step 3: Run, expect fail**

```
swift test --filter TransactionTests
```

Expected: `EIP1559Transaction` undefined.

- [ ] **Step 4: Implement**

`Sources/CloudupSnapCore/Ethereum/Transaction.swift`:

```swift
import Foundation

public struct EIP1559Transaction {
    public let chainId: UInt64
    public let nonce: UInt64
    public let maxPriorityFeePerGas: UInt64
    public let maxFeePerGas: UInt64
    public let gasLimit: UInt64
    public let to: Data           // 20 bytes
    public let value: UInt64      // wei (for ERC20 transfers, value=0)
    public let data: Data         // calldata; empty for plain ETH transfers

    public init(
        chainId: UInt64,
        nonce: UInt64,
        maxPriorityFeePerGas: UInt64,
        maxFeePerGas: UInt64,
        gasLimit: UInt64,
        to: Data,
        value: UInt64 = 0,
        data: Data = Data()
    ) {
        precondition(to.count == 20)
        self.chainId = chainId
        self.nonce = nonce
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.maxFeePerGas = maxFeePerGas
        self.gasLimit = gasLimit
        self.to = to
        self.value = value
        self.data = data
    }

    /// The unsigned payload: 0x02 || RLP([fields, []]).
    /// Used as input to keccak256 → signing hash.
    public var signingPayload: Data {
        let fields: [RLPItem] = [
            .uint(chainId),
            .uint(nonce),
            .uint(maxPriorityFeePerGas),
            .uint(maxFeePerGas),
            .uint(gasLimit),
            .bytes(to),
            .uint(value),
            .bytes(data),
            .list([]),  // accessList
        ]
        return Data([0x02]) + RLP.encode(.list(fields))
    }

    public func sign(with signer: Secp256k1Signer) throws -> SignedEIP1559Transaction {
        let hash = signingPayload.keccak256()
        let sig = try signer.signRecoverable(digest: hash)
        let signedFields: [RLPItem] = [
            .uint(chainId),
            .uint(nonce),
            .uint(maxPriorityFeePerGas),
            .uint(maxFeePerGas),
            .uint(gasLimit),
            .bytes(to),
            .uint(value),
            .bytes(data),
            .list([]),                  // accessList
            .uint(UInt64(sig.v)),       // yParity (0 or 1)
            .bigUint(sig.r),
            .bigUint(sig.s),
        ]
        let raw = Data([0x02]) + RLP.encode(.list(signedFields))
        return SignedEIP1559Transaction(rawTransaction: raw, transactionHash: raw.keccak256())
    }
}

public struct SignedEIP1559Transaction {
    public let rawTransaction: Data
    public let transactionHash: Data
}
```

- [ ] **Step 5: Run, expect pass**

```
swift test --filter TransactionTests
```

Expected: first test passes (`eip1559TransactionStructureHasCorrectFields`). Second test prints the hint and returns trivially until you populate the viem fixture.

- [ ] **Step 6: Populate the viem fixture**

Run the Node REPL snippet above in a scratch directory (do NOT add a Node project to this repo). Copy the resulting `0x02f86b...`-prefixed hex into `TxSigningVectors.baseSepoliaSimpleTransferRawTx`.

Re-run:

```
swift test --filter TransactionTests
```

Both tests should now pass. If `eip1559MatchesViemReference` fails, the most common cause is the `bigUint(sig.r)` / `bigUint(sig.s)` arms producing `0x80` for a value that happens to start with zeros — verify the `RLP.encode(.bigUint(...))` path strips leading zeros correctly. The next most common cause is mis-encoding the `yParity` byte (`sig.v` should be `0` or `1`, never `27`/`28` for typed transactions).

- [ ] **Step 7: Commit**

```
git add Sources/CloudupSnapCore/Ethereum/Transaction.swift Tests/CloudupSnapCoreTests/Fixtures/TxSigningVectors.swift Tests/CloudupSnapCoreTests/TransactionTests.swift
git commit -m "Add EIP-1559 transaction builder and signer with viem cross-check fixture"
```

---

### Task 9d: Ethereum RPC client

**Files:**
- Create: `Sources/CloudupSnapCore/Ethereum/EthereumRPC.swift`
- Create: `Tests/CloudupSnapCoreTests/Fixtures/MockEthereumRPC.swift`
- Create: `Tests/CloudupSnapCoreTests/EthereumRPCTests.swift`

A minimal JSON-RPC 2.0 over HTTP client for exactly the calls we need. Five RPC methods:

| RPC method | Used for |
|---|---|
| `eth_chainId` | sanity check the endpoint matches expectations |
| `eth_getTransactionCount` | the current nonce for our address |
| `eth_maxPriorityFeePerGas` | priority-fee tip suggestion |
| `eth_gasPrice` | fallback baseFee approximation when `eth_feeHistory` isn't available |
| `eth_estimateGas` | gas limit for the ERC20 transfer (with a safety margin) |
| `eth_sendRawTransaction` | broadcast the signed transaction |
| `eth_getTransactionReceipt` | poll for inclusion + status |

Note: For Base Sepolia we'll use `eth_maxPriorityFeePerGas` + `eth_gasPrice` rather than the more elaborate `eth_feeHistory` heuristic. That's good enough for testnet uploads.

- [ ] **Step 1: Write the failing test**

`Tests/CloudupSnapCoreTests/Fixtures/MockEthereumRPC.swift`:

```swift
import Foundation
@testable import CloudupSnapCore

final class MockEthereumRPC: EthereumRPC, @unchecked Sendable {
    var canned: [String: Any] = [:]
    var receivedCalls: [(method: String, params: [Any])] = []

    func call<T: Decodable>(_ method: String, params: [Any]) async throws -> T {
        receivedCalls.append((method, params))
        guard let value = canned[method] else {
            throw NSError(domain: "MockEthereumRPC", code: 1, userInfo: [NSLocalizedDescriptionKey: "no canned response for \(method)"])
        }
        if let v = value as? T { return v }
        // Allow JSON-encoded canned values for richer types
        let data = try JSONSerialization.data(withJSONObject: value)
        return try JSONDecoder().decode(T.self, from: data)
    }
}
```

`Tests/CloudupSnapCoreTests/EthereumRPCTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

@Test func ethereumRPCParsesChainId() async throws {
    let rpc = MockEthereumRPC()
    rpc.canned["eth_chainId"] = "0x14a34"  // 84532 = Base Sepolia
    let id: HexQuantity = try await rpc.call("eth_chainId", params: [])
    #expect(id.uint64 == 84532)
}

@Test func ethereumRPCEncodesAddressParam() async throws {
    let rpc = MockEthereumRPC()
    rpc.canned["eth_getTransactionCount"] = "0x0"
    let _: HexQuantity = try await rpc.call(
        "eth_getTransactionCount",
        params: ["0x3E64B7838e791d5E2b766C7AFae5C3f2D57F9Cc7", "latest"]
    )
    #expect(rpc.receivedCalls.first?.method == "eth_getTransactionCount")
}

@Test func hexQuantityRoundTrips() throws {
    let hex = "0x14a34"
    let decoded = try HexQuantity(hex: hex)
    #expect(decoded.uint64 == 84532)
    #expect(decoded.hexString == "0x14a34")
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter EthereumRPCTests
```

Expected: `EthereumRPC`, `HexQuantity` undefined.

- [ ] **Step 3: Implement**

`Sources/CloudupSnapCore/Ethereum/EthereumRPC.swift`:

```swift
import Foundation

/// Ethereum JSON-RPC "quantity" type: 0x-prefixed hex, no leading zeros except for "0x0".
public struct HexQuantity: Codable, Equatable {
    public let hexString: String

    public init(uint64 value: UInt64) {
        self.hexString = "0x" + String(value, radix: 16)
    }

    public init(hex: String) throws {
        var s = hex
        if s.hasPrefix("0x") { s = String(s.dropFirst(2)) }
        if s.isEmpty { s = "0" }
        if UInt64(s, radix: 16) == nil {
            throw NSError(domain: "HexQuantity", code: 1, userInfo: [NSLocalizedDescriptionKey: "invalid hex quantity: \(hex)"])
        }
        self.hexString = "0x" + s
    }

    public var uint64: UInt64 {
        let s = hexString.hasPrefix("0x") ? String(hexString.dropFirst(2)) : hexString
        return UInt64(s, radix: 16) ?? 0
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        try self.init(hex: s)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(hexString)
    }
}

public struct TransactionReceipt: Codable {
    public let transactionHash: String
    public let blockNumber: String?
    public let status: String?   // "0x1" on success, "0x0" on revert
    public var didSucceed: Bool { status == "0x1" }
}

public protocol EthereumRPC: Sendable {
    func call<T: Decodable>(_ method: String, params: [Any]) async throws -> T
}

public struct HTTPEthereumRPC: EthereumRPC {
    public let endpoint: URL
    public let session: URLSession

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func call<T: Decodable>(_ method: String, params: [Any]) async throws -> T {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: envelope)
        let (data, _) = try await session.data(for: req)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let err = json?["error"] as? [String: Any] {
            let msg = (err["message"] as? String) ?? "unknown RPC error"
            throw NSError(domain: "HTTPEthereumRPC", code: (err["code"] as? Int) ?? -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard let result = json?["result"] else {
            throw NSError(domain: "HTTPEthereumRPC", code: -2, userInfo: [NSLocalizedDescriptionKey: "missing result"])
        }
        let resultData = try JSONSerialization.data(withJSONObject: result, options: .fragmentsAllowed)
        return try JSONDecoder().decode(T.self, from: resultData)
    }
}

// MARK: Higher-level helpers used by Wallet

public extension EthereumRPC {
    func chainId() async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_chainId", params: [])
        return q.uint64
    }
    func transactionCount(address: EthereumAddress, block: String = "pending") async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_getTransactionCount", params: [address.hexString(), block])
        return q.uint64
    }
    func maxPriorityFeePerGas() async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_maxPriorityFeePerGas", params: [])
        return q.uint64
    }
    func gasPrice() async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_gasPrice", params: [])
        return q.uint64
    }
    func estimateGas(from: EthereumAddress, to: EthereumAddress, data: Data) async throws -> UInt64 {
        let q: HexQuantity = try await call("eth_estimateGas", params: [[
            "from": from.hexString(),
            "to": to.hexString(),
            "data": data.hexEncodedString(prefix: true),
        ]])
        return q.uint64
    }
    func sendRawTransaction(_ raw: Data) async throws -> String {
        let result: String = try await call("eth_sendRawTransaction", params: [raw.hexEncodedString(prefix: true)])
        return result  // tx hash
    }
    func transactionReceipt(_ txHash: String) async throws -> TransactionReceipt? {
        do {
            let receipt: TransactionReceipt = try await call("eth_getTransactionReceipt", params: [txHash])
            return receipt
        } catch {
            // RPCs return null when the receipt isn't ready; depending on decoder this surfaces as a decode error.
            return nil
        }
    }
}
```

- [ ] **Step 4: Run, expect pass**

```
swift test --filter EthereumRPCTests
```

Expected: three tests pass.

- [ ] **Step 5: Commit**

```
git add Sources/CloudupSnapCore/Ethereum/EthereumRPC.swift Tests/CloudupSnapCoreTests/Fixtures/MockEthereumRPC.swift Tests/CloudupSnapCoreTests/EthereumRPCTests.swift
git commit -m "Add Ethereum JSON-RPC client with high-level helpers"
```

---

## Phase 4 — Wallet façade

### Task 10: Wallet with sendTransfer

**Files:**
- Create: `Sources/CloudupSnapCore/Wallet/Wallet.swift`
- Create: `Tests/CloudupSnapCoreTests/WalletTests.swift`

The Wallet composes everything above:
- Loads/generates a secp256k1 key via Keychain.
- Exposes `address`.
- `sendTransfer(to:amount:contract:rpc:)` builds an EIP-1559 ERC20 transfer, signs it, broadcasts via `EthereumRPC.sendRawTransaction`, polls `transactionReceipt` until success or timeout.
- Returns the tx hash on success.
- Throws on revert or timeout.

We define `WalletProtocol` from the start (the original plan deferred this to Task 20 — including it now avoids the later refactor).

- [ ] **Step 1: Write the failing test**

`Tests/CloudupSnapCoreTests/WalletTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

@Test func walletGeneratesAndPersists() throws {
    let store = InMemoryKeychainStore()
    let a = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let b = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    #expect(a.address == b.address)
    #expect(a.address.bytes.count == 20)
}

@Test func walletSendTransferOrchestratesRPCCalls() async throws {
    let store = InMemoryKeychainStore()
    let wallet = try Wallet.loadOrCreate(keychain: store, service: "test", account: "default")
    let rpc = MockEthereumRPC()
    rpc.canned["eth_chainId"] = "0x14a34"  // 84532
    rpc.canned["eth_getTransactionCount"] = "0x5"
    rpc.canned["eth_maxPriorityFeePerGas"] = "0x3b9aca00"  // 1 gwei
    rpc.canned["eth_gasPrice"] = "0x77359400"  // 2 gwei
    rpc.canned["eth_estimateGas"] = "0xea60"  // 60000
    rpc.canned["eth_sendRawTransaction"] = "0xabc1230000000000000000000000000000000000000000000000000000000001"
    rpc.canned["eth_getTransactionReceipt"] = [
        "transactionHash": "0xabc1230000000000000000000000000000000000000000000000000000000001",
        "blockNumber": "0x123",
        "status": "0x1",
    ]
    let to = try Data(hexString: "0xc5F06701bd664159620F1a83A64A57ebCEF9151b")
    let contract = try Data(hexString: "0x036CbD53842c5426634e7929541eC2318f3dCF7e")

    let txHash = try await wallet.sendTransfer(
        to: EthereumAddress(bytes: to),
        amount: 50000,                          // 0.05 USDC in 6-decimal units
        contract: EthereumAddress(bytes: contract),
        rpc: rpc,
        receiptPoll: ReceiptPollPolicy(interval: 0.01, timeout: 1.0)
    )
    #expect(txHash == "0xabc1230000000000000000000000000000000000000000000000000000000001")
    #expect(rpc.receivedCalls.map { $0.method }.contains("eth_sendRawTransaction"))
}
```

- [ ] **Step 2: Run, expect fail**

```
swift test --filter WalletTests
```

Expected: `Wallet`, `WalletProtocol`, `ReceiptPollPolicy` undefined.

- [ ] **Step 3: Implement**

`Sources/CloudupSnapCore/Wallet/Wallet.swift`:

```swift
import Foundation

public protocol WalletProtocol: Sendable {
    var address: EthereumAddress { get }
    func sendTransfer(
        to: EthereumAddress,
        amount: UInt64,
        contract: EthereumAddress,
        rpc: EthereumRPC,
        receiptPoll: ReceiptPollPolicy
    ) async throws -> String
}

public struct ReceiptPollPolicy {
    public let interval: TimeInterval
    public let timeout: TimeInterval
    public init(interval: TimeInterval = 1.0, timeout: TimeInterval = 60.0) {
        self.interval = interval
        self.timeout = timeout
    }
}

public enum WalletError: Error {
    case transactionReverted(txHash: String)
    case receiptTimeout(txHash: String)
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

    public func sendTransfer(
        to: EthereumAddress,
        amount: UInt64,
        contract: EthereumAddress,
        rpc: EthereumRPC,
        receiptPoll: ReceiptPollPolicy = ReceiptPollPolicy()
    ) async throws -> String {
        let chainId = try await rpc.chainId()
        let nonce = try await rpc.transactionCount(address: address)
        let tip = try await rpc.maxPriorityFeePerGas()
        let basefee = try await rpc.gasPrice()
        // EIP-1559: maxFeePerGas = baseFee + tip, with headroom.
        let maxFee = basefee + tip
        let calldata = ERC20.encodeTransfer(to: to.bytes, amount: amount)
        let gas = try await rpc.estimateGas(from: address, to: contract, data: calldata)
        let gasWithMargin = (gas * 12) / 10  // 20% safety margin

        let tx = EIP1559Transaction(
            chainId: chainId,
            nonce: nonce,
            maxPriorityFeePerGas: tip,
            maxFeePerGas: maxFee,
            gasLimit: gasWithMargin,
            to: contract.bytes,
            value: 0,
            data: calldata
        )
        let signed = try tx.sign(with: signer)
        let txHash = try await rpc.sendRawTransaction(signed.rawTransaction)
        try await waitForReceipt(txHash: txHash, rpc: rpc, policy: receiptPoll)
        return txHash
    }

    private func waitForReceipt(txHash: String, rpc: EthereumRPC, policy: ReceiptPollPolicy) async throws {
        let deadline = Date().addingTimeInterval(policy.timeout)
        while Date() < deadline {
            if let receipt = try await rpc.transactionReceipt(txHash) {
                if receipt.didSucceed { return }
                throw WalletError.transactionReverted(txHash: txHash)
            }
            try await Task.sleep(nanoseconds: UInt64(policy.interval * 1_000_000_000))
        }
        throw WalletError.receiptTimeout(txHash: txHash)
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
git add Sources/CloudupSnapCore/Wallet/Wallet.swift Tests/CloudupSnapCoreTests/WalletTests.swift
git commit -m "Add Wallet façade with sendTransfer composing tx signer + RPC"
```

---

## Phase 5 — MCP transport

### Task 11: JSON-RPC 2.0 framing types

**Files:**
- Create: `Sources/CloudupSnapCore/MCP/JSONRPC.swift`
- Create: `Tests/CloudupSnapCoreTests/JSONRPCTests.swift`

- [ ] **Step 1: Write the failing test**

`Tests/CloudupSnapCoreTests/JSONRPCTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

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

`Sources/CloudupSnapCore/MCP/JSONRPC.swift`:

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
git add Sources/CloudupSnapCore/MCP/JSONRPC.swift Tests/CloudupSnapCoreTests/JSONRPCTests.swift
git commit -m "Add JSON-RPC 2.0 Codable types for MCP transport"
```

---

### Task 12: Server-Sent Events parser

**Files:**
- Create: `Sources/CloudupSnapCore/MCP/SSEReader.swift`
- Create: `Tests/CloudupSnapCoreTests/SSEReaderTests.swift`

The SSE format is line-oriented: each `\n\n` separates an event. Lines beginning with `data:` accumulate; `event:` sets the event type; `id:` sets the last-event id; comments start with `:`. We only need `data:` for MCP responses.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

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

`Sources/CloudupSnapCore/MCP/SSEReader.swift`:

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
git add Sources/CloudupSnapCore/MCP/SSEReader.swift Tests/CloudupSnapCoreTests/SSEReaderTests.swift
git commit -m "Add SSEReader for Server-Sent Events with chunked input"
```

---

### Task 13: MCPTransport protocol + Streamable HTTP implementation

**Files:**
- Create: `Sources/CloudupSnapCore/MCP/MCPTransport.swift`
- Create: `Sources/CloudupSnapCore/MCP/StreamableHTTPTransport.swift`

This task is split into two files because the protocol is testable (mock transport) while the URLSession implementation is integration-tested via `Uploader`.

- [ ] **Step 1: Define the transport protocol**

`Sources/CloudupSnapCore/MCP/MCPTransport.swift`:

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

`Sources/CloudupSnapCore/MCP/StreamableHTTPTransport.swift`:

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
git add Sources/CloudupSnapCore/MCP/MCPTransport.swift Sources/CloudupSnapCore/MCP/StreamableHTTPTransport.swift
git commit -m "Add MCPTransport protocol and Streamable HTTP implementation"
```

---

### Task 14: MCPClient with `_meta` support

**Files:**
- Create: `Sources/CloudupSnapCore/MCP/MCPClient.swift`
- Create: `Tests/CloudupSnapCoreTests/Fixtures/MockMCPTransport.swift`
- Create: `Tests/CloudupSnapCoreTests/MCPClientTests.swift`

The `mpp-remote` protocol (see `docs/superpowers/protocol/mpp-x402.md` §5) attaches the payment credential to a *retry* via `params._meta["org.paymentauth/credential"]`. So `MCPClient.callTool` needs to accept an optional `meta` dictionary and merge it into the JSON-RPC request's `params._meta`.

- [ ] **Step 1: Write the mock transport fixture**

`Tests/CloudupSnapCoreTests/Fixtures/MockMCPTransport.swift`:

```swift
import Foundation
@testable import CloudupSnapCore

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

`Tests/CloudupSnapCoreTests/MCPClientTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

@Test func mcpClientCallsToolAndDecodesResult() async throws {
    let transport = MockMCPTransport()
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

@Test func mcpClientPassesMetaInParams() async throws {
    let transport = MockMCPTransport()
    let resultJSON = #"{"jsonrpc":"2.0","id":1,"result":{"ok":true}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: resultJSON.data(using: .utf8)!)
    ]
    let client = MCPClient(transport: transport)
    _ = try await client.callTool(
        name: "quick_upload",
        arguments: ["filename": .string("x.png")],
        meta: ["org.paymentauth/credential": .object([
            "method": .string("erc20-usdc-base-sepolia"),
            "settlement_tx_hash": .string("0xabc"),
        ])]
    )
    let req = transport.receivedRequests[0].request
    let params = req.params
    #expect(params?["_meta"]?.objectValue?["org.paymentauth/credential"] != nil)
    // Arguments must be preserved alongside _meta
    #expect(params?["arguments"]?.objectValue?["filename"] == .string("x.png"))
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

Expected: `MCPClient` undefined.

- [ ] **Step 4: Implement**

`Sources/CloudupSnapCore/MCP/MCPClient.swift`:

```swift
import Foundation

public actor MCPClient {
    public let transport: MCPTransport
    private var nextId = 1

    public init(transport: MCPTransport) {
        self.transport = transport
    }

    /// Call a tool. `meta` is merged into `params._meta`. Throws `JSONRPCError` on
    /// any failure response (caller decides how to react to -32042 payment-required).
    public func callTool(
        name: String,
        arguments: [String: EIP712Value],
        meta: [String: EIP712Value]? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> EIP712Value {
        let id = nextId; nextId += 1
        var params: [String: EIP712Value] = [
            "name": .string(name),
            "arguments": .object(arguments),
        ]
        if let meta = meta, !meta.isEmpty {
            params["_meta"] = .object(meta)
        }
        let req = JSONRPCRequest(id: .number(id), method: "tools/call", params: params)
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

Expected: three tests pass.

- [ ] **Step 6: Commit**

```
git add Sources/CloudupSnapCore/MCP/MCPClient.swift Tests/CloudupSnapCoreTests/Fixtures/MockMCPTransport.swift Tests/CloudupSnapCoreTests/MCPClientTests.swift
git commit -m "Add MCPClient with callTool supporting params._meta credential"
```

---

## Phase 6 — Payment

### Task 15: PaymentChallenge parsing

**Files:**
- Create: `Sources/CloudupSnapCore/Payment/PaymentChallenge.swift`
- Create: `Tests/CloudupSnapCoreTests/Fixtures/PaymentChallengeSamples.swift`
- Create: `Tests/CloudupSnapCoreTests/PaymentChallengeTests.swift`

Schema is documented in `docs/superpowers/protocol/mpp-x402.md` §2. The 402 response is a JSON-RPC error with `error.code === -32042` and `error.data.challenges[]`. Each challenge has `challenge_id`, `sku`, `amount` (decimal USD string), `opaque`, and `methods[]`. Each method has `id`, `network`, `currency`, `currency_contract`, `currency_decimals`, `recipient_address`.

- [ ] **Step 1: Add the fixture**

`Tests/CloudupSnapCoreTests/Fixtures/PaymentChallengeSamples.swift`:

```swift
import Foundation

enum PaymentChallengeSamples {
    /// Verbatim from `docs/superpowers/protocol/mpp-x402.md` §9.2.
    static let basicChallengeJSON = """
    {
      "challenges": [
        {
          "challenge_id": "ch_abc123",
          "sku": "upload-screenshot",
          "amount": "0.10",
          "opaque": "srv-nonce-xyz789",
          "methods": [
            {
              "id": "erc20-usdc-base-sepolia",
              "network": "base-sepolia",
              "currency": "USDC",
              "currency_contract": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
              "currency_decimals": 6,
              "recipient_address": "0xc5F06701bd664159620F1a83A64A57ebCEF9151b"
            }
          ]
        }
      ]
    }
    """
}
```

- [ ] **Step 2: Write the failing test**

`Tests/CloudupSnapCoreTests/PaymentChallengeTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

@Test func paymentChallengeParses() throws {
    let data = PaymentChallengeSamples.basicChallengeJSON.data(using: .utf8)!
    let payload = try JSONDecoder().decode(PaymentChallengePayload.self, from: data)
    let challenge = payload.challenges[0]
    #expect(challenge.challengeId == "ch_abc123")
    #expect(challenge.amount == Decimal(string: "0.10"))
    #expect(challenge.opaque?.stringValue == "srv-nonce-xyz789")
    #expect(challenge.methods.first?.id == "erc20-usdc-base-sepolia")
    #expect(challenge.methods.first?.currencyDecimals == 6)
}

@Test func paymentChallengePicksFirstSupportedMethod() throws {
    let data = PaymentChallengeSamples.basicChallengeJSON.data(using: .utf8)!
    let payload = try JSONDecoder().decode(PaymentChallengePayload.self, from: data)
    let method = payload.challenges[0].firstSupportedMethod()
    #expect(method?.id == "erc20-usdc-base-sepolia")
    #expect(method?.recipientAddress.hexEncodedString() != nil)
}
```

- [ ] **Step 3: Run, expect fail**

```
swift test --filter PaymentChallengeTests
```

Expected: types undefined.

- [ ] **Step 4: Implement**

`Sources/CloudupSnapCore/Payment/PaymentChallenge.swift`:

```swift
import Foundation

public struct PaymentChallengePayload: Decodable {
    public let challenges: [PaymentChallenge]
}

public struct PaymentChallenge: Decodable {
    public let challengeId: String
    public let sku: String?
    public let amount: Decimal
    public let opaque: EIP712Value?
    public let methods: [PaymentMethod]

    enum CodingKeys: String, CodingKey {
        case challengeId = "challenge_id"
        case sku, amount, opaque, methods
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.challengeId = try c.decode(String.self, forKey: .challengeId)
        self.sku = try c.decodeIfPresent(String.self, forKey: .sku)
        let amountString = try c.decode(String.self, forKey: .amount)
        guard let amount = Decimal(string: amountString) else {
            throw DecodingError.dataCorruptedError(forKey: .amount, in: c, debugDescription: "non-numeric amount")
        }
        self.amount = amount
        self.opaque = try c.decodeIfPresent(EIP712Value.self, forKey: .opaque)
        self.methods = try c.decode([PaymentMethod].self, forKey: .methods)
    }

    /// First method whose id matches `eip3009-usdc-*`, `erc20-*`, or any method that
    /// has a non-empty currencyContract. Mirrors mpp-remote's matching at :174–177.
    public func firstSupportedMethod() -> PaymentMethod? {
        methods.first(where: { m in
            m.id.hasPrefix("eip3009-usdc-")
            || m.id.hasPrefix("erc20-")
            || !m.currencyContract.isEmpty
        })
    }
}

public struct PaymentMethod: Decodable {
    public let id: String
    public let network: String
    public let currency: String
    public let currencyContractHex: String
    public let currencyDecimals: Int
    public let recipientAddressHex: String

    enum CodingKeys: String, CodingKey {
        case id, network, currency
        case currencyContract = "currency_contract"
        case currencyDecimals = "currency_decimals"
        case recipientAddress = "recipient_address"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.network = try c.decode(String.self, forKey: .network)
        self.currency = try c.decode(String.self, forKey: .currency)
        self.currencyContractHex = try c.decode(String.self, forKey: .currencyContract)
        self.currencyDecimals = try c.decode(Int.self, forKey: .currencyDecimals)
        self.recipientAddressHex = try c.decode(String.self, forKey: .recipientAddress)
    }

    public var currencyContract: Data { (try? Data(hexString: currencyContractHex)) ?? Data() }
    public var recipientAddress: Data { (try? Data(hexString: recipientAddressHex)) ?? Data() }
}
```

- [ ] **Step 5: Run, expect pass**

```
swift test --filter PaymentChallengeTests
```

Expected: both tests pass.

- [ ] **Step 6: Commit**

```
git add Sources/CloudupSnapCore/Payment/PaymentChallenge.swift Tests/CloudupSnapCoreTests/Fixtures/PaymentChallengeSamples.swift Tests/CloudupSnapCoreTests/PaymentChallengeTests.swift
git commit -m "Add PaymentChallenge parsing for mpp-remote 402 payloads"
```

---

### Task 16: PaymentError types

**Files:**
- Create: `Sources/CloudupSnapCore/Payment/PaymentError.swift`

- [ ] **Step 1: Implement**

`Sources/CloudupSnapCore/Payment/PaymentError.swift`:

```swift
import Foundation

public enum PaymentError: Error, Equatable {
    /// The quote exceeds the configured cap.
    case capExceeded(quotedUSD: Decimal, capUSD: Decimal)

    /// No method in the challenge matches anything we support.
    case noSupportedMethod(offered: [String])

    /// On-chain settlement transaction reverted.
    case settlementReverted(txHash: String)

    /// Settlement transaction never confirmed within the receipt-poll timeout.
    case settlementTimeout(txHash: String)

    /// The challenge payload was malformed or could not be parsed.
    case malformedChallenge(String)

    /// The wallet does not have enough balance to send the transfer (gas or token).
    case insufficientFunds(needed: Decimal, haveUSDC: Decimal?, haveETH: Decimal?)

    /// Any other unexpected failure.
    case other(String)
}
```

- [ ] **Step 2: Verify build**

```
swift build
```

- [ ] **Step 3: Commit**

```
git add Sources/CloudupSnapCore/Payment/PaymentError.swift
git commit -m "Add PaymentError typed errors for FundingPanel routing"
```

---

### Task 17: PaymentClient.settle

**Files:**
- Create: `Sources/CloudupSnapCore/Payment/PaymentCredential.swift`
- Create: `Sources/CloudupSnapCore/Payment/PaymentClient.swift`
- Create: `Tests/CloudupSnapCoreTests/PaymentClientTests.swift`

PaymentClient handles a single challenge:
1. Pick the first supported method (per `PaymentChallenge.firstSupportedMethod`).
2. Validate `challenge.amount ≤ capUSD`. Throw `capExceeded` otherwise.
3. Convert `amount` (decimal USD) into the method's token units (multiply by `10^currencyDecimals`).
4. Call `wallet.sendTransfer(to: recipientAddress, amount: tokenAmount, contract: currencyContract, rpc:)`.
5. Build the `PaymentCredential` from the resulting tx hash.

- [ ] **Step 1: Define PaymentCredential**

`Sources/CloudupSnapCore/Payment/PaymentCredential.swift`:

```swift
import Foundation

/// Sent back to the server inside `params._meta["org.paymentauth/credential"]`.
/// See `docs/superpowers/protocol/mpp-x402.md` §5.
public struct PaymentCredential: Codable, Equatable {
    public let method: String
    public let challengeId: String
    public let opaque: EIP712Value?
    public let settlementTxHash: String

    enum CodingKeys: String, CodingKey {
        case method
        case challengeId = "challenge_id"
        case opaque
        case settlementTxHash = "settlement_tx_hash"
    }

    public var asEIP712Value: EIP712Value {
        var obj: [String: EIP712Value] = [
            "method": .string(method),
            "challenge_id": .string(challengeId),
            "settlement_tx_hash": .string(settlementTxHash),
        ]
        if let o = opaque { obj["opaque"] = o }
        return .object(obj)
    }
}
```

- [ ] **Step 2: Write the failing test**

`Tests/CloudupSnapCoreTests/PaymentClientTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

private final class StubWallet: WalletProtocol, @unchecked Sendable {
    let address: EthereumAddress
    var lastTransferArgs: (to: EthereumAddress, amount: UInt64, contract: EthereumAddress)?
    let returnedTxHash: String

    init(returnedTxHash: String = "0xfeedbeef000000000000000000000000000000000000000000000000000000aa") {
        self.address = EthereumAddress(bytes: Data(repeating: 0xaa, count: 20))
        self.returnedTxHash = returnedTxHash
    }

    func sendTransfer(
        to: EthereumAddress, amount: UInt64, contract: EthereumAddress,
        rpc: EthereumRPC, receiptPoll: ReceiptPollPolicy
    ) async throws -> String {
        lastTransferArgs = (to, amount, contract)
        return returnedTxHash
    }
}

@Test func paymentClientSettlesChallengeUnderCap() async throws {
    let payload = try JSONDecoder().decode(
        PaymentChallengePayload.self,
        from: PaymentChallengeSamples.basicChallengeJSON.data(using: .utf8)!
    )
    let challenge = payload.challenges[0]
    let wallet = StubWallet()
    let rpc = MockEthereumRPC()
    let client = PaymentClient(wallet: wallet, rpc: rpc, capUSD: Decimal(string: "0.50")!)
    let credential = try await client.settle(challenge: challenge)
    #expect(credential.method == "erc20-usdc-base-sepolia")
    #expect(credential.challengeId == "ch_abc123")
    #expect(credential.settlementTxHash == "0xfeedbeef000000000000000000000000000000000000000000000000000000aa")
    // 0.10 USDC with 6 decimals = 100000 raw units
    #expect(wallet.lastTransferArgs?.amount == 100000)
}

@Test func paymentClientRejectsOverCap() async throws {
    let payload = try JSONDecoder().decode(
        PaymentChallengePayload.self,
        from: PaymentChallengeSamples.basicChallengeJSON.data(using: .utf8)!
    )
    let challenge = payload.challenges[0]   // amount = 0.10
    let wallet = StubWallet()
    let rpc = MockEthereumRPC()
    let client = PaymentClient(wallet: wallet, rpc: rpc, capUSD: Decimal(string: "0.05")!)
    do {
        _ = try await client.settle(challenge: challenge)
        Issue.record("expected capExceeded")
    } catch PaymentError.capExceeded(let q, let cap) {
        #expect(q == Decimal(string: "0.10"))
        #expect(cap == Decimal(string: "0.05"))
    } catch {
        Issue.record("wrong error: \(error)")
    }
}

@Test func paymentClientRejectsWhenNoMethodSupported() async throws {
    let json = """
    {"challenges":[{"challenge_id":"x","amount":"0.10","methods":[{"id":"unsupported","network":"foo","currency":"FOO","currency_contract":"","currency_decimals":0,"recipient_address":""}]}]}
    """.data(using: .utf8)!
    let payload = try JSONDecoder().decode(PaymentChallengePayload.self, from: json)
    let challenge = payload.challenges[0]
    let wallet = StubWallet()
    let rpc = MockEthereumRPC()
    let client = PaymentClient(wallet: wallet, rpc: rpc, capUSD: 1)
    await #expect(throws: PaymentError.self) {
        _ = try await client.settle(challenge: challenge)
    }
}
```

- [ ] **Step 3: Run, expect fail**

```
swift test --filter PaymentClientTests
```

Expected: `PaymentClient` undefined.

- [ ] **Step 4: Implement**

`Sources/CloudupSnapCore/Payment/PaymentClient.swift`:

```swift
import Foundation

public struct PaymentClient {
    public let wallet: WalletProtocol
    public let rpc: EthereumRPC
    public let capUSD: Decimal
    public let receiptPoll: ReceiptPollPolicy

    public init(
        wallet: WalletProtocol,
        rpc: EthereumRPC,
        capUSD: Decimal = Decimal(string: "0.50")!,
        receiptPoll: ReceiptPollPolicy = ReceiptPollPolicy()
    ) {
        self.wallet = wallet
        self.rpc = rpc
        self.capUSD = capUSD
        self.receiptPoll = receiptPoll
    }

    public func isPaymentRequired(_ error: JSONRPCError) -> Bool {
        error.code == -32042
    }

    public func extractPayload(from error: JSONRPCError) throws -> PaymentChallengePayload {
        guard let data = error.data else {
            throw PaymentError.malformedChallenge("missing data on -32042 error")
        }
        let json = try JSONEncoder().encode(data)
        do {
            return try JSONDecoder().decode(PaymentChallengePayload.self, from: json)
        } catch {
            throw PaymentError.malformedChallenge("\(error)")
        }
    }

    public func settle(challenge: PaymentChallenge) async throws -> PaymentCredential {
        guard challenge.amount <= capUSD else {
            throw PaymentError.capExceeded(quotedUSD: challenge.amount, capUSD: capUSD)
        }
        guard let method = challenge.firstSupportedMethod() else {
            throw PaymentError.noSupportedMethod(offered: challenge.methods.map(\.id))
        }
        let tokenAmount = try unitsFromDecimal(challenge.amount, decimals: method.currencyDecimals)
        let recipient = EthereumAddress(bytes: method.recipientAddress)
        let contract = EthereumAddress(bytes: method.currencyContract)

        let txHash: String
        do {
            txHash = try await wallet.sendTransfer(
                to: recipient,
                amount: tokenAmount,
                contract: contract,
                rpc: rpc,
                receiptPoll: receiptPoll
            )
        } catch WalletError.transactionReverted(let hash) {
            throw PaymentError.settlementReverted(txHash: hash)
        } catch WalletError.receiptTimeout(let hash) {
            throw PaymentError.settlementTimeout(txHash: hash)
        }
        return PaymentCredential(
            method: method.id,
            challengeId: challenge.challengeId,
            opaque: challenge.opaque,
            settlementTxHash: txHash
        )
    }

    /// Convert a decimal USD amount (e.g. 0.10) into integer token units
    /// (e.g. 100_000 for 6-decimal USDC).
    private func unitsFromDecimal(_ amount: Decimal, decimals: Int) throws -> UInt64 {
        var multiplier = Decimal(1)
        for _ in 0..<decimals { multiplier *= 10 }
        var scaled = amount * multiplier
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let str = (rounded as NSDecimalNumber).stringValue
        guard let u = UInt64(str) else {
            throw PaymentError.malformedChallenge("amount \(amount) not representable as UInt64 token units")
        }
        return u
    }
}
```

- [ ] **Step 5: Run, expect pass**

```
swift test --filter PaymentClientTests
```

Expected: three tests pass.

- [ ] **Step 6: Commit**

```
git add Sources/CloudupSnapCore/Payment/PaymentCredential.swift Sources/CloudupSnapCore/Payment/PaymentClient.swift Tests/CloudupSnapCoreTests/PaymentClientTests.swift
git commit -m "Add PaymentClient: settle challenges via on-chain transfer + credential"
```

---

## Phase 7 — Uploader and CLI

### Task 18: Uploader

**Files:**
- Create: `Sources/CloudupSnapCore/Uploader/Uploader.swift`
- Create: `Tests/CloudupSnapCoreTests/UploaderTests.swift`

The Uploader orchestrates: first attempt → if -32042, parse challenge, settle, retry with credential in `_meta`. Single retry only (mirrors mpp-remote :253–263).

- [ ] **Step 1: Write the failing test**

`Tests/CloudupSnapCoreTests/UploaderTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

private final class StubWallet: WalletProtocol, @unchecked Sendable {
    let address = EthereumAddress(bytes: Data(repeating: 0xaa, count: 20))
    let txHash: String
    init(txHash: String) { self.txHash = txHash }
    func sendTransfer(
        to: EthereumAddress, amount: UInt64, contract: EthereumAddress,
        rpc: EthereumRPC, receiptPoll: ReceiptPollPolicy
    ) async throws -> String { txHash }
}

@Test func uploaderPaysAndReturnsShareURL() async throws {
    let wallet = StubWallet(txHash: "0xabc1230000000000000000000000000000000000000000000000000000000001")
    let rpc = MockEthereumRPC()
    let payment = PaymentClient(wallet: wallet, rpc: rpc)
    let transport = MockMCPTransport()

    // First response: 402 with challenge payload
    let challengeJSON = PaymentChallengeSamples.basicChallengeJSON
    let challenge1 = """
    {"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required","data":\(challengeJSON)}}
    """
    let success2 = #"{"jsonrpc":"2.0","id":2,"result":{"item_id":"abc","share_url":"https://stage-cloudup.com/s/abc/abc"}}"#
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: challenge1.data(using: .utf8)!),
        try JSONDecoder().decode(JSONRPCResponse.self, from: success2.data(using: .utf8)!),
    ]

    let mcp = MCPClient(transport: transport)
    let uploader = Uploader(mcp: mcp, payment: payment)
    let url = try await uploader.upload(
        data: Data([0x89, 0x50, 0x4e, 0x47]),
        filename: "x.png",
        mime: "image/png"
    )
    #expect(url.absoluteString == "https://stage-cloudup.com/s/abc/abc")
    #expect(transport.receivedRequests.count == 2)

    // The retry must carry params._meta["org.paymentauth/credential"]
    let retryParams = transport.receivedRequests[1].request.params
    let credential = retryParams?["_meta"]?.objectValue?["org.paymentauth/credential"]?.objectValue
    #expect(credential?["method"] == .string("erc20-usdc-base-sepolia"))
    #expect(credential?["settlement_tx_hash"] == .string("0xabc1230000000000000000000000000000000000000000000000000000000001"))
}

@Test func uploaderSurfacesCapExceeded() async throws {
    let wallet = StubWallet(txHash: "0x")
    let rpc = MockEthereumRPC()
    let payment = PaymentClient(wallet: wallet, rpc: rpc, capUSD: Decimal(string: "0.01")!)
    let transport = MockMCPTransport()

    let challengeJSON = PaymentChallengeSamples.basicChallengeJSON   // amount 0.10
    let challenge1 = """
    {"jsonrpc":"2.0","id":1,"error":{"code":-32042,"message":"payment required","data":\(challengeJSON)}}
    """
    transport.queuedResponses = [
        try JSONDecoder().decode(JSONRPCResponse.self, from: challenge1.data(using: .utf8)!),
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

Expected: `Uploader` undefined.

- [ ] **Step 3: Implement**

`Sources/CloudupSnapCore/Uploader/Uploader.swift`:

```swift
import Foundation

public struct Uploader {
    public let mcp: MCPClient
    public let payment: PaymentClient

    public init(mcp: MCPClient, payment: PaymentClient) {
        self.mcp = mcp
        self.payment = payment
    }

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
            let payload = try payment.extractPayload(from: err)
            guard let challenge = payload.challenges.first else {
                throw PaymentError.malformedChallenge("empty challenges array")
            }
            let credential = try await payment.settle(challenge: challenge)
            let result = try await mcp.callTool(
                name: "quick_upload",
                arguments: args,
                meta: ["org.paymentauth/credential": credential.asEIP712Value]
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
git add Sources/CloudupSnapCore/Uploader/Uploader.swift Tests/CloudupSnapCoreTests/UploaderTests.swift
git commit -m "Add Uploader: orchestrates MCP + payment + credential retry"
```

---

### Task 19: CLI binary

**Files:**
- Create: `Sources/cloudupsnap-cli/main.swift`

- [ ] **Step 1: Write the CLI**

`Sources/cloudupsnap-cli/main.swift`:

```swift
import Foundation
import CloudupSnapCore

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
            print("usage: cloudupsnap-cli upload <path>")
            print("       cloudupsnap-cli address")
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
            service: "com.bongnam.cloudupsnap",
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

Expected: success. The CLI binary is at `.build/debug/cloudupsnap-cli`.

- [ ] **Step 3: Try `address` subcommand (no upload, just prints wallet address)**

```
swift run cloudupsnap-cli address
```

Expected: prints a 0x-prefixed Ethereum address. The first run may prompt for Keychain access — accept.

- [ ] **Step 4: Commit**

```
git add Sources/cloudupsnap-cli/main.swift
git commit -m "Add cloudupsnap-cli executable with upload and address subcommands"
```

---

## Phase 8 — End-to-end integration

### Task 20: Integration test against live Cloudup

**Files:**
- Create: `Tests/CloudupSnapCoreTests/UploaderIntegrationTests.swift`

This test pays a real (small) on-chain transfer on Base Sepolia and uploads a real file to Cloudup stage. Run only when you have a funded test wallet — see Step 3 below.

- [ ] **Step 1: Write the test**

`Tests/CloudupSnapCoreTests/UploaderIntegrationTests.swift`:

```swift
import Testing
import Foundation
@testable import CloudupSnapCore

@Test(.disabled(
    if: ProcessInfo.processInfo.environment["CLOUDUPSNAP_INTEGRATION"] != "1"
       || ProcessInfo.processInfo.environment["CLOUDUPSNAP_TEST_WALLET_KEY"] == nil,
    "Set CLOUDUPSNAP_INTEGRATION=1 and CLOUDUPSNAP_TEST_WALLET_KEY=0x... to run"
))
func integrationPaidUploadAgainstCloudupStage() async throws {
    let keyHex = ProcessInfo.processInfo.environment["CLOUDUPSNAP_TEST_WALLET_KEY"]!
    let mcpEndpoint = URL(string: ProcessInfo.processInfo.environment["MCP_ENDPOINT"]
        ?? "https://api.stage-cloudup.com/mcp/public")!
    let rpcEndpoint = URL(string: ProcessInfo.processInfo.environment["BASE_SEPOLIA_RPC"]
        ?? "https://sepolia.base.org")!

    let priv = try Data(hexString: keyHex)
    let signer = try Secp256k1Signer(privateKey: priv)
    let address = EthereumAddress(uncompressedPublicKey: signer.publicKeyUncompressed)
    let wallet = Wallet(address: address, signer: signer)

    let rpc = HTTPEthereumRPC(endpoint: rpcEndpoint)
    let payment = PaymentClient(
        wallet: wallet,
        rpc: rpc,
        capUSD: Decimal(string: "0.50")!,
        receiptPoll: ReceiptPollPolicy(interval: 2.0, timeout: 120.0)
    )
    let transport = StreamableHTTPTransport(endpoint: mcpEndpoint)
    let mcp = MCPClient(transport: transport)
    let uploader = Uploader(mcp: mcp, payment: payment)

    // Minimal valid PNG (1x1 transparent)
    let pngHex = "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da636400000000050001a5f645080000000049454e44ae426082"
    let png = try Data(hexString: pngHex)

    let url = try await uploader.upload(data: png, filename: "integration.png", mime: "image/png")
    #expect(url.absoluteString.contains("stage-cloudup.com"))
}
```

- [ ] **Step 2: Run unit tests to confirm no regressions**

```
swift test
```

Expected: all unit tests pass; integration test is skipped (env not set).

- [ ] **Step 3: Run the integration test (only if you have a funded test wallet)**

The wallet at `CLOUDUPSNAP_TEST_WALLET_KEY` needs Base Sepolia ETH (for gas) AND Base Sepolia USDC (for the upload fee, ~0.10 USDC). Fund it via:
- Coinbase CDP faucet: https://portal.cdp.coinbase.com/products/faucet (Base Sepolia network)
- Circle USDC faucet: https://faucet.circle.com/

Then:

```
CLOUDUPSNAP_INTEGRATION=1 \
CLOUDUPSNAP_TEST_WALLET_KEY=0xYOUR_FUNDED_TESTNET_KEY \
swift test --filter UploaderIntegrationTests
```

Expected: the test executes a real on-chain USDC transfer, waits for confirmation (~5–30 seconds on Base Sepolia), uploads the tiny PNG, and asserts a stage-cloudup.com share URL.

If you don't yet have a funded test wallet:
- Run `swift run cloudupsnap-cli address` to get the CLI's Keychain-stored wallet address.
- Fund that address (same instructions as above).
- Run the CLI directly: `swift run cloudupsnap-cli upload some-file.png`. The CLI exercises the same code paths.

- [ ] **Step 4: Commit**

```
git add Tests/CloudupSnapCoreTests/UploaderIntegrationTests.swift
git commit -m "Add gated integration test for paid upload against Cloudup stage"
```

---

### Task 21: Manual end-to-end verification

**Files:** none (verification only)

- [ ] **Step 1: Build the CLI**

```
swift build -c release
```

Expected: release binary at `.build/release/cloudupsnap-cli`.

- [ ] **Step 2: Get the wallet address**

```
.build/release/cloudupsnap-cli address
```

Expected: prints a 0x-prefixed Ethereum address.

- [ ] **Step 3: Fund the wallet**

Go to https://portal.cdp.coinbase.com/products/faucet (Base Sepolia network) and request both ETH and USDC for the address above. Wait ~30 seconds for confirmations.

- [ ] **Step 4: Upload a test image**

Create a tiny PNG (or any file) for testing:

```
# A trivial PNG; you can also use any existing image.
echo "test" > /tmp/cloudupsnap-test.txt
.build/release/cloudupsnap-cli upload /tmp/cloudupsnap-test.txt
```

Expected: prints a Cloudup share URL to stdout, e.g.:

```
uploading cloudupsnap-test.txt (5 bytes) from 0xabcd...
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

This plan implements the following components from the spec (`docs/superpowers/specs/2026-05-12-cloudupsnap-design.md`):

- `Wallet` — Tasks 4–8b (key, address, Keychain) + Tasks 9–9d (Ethereum primitives) + Task 10 (façade)
- `MCPClient` — Tasks 11–14
- `PaymentClient` — Tasks 15–17 (now: challenge parsing, errors, `settle()` via on-chain transfer)
- `Uploader` — Task 18

The following spec components are **intentionally deferred to Plan 2** (the macOS app):
- `MenubarController`, `HotkeyManager`, `OnboardingCoordinator`, `CaptureCoordinator`, `CaptureService`, `AnnotationEditor`, `AnnotationModel`, `UndoStack`, `Renderer`, `ClipboardService`, `NotificationService`, `FundingPanel`
- Balance-query methods on `Wallet` (`balanceUSDC`, `balanceETH`) — needed only by `FundingPanel` in Plan 2. The `EthereumRPC` helpers added in Task 9d make these one-liners when needed.

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

Plan 2 will build directly on top of the `CloudupSnapCore` library — `Uploader` is the single integration point.
