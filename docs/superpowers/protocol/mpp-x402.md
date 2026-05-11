# MPP / x402 Payment Protocol

Wire-level documentation of the client-side payment-handshake protocol implemented
by `github:tellyworth/mpp-remote` (tag `main`, commit reflected in
`/tmp/mpp-remote-probe/.git/logs/HEAD`).  Every claim below cites a specific
file and line in that repository so future engineers can verify against the
source of truth.

> **IMPORTANT — read before using this as a Swift spec.**
> The current implementation settles payments with a real on-chain ERC20
> `transfer()` transaction and returns the resulting tx hash as the credential.
> It does **not** use EIP-712 signed authorizations (EIP-3009
> `transferWithAuthorization`) even though the README labels some method IDs
> `eip3009-usdc-*` — those are challenge method identifiers, not signing modes.
> EIP-3009 signing is explicitly listed as **roadmap** in the README and is
> absent from the source.  The EIP-712 sections in this document therefore
> describe what the roadmap would add, not what is shipped today.  See
> §10 (Open Questions) for details.

---

## Source files (all of mpp-remote's logic)

| File | Lines | Role |
|---|---|---|
| `bin/mpp-remote.mjs` | 1–312 | Entire implementation; no `src/` directory exists |
| `package.json` | — | Deps: `axios ^1.7.7`, `viem ^2.21.0`, `socks-proxy-agent ^8.0.4`, `https-proxy-agent ^7.0.5` |
| `package-lock.json` | — | Pins viem to `2.48.11` |

---

## 1. 402 Challenge Detection

`mpp-remote` treats a response as a payment challenge if and only if **all three**
of the following are true:

| Condition | Where checked | Source |
|---|---|---|
| The outgoing JSON-RPC `method` equals `"tools/call"` | `forward()`, condition branch | `bin/mpp-remote.mjs:244–245` |
| The response has `error.code === -32042` | `forward()`, condition branch | `bin/mpp-remote.mjs:245` |
| `error.data.challenges` is a non-empty array | guard before `settle()` | `bin/mpp-remote.mjs:248–250` |

Relevant code (`bin/mpp-remote.mjs:244–250`):

```js
async function forward(req) {
  const res = await post(req);
  if (req.method !== 'tools/call' || res?.error?.code !== -32042) {
    return res;                           // not a payment challenge
  }
  const challenges = res.error.data?.challenges;
  if (!Array.isArray(challenges) || challenges.length === 0) {
    return res;                           // malformed challenge, pass through
  }
  // ... settle and retry
```

**HTTP status code:** mpp-remote does not inspect the HTTP status code at all.
The axios instance is created with `validateStatus: () => true`
(`bin/mpp-remote.mjs:111`), so any HTTP status is accepted.  Detection is done
entirely on the JSON-RPC payload.  The "402" in the project name is conceptual;
no HTTP 402 check exists in the code.

**Non-`tools/call` requests:** All other JSON-RPC methods (e.g., `tools/list`,
`initialize`) are forwarded verbatim even if they carry a `-32042` error.  The
guard on line 244 (`req.method !== 'tools/call'`) causes them to short-circuit.

---

## 2. Challenge Payload Schema

The 402 challenge is a standard JSON-RPC 2.0 error response with the payment
data in `error.data`.  Source: `bin/mpp-remote.mjs:248` (`res.error.data?.challenges`)
and `bin/mpp-remote.mjs:252` (`settle(challenges[0])`).

### JSON-RPC envelope

```jsonc
{
  "jsonrpc": "2.0",
  "id": <same id as the request>,
  "error": {
    "code": -32042,
    "message": "<human-readable string, not parsed by mpp-remote>",
    "data": {
      "challenges": [ <Challenge>, ... ]
    }
  }
}
```

Only `challenges[0]` is ever used (`bin/mpp-remote.mjs:253`); the array
allows the server to offer multiple payment methods but mpp-remote picks the
first one it recognises.

### Challenge object

Fields read by `settle()` (`bin/mpp-remote.mjs:158–226`):

| Field | Type | Description | Source line |
|---|---|---|---|
| `amount` | string (decimal USD) | Charge amount, e.g. `"0.10"` | `:162` |
| `sku` | string | Opaque SKU identifier (logged only) | `:194` |
| `challenge_id` | string | Echoed back in the credential | `:223` |
| `opaque` | any | Opaque server token, echoed back unchanged | `:224` |
| `methods` | array of Method | Available payment methods | `:173` |

### Method object

| Field | Type | Description | Source line |
|---|---|---|---|
| `id` | string | Method identifier, see below | `:174` |
| `network` | string | EVM chain name, e.g. `"base-sepolia"` | `:184` |
| `currency` | string | Token symbol, e.g. `"USDC"` (logged) | `:194` |
| `currency_contract` | string (address) | ERC20 contract address | `:177`, `:207` |
| `currency_decimals` | number | Token decimals, e.g. `6` for USDC | `:207` |
| `recipient_address` | string (address) | Address to transfer tokens to | `:205` |

### Method `id` matching

`settle()` picks the first `Method` whose `id` satisfies any of these (checked
in order, `bin/mpp-remote.mjs:174–177`):

```
m.id?.startsWith('eip3009-usdc-')   // labeled EIP-3009; treated as plain ERC20 today
m.id?.startsWith('erc20-')
m.currency_contract                  // fallback: any method with a contract address
```

### Example challenge payload

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "error": {
    "code": -32042,
    "message": "Payment required",
    "data": {
      "challenges": [
        {
          "challenge_id": "ch_abc123",
          "sku": "upload-1mb",
          "amount": "0.10",
          "opaque": "srv-token-xyz",
          "methods": [
            {
              "id": "erc20-usdc-base-sepolia",
              "network": "base-sepolia",
              "currency": "USDC",
              "currency_contract": "0x036CbD53842c5426634e7929541eC2318f3dCF7e",
              "currency_decimals": 6,
              "recipient_address": "0xRecipientAddress0000000000000000000000"
            }
          ]
        }
      ]
    }
  }
}
```

---

## 3. EIP-712 Typed-Data Structure

**Not applicable to the current implementation.**

The current `settle()` function sends a plain ERC20 `transfer()` on-chain
transaction.  No EIP-712 domain, types, or message struct is constructed
anywhere in `bin/mpp-remote.mjs`.  The viem imports used are
`createWalletClient`, `encodeFunctionData`, `parseUnits`, and `getAddress`
(`bin/mpp-remote.mjs:34–40`) — none of the EIP-712 viem APIs
(`signTypedData`, `hashTypedData`, etc.) appear.

**Roadmap note:** The README and method ID prefix `eip3009-usdc-*` indicate
that a future version will use EIP-3009 `transferWithAuthorization`, which
requires an EIP-712 permit-style signature.  The EIP-3009 typed-data structure
(for reference — this is the standard, not something observed in mpp-remote
source) would be:

```
Domain:
  name:              <token name, e.g. "USD Coin">
  version:           "2"
  chainId:           <EIP-155 chain id>
  verifyingContract: <currency_contract address>

PrimaryType: "TransferWithAuthorization"

Types:
  TransferWithAuthorization:
    from:        address
    to:          address
    value:       uint256
    validAfter:  uint256
    validBefore: uint256
    nonce:       bytes32
```

**This is speculative / standards-derived, not sourced from mpp-remote code.**
Do not use it as an implementation target until EIP-3009 support lands.

---

## 4. Signature Encoding

**Not applicable to the current implementation.**  See §3.

The current implementation does not produce a signature.  The credential value
is the on-chain transaction hash returned by `wallet.sendTransaction()`
(`bin/mpp-remote.mjs:209`).

For the EIP-3009 roadmap path, a standard EIP-712 secp256k1 signature would be
`r || s || v` as 65 bytes (hex-prefixed), per Ethereum convention.  But this is
not confirmed by the source.

---

## 5. Header Name and Format

**There is no custom payment HTTP header in the current implementation.**

The credential is delivered as a JSON field inside the request body, not as an
HTTP header.  When retrying after settlement, `mpp-remote` replaces the
outgoing request's `params._meta` field (`bin/mpp-remote.mjs:255–262`):

```js
return await post({
  ...req,
  params: {
    ...req.params,
    _meta: {
      ...(req.params?._meta ?? {}),
      'org.paymentauth/credential': credential,
    },
  },
});
```

The only custom HTTP header ever sent by mpp-remote is `Mcp-Session-Id`
(standard MCP session tracking, `bin/mpp-remote.mjs:234`), which is unrelated
to payment.

### Credential field path

| Location | Value |
|---|---|
| JSON-RPC request body | `params._meta["org.paymentauth/credential"]` |

### Credential object shape (returned by `settle()`)

| Field | Type | Example | Source line |
|---|---|---|---|
| `method` | string | `"erc20-usdc-base-sepolia"` | `:222` |
| `challenge_id` | string | `"ch_abc123"` | `:223` |
| `opaque` | any | `"srv-token-xyz"` | `:224` |
| `settlement_tx_hash` | string (hex, `0x`-prefixed) | `"0xabc...def"` | `:225` |

---

## 6. Retry Semantics

After on-chain settlement, `mpp-remote` retries the original request with the
following behaviour (`bin/mpp-remote.mjs:253–263`):

- **Same HTTP session.** The retry uses the same `sessionId` (captured from
  the initial `initialize` response's `Mcp-Session-Id` header,
  `bin/mpp-remote.mjs:236–238`).  `post()` always sends the stored `sessionId`
  in the `Mcp-Session-Id` request header.

- **Same JSON-RPC `id`.** The retry spreads `...req` so `id`, `jsonrpc`, and
  `method` are identical to the original call (`bin/mpp-remote.mjs:255`).

- **Same `params`, plus credential.** Only `params._meta` is extended; all
  tool arguments in `params` are preserved (`bin/mpp-remote.mjs:256–261`).

- **Single retry only.** There is no loop.  If the retried call returns another
  `-32042`, it passes through to the caller as-is.

- **Idempotency.** Whether the retry is safe to replay depends on the server's
  tool implementation.  mpp-remote makes no idempotency guarantees and does
  not generate a new request ID.

- **On settlement failure.** If `settle()` throws (e.g., tx reverted, max
  amount exceeded, no matching method), `forward()` synthesises a `-32042`
  error and returns it to the stdio client with `data` copied from the
  original challenge response (`bin/mpp-remote.mjs:264–274`).

---

## 7. Wallet Derivation

`MPP_WALLET_PRIVATE_KEY` must be a `0x`-prefixed hex-encoded 32-byte
secp256k1 private key (`bin/mpp-remote.mjs:89`, `bin/mpp-remote.mjs:123`):

```js
const PK = process.env.MPP_WALLET_PRIVATE_KEY;
// ...
const account = PK ? privateKeyToAccount(PK) : null;
```

`privateKeyToAccount` is viem's standard account factory
(`bin/mpp-remote.mjs:41`).  viem derives the Ethereum address via the canonical
path:

1. Scalar multiply the private key by the secp256k1 generator to get the
   uncompressed 64-byte public key (without the `04` prefix).
2. keccak256 hash the 64 bytes.
3. Take the last 20 bytes as the Ethereum address.
4. EIP-55 mixed-case checksum the hex string.

This is the standard Ethereum address derivation — there is nothing custom
here.  Confirmed by viem 2.x source (`viem/accounts/privateKeyToAccount`);
no override code exists in mpp-remote.

The derived address is only used as the `account` field of the viem
`WalletClient`, which signs transactions with it.

---

## 8. Max-Amount Enforcement

**Parsing** (`bin/mpp-remote.mjs:90`):

```js
const MAX_AMOUNT = parseFloat(process.env.MPP_MAX_AMOUNT_USD ?? '1.0');
```

- Format: decimal USD string, e.g. `"0.50"` means fifty cents.
- Default: `1.0` (one US dollar) when the env var is absent.
- Parsed with JavaScript `parseFloat`; `"1."`, `"1"`, `"1.00"` all produce
  `1.0`.  Non-numeric strings produce `NaN`, which will cause every charge to
  fail the guard below (since `NaN > anything` is `false` — this is a latent
  bug: a bad env value silently disables the cap).

**Enforcement** (`bin/mpp-remote.mjs:162–170`):

```js
const amount = parseFloat(challenge.amount);
if (!Number.isFinite(amount)) {
  throw new Error(`invalid challenge.amount: ${challenge.amount}`);
}
if (amount > MAX_AMOUNT) {
  throw new Error(
    `charge ${challenge.amount} exceeds MPP_MAX_AMOUNT_USD=${MAX_AMOUNT}`,
  );
}
```

- The check is performed **before** any on-chain transaction is submitted.
- It compares parsed floating-point USD values directly.  No currency
  conversion occurs; `challenge.amount` is assumed to be in USD.
- If the amount exceeds the cap, `settle()` throws, and `forward()` returns a
  synthesised `-32042` error to the caller.

---

## 9. Fully Worked Example

This example traces one complete payment flow from the incoming stdio
JSON-RPC request to the retried request body.

### 9.1 Inputs

**Environment:**
```
MPP_WALLET_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
MPP_MAX_AMOUNT_USD=1.0
```
(This is the well-known Hardhat test key #0.  Never use on mainnet.)

Derived address (standard secp256k1 derivation):
`0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266`

**Initial MCP request (over stdio):**
```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "tools/call",
  "params": {
    "name": "upload_file",
    "arguments": { "filename": "screenshot.png" }
  }
}
```

### 9.2 Server's 402 response

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "error": {
    "code": -32042,
    "message": "Payment required",
    "data": {
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
              "recipient_address": "0xPaymentRecipient000000000000000000000001"
            }
          ]
        }
      ]
    }
  }
}
```

### 9.3 What mpp-remote does

1. **Detects** `-32042` on a `tools/call` request; finds non-empty `challenges`.
2. **Validates** `parseFloat("0.10") = 0.10 ≤ MAX_AMOUNT = 1.0` — OK.
3. **Picks method** `"erc20-usdc-base-sepolia"` (starts with `"erc20-"`).
4. **Resolves chain** `"base-sepolia"` → `chains.baseSepolia` (chainId 84532).
5. **Encodes calldata** for `transfer(0xPaymentRecipient…, 100000)` (0.10 USDC
   × 10^6 decimals = 100,000 raw units).
6. **Submits tx** to `0x036CbD53842c5426634e7929541eC2318f3dCF7e` (USDC on
   Base Sepolia) via the chain's default public RPC.
7. **Waits** for receipt; verifies `receipt.status === 'success'`.
8. **Builds credential:**
   ```json
   {
     "method": "erc20-usdc-base-sepolia",
     "challenge_id": "ch_abc123",
     "opaque": "srv-nonce-xyz789",
     "settlement_tx_hash": "0x<actual tx hash from chain>"
   }
   ```

### 9.4 Retried request body

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "tools/call",
  "params": {
    "name": "upload_file",
    "arguments": { "filename": "screenshot.png" },
    "_meta": {
      "org.paymentauth/credential": {
        "method": "erc20-usdc-base-sepolia",
        "challenge_id": "ch_abc123",
        "opaque": "srv-nonce-xyz789",
        "settlement_tx_hash": "0x<actual tx hash from chain>"
      }
    }
  }
}
```

### 9.5 Why there is no deterministic test vector

The settlement_tx_hash is produced by a real blockchain transaction.  Its
value depends on the chain state (nonce, gas price, block number) at the
time of execution.  **There is no offline-computable signature to test.**

For Swift unit tests, mock the network layer: intercept the `tools/call`
response to return a fake `-32042`, then assert that the retry contains the
expected `params._meta["org.paymentauth/credential"]` shape with the tx hash
your mock "transaction sender" returns.

---

## 10. Open Questions / Unknowns

### 10.1 No EIP-712 in the current implementation

The task description assumed this protocol used EIP-712 signed authorization
(e.g., `signTypedData`, `X-PAYMENT` header).  The mpp-remote source contains
**none of that**.  Specifically:

- No call to `signTypedData` or `hashTypedData`.
- No `TypedDataDomain` struct.
- No custom HTTP header for payment (`X-PAYMENT`, `X-Payment-Authorization`,
  etc.).
- No base64 or hex-encoded signature in any header.

The word "x402" in the keywords (`package.json:26`) refers to the broader
x402 payment ecosystem concept, not to an HTTP 402 or EIP-712 flow within
this codebase.

### 10.2 EIP-3009 roadmap

The README (`README.md:6`, `:105`) and method ID prefix `eip3009-usdc-*` both
refer to EIP-3009 `transferWithAuthorization` as a future payment mode.  When
implemented, it would allow the client to sign an off-chain authorization
rather than submit an on-chain transaction.  That flow **would** use EIP-712
typed data.  However:

- No code for it exists today.
- The domain, types, field names, and header/credential encoding for the
  EIP-3009 path are **unknown** and cannot be inferred from mpp-remote source.
- The server-side schema for accepting an EIP-3009 credential in
  `org.paymentauth/credential` is also unknown.

### 10.3 `org.paymentauth/receipt` schema unknown

The README (`README.md:38`) mentions that the success result carries
`result._meta["org.paymentauth/receipt"]` from the server, but `forward()`
passes the success response verbatim (`bin/mpp-remote.mjs:244`, early return).
The receipt schema is entirely server-defined and undocumented in mpp-remote.

### 10.4 `opaque` field meaning

The `opaque` field on the challenge is echoed back to the server verbatim in
the credential (`bin/mpp-remote.mjs:224`).  Its purpose and format are
server-defined.  mpp-remote never inspects it.

### 10.5 `sku` field not in credential

The `sku` field on the challenge is logged to stderr
(`bin/mpp-remote.mjs:194`) but is **not** echoed back in the credential
object.  If the server uses `sku` for routing/accounting, it must derive it
from `challenge_id` or the tx hash on its side.

### 10.6 No receipt caching / idempotency token

There is no nonce, timestamp, or idempotency key added by mpp-remote.  If a
retry is needed (e.g., transient network error after settlement), the client
would need to re-submit the same credential.  Whether the server accepts
repeated use of the same `settlement_tx_hash` is unknown.

### 10.7 NaN cap bug

If `MPP_MAX_AMOUNT_USD` is set to a non-numeric string (e.g., `"off"` or
`""`), `parseFloat` returns `NaN`, and `amount > NaN` is always `false`,
silently disabling the spending cap.  This is a latent bug in mpp-remote
(`bin/mpp-remote.mjs:90`, `:166–170`).

---

## Summary table: what Swift's PaymentClient must implement

| Concern | Current protocol | Source |
|---|---|---|
| Trigger condition | JSON-RPC error code `-32042` on a `tools/call` response | `:244–245` |
| Challenge location | `error.data.challenges[0]` | `:248–253` |
| Payment mechanism | On-chain ERC20 `transfer()` to `method.recipient_address` | `:201–212` |
| Credential delivery | `params._meta["org.paymentauth/credential"]` in retry body | `:255–262` |
| Credential fields | `method`, `challenge_id`, `opaque`, `settlement_tx_hash` | `:221–226` |
| HTTP session | Same `Mcp-Session-Id` as original request | `:234` |
| JSON-RPC `id` | Unchanged from original request | `:255` |
| EIP-712 signing | **Not implemented** (roadmap) | — |
| Custom HTTP headers | **None** (beyond `Mcp-Session-Id`) | — |
| Max-amount check | `parseFloat(challenge.amount) > parseFloat(MPP_MAX_AMOUNT_USD)` | `:162–170` |
| Network names | `"base"`, `"base-sepolia"`, `"mainnet"`, `"ethereum"`, `"sepolia"`, `"polygon"`, `"optimism"`, `"optimism-sepolia"`, `"arbitrum"` | `:129–139` |
