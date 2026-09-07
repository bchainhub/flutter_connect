# Changelog

## 0.1.0

Initial Connect v1 implementation, shared conformance vectors, security tests, examples and release automation.

- Add named chain presets, wallet adapters and extensible server verifiers for all fourteen requested chains, plus Bitcoin legacy and XRP Ed25519. Expand shared fixtures and live cross-language authentication tests.

- Use connect.js for browser-only authentication and wallet adapters. better-connect independently owns HTTP endpoints, backend state transitions and Better Auth sessions.

- Rename the browser wallet entry to connect.js/wallet; add brand-neutral discovery, Solana and CIP-30 adapters, TronLink-style signing and native wallet bridges. Add shared Core Blockchain Ed448/ICAN helpers and a future-wallet bridge with mainnet/Devin support.
