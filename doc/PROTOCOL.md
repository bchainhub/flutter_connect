# Connect protocol v1

`connect://` is the primary transport URI. The Connect authentication protocol itself is transport-independent. HTTPS, Universal Links, App Links, wallet-specific schemes and direct invocation carry the same public request identity.

## Wire format

The primary app handoff embeds the challenge and pairing key in a URI fragment and needs no server lookup. See [nearby and offline transport](NEARBY.md). Canonical signature bytes remain unchanged. The short-URI HTTP lookup below is an optional Better Auth compatibility transport.

`connect://example.com/connect/v1/<requestId>` maps to `https://example.com/api/auth/wallet-connect/challenge?requestId=<requestId>`.

The HTTPS alternative is `https://example.com/connect/v1/<requestId>`. Domains must be lowercase ASCII DNS names, with at least two labels. Punycode is permitted and displayed literally. Ports, IP literals, credentials, fragments on short lookup URIs, queries, percent escapes, trailing dots, path normalization and whitespace are rejected. Local servers are supported only through an explicitly injected test transport/network, never by disabling TLS validation. The Better Auth base URL must be exactly `<origin>/api/auth`.

IDs and nonces are 32 random bytes encoded as 64 lowercase hex characters. Redemption secrets use the same entropy but are separate credentials. A challenge is a strict object containing `version: 1`, `requestId`, `nonce`, `domain`, `origin`, `issuedAt`, `expiresAt`, and `requirements`. Times are UTC `YYYY-MM-DDTHH:mm:ss.sssZ`, with a maximum lifetime of five minutes and 30 seconds of allowed issuance clock skew. Each requirement contains `namespace`, `reference`, `profile`, and `alg`. `alg` is an integer or explicit JSON null. Unknown fields are rejected.

A proof contains `requestId`, `account: { namespace, reference, address }`, `profile`, `alg`, `signature`, and optional `publicKey`. The verifier loads its stored challenge and never accepts a client-supplied nonce, message, domain or expiration. EdDSA keys/signatures are lowercase hex without `0x`; Ethereum signatures are `0x`-prefixed lowercase hex; BIP-322 simple signatures are canonical padded Base64.

The canonical message is UTF-8, LF-separated, with no trailing LF, BOM, JSON serialization or Unicode normalization. For non-Ethereum profiles:

```text
Connect Authentication
Version: 1
Domain: <domain>
URI: <origin>
Account: <namespace>:<reference>:<address>
Profile: <profile>
Algorithm: <signed decimal integer or none>
Nonce: <nonce>
Request ID: <requestId>
Issued At: <issuedAt>
Expiration Time: <expiresAt>
```

Ethereum uses an ERC-4361 message constructed by `canonicalMessage`, with the same fields and Connect version/profile/algorithm/account bindings in Resources. Its fixed statement is `Approve this Connect sign-in request.`. See `test/fixtures/conformance.json` for the exact bytes of every profile. Requirements select acceptable identities before signing; the selected identity/profile/algorithm are signed, while the server independently enforces its stored policy.

## Profiles

The original profiles below remain stable. [Chain profiles and adapters](CHAINS.md) specify the expanded set, named presets, and extension APIs.

| Profile | Namespace / reference | Algorithm | Identity verification |
| --- | --- | --- | --- |
| `xcb-ed448` | local `core` / `1` (mainnet), `3` (Devin) | Ed448, COSE -53 | Ed448 signature plus SHA3-256(publicKey) last 20 bytes, cb/ab network prefix and ICAN checksum |
| `raw-ed25519` | local `raw` / `ed25519` | Ed25519, COSE -19 | Address is the exact 32-byte public key in lowercase hex; strict RFC8032 verification |
| `ethereum-siwe` | CAIP `eip155` / decimal chain ID | null | ERC-4361 message signed with EIP-191; recovered EOA equals the EIP-55 address |
| `bitcoin-bip322-p2wpkh` | CAIP `bip122` / `000000000019d6689c085ae165831e93` | null | Mainnet BIP-322 simple native P2WPKH, compressed key and SIGHASH_ALL |

The local `core` and `raw` namespaces are explicitly protocol-local identifiers, not claims of CAIP registration. The raw-key profile does not claim to implement Solana or another Ed25519 chain. XCB uses pure RFC8032 Ed448 over these exact canonical bytes (empty context); do not pass the bytes to a Core wallet API that adds a personal-message prefix or hashes them again. This is an explicit Connect signing method, not an alias for Core transaction signing. Address derivation is checked against a go-core reference vector. Host wallets using CIP-98 derived keys need a compatible native signer; private keys never enter the SDK API.

Ethereum personal_sign is not generic COSE ES256K. Contract accounts/ERC-1271 are currently rejected by the EOA profile. The BIP-322 profile rejects P2SH, P2TR and arbitrary scripts. A separate `bitcoin-signmessage` profile supports legacy P2PKH. See [chain profiles](CHAINS.md) for all additional networks, exact wrappers, proof encodings and address limits. Future profiles must define full canonical signing and key/account verification semantics; they cannot weaken an existing profile.

## Endpoints and lifecycle

All paths below are relative to `/api/auth/wallet-connect`.

| Method/path | Input | Result |
| --- | --- | --- |
| POST `/create` | `{}`; exact relying-party Origin header | requestId, connectUri, redeemSecret, expiresAt |
| GET `/challenge` | requestId query | pending challenge |
| GET `/status` | requestId query | requestId and status only |
| POST `/approve` | proof | requestId and APPROVED; no session/cookie |
| POST `/redeem` | requestId and redeemSecret; exact Origin header | success and user ID; Better Auth session cookie |
| POST `/deny` | requestId and redeemSecret; exact Origin header | requestId and DENIED |

Server: PENDING -> APPROVED -> CONSUMED; PENDING -> DENIED; PENDING/APPROVED -> EXPIRED. Conditional database updates choose exactly one winner. Browser polling is sufficient; the status API can later be backed by SSE/WebSocket notifications without altering proofs.

Wallet: awaitingUserApproval -> signing -> submitting -> approved, or rejected/cancelled/expired/failed. Resolving/fetching is represented by the pending resolve Future/Promise. Opening a URI never signs. Confirmation shows validated origin/domain, identity, network, profile and expiration. Expiration is checked immediately before signing and submission. Cancellation while a hardware signer is running suppresses submission after it returns; cancellation cannot undo a proof already submitted. In-memory duplicate tracking lasts for the client instance. A local wallet rejection does not remotely deny a public QR: only the initiating browser can call deny. Local rejection/cancellation does not revoke an already-approved request.

## Security boundary

A wallet address is a claim. Authentication is established only when the server verifies that the signing key corresponds to that claimed account.

Client-supplied wallet addresses and public keys are untrusted. A user is authenticated only after the server cryptographically verifies the signature and establishes that the signing key corresponds to the claimed blockchain account.

A QR contains only a public request identifier. It never contains a redemption secret, signature, private key or session token. The phone authorizes a fresh desktop session; it never transfers its own session. The desktop must retain its secret privately until redemption. Do not place it in URLs, analytics, browser history or logs. Clear it after completion. Public challenge/status responses do not disclose the approved identity.

TLS origin matching prevents silently signing for a different relying party. It does not prove that a displayed QR came from the intended desktop; an attacker can relay a QR for the same legitimate site. The wallet must make cross-device authorization explicit, and users must scan their own initiating browser. No arbitrary callbacks/return URLs are accepted in v1. Same-device login follows the identical flow, with the browser retaining its secret and the user returning manually.

Wallet HTTP requests omit cookies (TypeScript), reject redirects, time out after 15 seconds, and cap response bytes at 16 KiB. Dart's default native http client has no cookie jar; injected clients must preserve that property. No private keys or raw authentication material are logged by the packages. Error codes are stable strings without raw server/signer errors. Configure server body limits and Better Auth rate limiting at deployment. Browser wallet hosts should explicitly configure trusted origins/CORS where necessary; native clients do not require browser CORS.

## Conformance

`test/fixtures/conformance.json` is identical in all repositories. It contains public deterministic test seeds for EdDSA, proofs, complete canonical strings and hex bytes. Never use these seeds for assets or production authentication. The server tests verify every built-in profile, wrong-key injection, mutation, replay, expiry and concurrent redemption. `scripts/flutter-interop.mjs` in better-connect starts an isolated real Better Auth/SQLite server and runs all seventeen chain/method combinations through the full QR/approval/redemption flow, using Dart Ed25519, native OpenSSL Ed448 and test host-wallet bridges for the other methods.
