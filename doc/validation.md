# Implementation validation


## Desktop validation — 2026-11-03

The example now includes macOS, Linux and Windows runners. The desktop CI matrix runs analysis, package tests, example tests and a debug example build on each operating system. Linux CI installs GTK/CMake/Ninja dependencies; Windows CI makes OpenSSL available for the Ed448 fixture.

| Platform | Local result |
| --- | --- |
| macOS ARM64 | Analysis passed; 206 package tests and 2 example tests passed; debug app built |
| Linux ARM64 (Debian 12 Docker) | Analysis passed; 206 package tests and 2 example tests passed; debug app built |
| Windows | CI configured; not executed locally because no Windows runner or authenticated GitHub CLI was available |

Both local platforms used Flutter 3.47.2 and Dart 3.13.2. The 17 live-server cases are skipped in these standalone desktop runs; authenticated interoperability was verified separately in the 0.2.1 validation below. This validation does not exercise physical Bluetooth devices or Windows/Linux external URL registration. Workflow syntax passed actionlint. Windows and x86_64 Linux execution remains pending CI after pushing these changes.

## 0.2.1 validation — 2026-11-03

Dependency refresh rechecked on 2026-11-03: `flutter pub upgrade --major-versions` in both the library and example found no further upgrades. All direct and development dependencies are current; upstream/SDK-constrained transitive versions remain unchanged. Formatting, analysis, standalone/browser/example tests, authenticated interoperability, Android APK and iOS simulator builds, and a clean-snapshot publish dry run were repeated successfully.

Prepared locally with Flutter 3.47.2, Dart 3.13.2, and pana 0.23.19. No commits, tags, pushes, or publications were performed.

| Check | Result |
| --- | --- |
| Package version and release examples | 0.2.1; pub.dev still reports 0.2.0 as latest, and 0.2.1 is available |
| Formatting and static analysis | Passed; no source formatting changes or analyzer findings |
| Standalone Flutter tests | 206 passed; 17 server-dependent tests skipped here and exercised below |
| Chrome provider, action and discovery tests | 8 passed |
| Example tests | 2 passed |
| Local Better Auth interoperability runner | 18 Dart tests passed, including 17 completed authenticated sessions |
| Offline encrypted handoff interoperability | 18 Dart tests and 18 Node tests passed |
| Android example debug build | Passed |
| iOS simulator example debug build | Passed |
| Publish dry run from clean staging copy | Passed; zero warnings |
| Pana | 150/160 points |

Scoring breakdown: conventions 20/30, documentation 20/20, platforms 20/20, static analysis 50/50, dependencies 40/40. The existing CORE License is not recognized as an OSI license, accounting for the missing 10 points; it was not changed. Dartdoc completed with zero warnings/errors, and 142 of 509 public API elements have documentation comments (27.9%). The installed SDK's `dart doc` wrapper did not accept pana's full argument set; final scoring used the standalone dartdoc selected by pana instead.

All direct and development dependencies are at their latest published versions. The example now requires cryptography ^2.9.0, matching the library. No dependency overrides were added. Newer versions of bluez, dbus, material_color_utilities and test_api remain constrained by upstream packages or the Flutter SDK; the example additionally inherits qr's constraint from qr_flutter. Dependency resolution and pana's lower-bound analysis pass.

The normal worktree publish dry run reports modified Git files because release changes are uncommitted. A staging copy containing the current tracked and untracked, non-ignored release sources validates with zero warnings. Generated lockfiles remain ignored. Android's successful build emits an upstream bluetooth_low_energy_android Kotlin Gradle migration notice.

Commands used:

```sh
flutter pub upgrade --major-versions
flutter pub upgrade --major-versions --directory example
dart format --output=none --set-exit-if-changed lib test example/lib example/test
flutter analyze
flutter test --no-pub
flutter test --no-pub --platform chrome test/provider_actions_web_test.dart test/providers_web_test.dart test/wallet_discovery_web_test.dart
(cd example && flutter test --no-pub)
node ../better-connect/scripts/flutter-interop.mjs
(cd example && flutter build apk --debug --no-pub)
(cd example && flutter build ios --simulator --debug --no-pub)
flutter pub publish --dry-run
dart pub global run pana --json --flutter-sdk /path/to/flutter .
```

On this macOS host, tests used the Xcode macOS SDK through `SDKROOT`, and Android builds used Android Studio's bundled Java 21 through `JAVA_HOME`. Browser tests used the installed Chrome executable. Live interoperability uses a local test server and ephemeral test accounts; no production service or wallet transaction is exercised. This is not a physical-device Bluetooth or multi-device test. Pub.dev's public score updates only after publication and registry analysis.

## 0.1.1 validation — 2026-09-07 (historical)

Local pana 0.23.18 reports 150/160 points. Documentation scores 20/20 with 64 of 161 public API elements documented (39.8%); dependency support scores 40/40, including latest-version compatibility and lower-bound analysis. The remaining 10 points require an OSI-approved license; CORE License is intentionally retained unchanged.

The package now requires Flutter 3.44 and Dart 3.12 to support app_links 7.2.1. Static analysis, Flutter tests, and Android/iOS simulator builds pass. Registry scores will update only after this version is published and analyzed by pub.dev.


Implemented locally in flutter_connect, connect-protocol and better-connect. No commits, pushes, tags or registry publications were made in the target repositories.

## Results

| Check | Result |
| --- | --- |
| connect-protocol browser API/unit/conformance/lifecycle suite | 39 passed |
| Chromium browser and installed-package verification | All 17 proof fixtures, fresh Core flow, lifecycle checks and static example passed |
| better-connect cryptographic/security/SQLite/client suite | 54 passed |
| Flutter standalone suite | 27 passed; the 17 live-server cases run separately below |
| Live Flutter interoperability runner | 18 passed: repeated OpenSSL vector check plus 17 complete sign-in flows |
| Flutter example widget test | 1 passed |
| TypeScript checks, including inferred Better Auth client API | Passed |
| ESLint and Prettier checks | Passed |
| Dart formatting and Flutter analysis | Passed |
| Android debug APK and iOS simulator builds | Passed |
| Android emulator cold/warm custom-scheme dispatch | Passed; both delivered to Flutter URI validation |
| iPhone 17 Pro simulator cold/warm custom-scheme dispatch | Passed; cold invalid URI reached validation, warm canonical URI reached HTTPS retrieval and reported serverRejected for the deliberately nonexistent example.com endpoint |
| Identical vectors across three repositories | SHA-256 f244e3eefe4b8c64f85b74204a077f2d0bcdb89dde9579410ca7fecf24671d17 |
| SDK and plugin packaged installation | Passed, including all 17 proof fixtures, browser-only SDK packaging and the plugin's patched Node Monero dependency |
| pub.dev dry run | Passed with zero warnings from a clean temporary source snapshot |
| GitHub workflow YAML parsing | Passed |
| npm dependency audit during clean installation | Zero production advisories in installed package; development-only bitcoinjs-message has three low-severity transitive notices |

The Node suites now contain 39 SDK and 54 Better Auth tests; the removed standalone HTTP-server tests have been replaced by browser API and installed-package coverage. The OpenSSL vector case runs again in the integration runner. The normal Flutter command intentionally skips the live-server cases when no endpoint is supplied; all seventeen passed under better-connect/scripts/flutter-interop.mjs. Native device link tests and cryptographic server integration were exercised separately: the latter runs Dart on the host with an injected loopback test transport, not a deployed mobile HTTPS service.

Local toolchain: Node 24.2.0, Flutter 3.47.2 / Dart 3.13.2, OpenSSL 3.6.4, Better Auth 1.7.3. CI also defines a Node 22 job; that version's hosted CI execution has not been run locally. The direct pub dry run in the working tree warns about the intentionally uncommitted README; the clean snapshot check verifies release packaging without committing user changes.

## Delivered architecture and support

connect-protocol owns the browser-only API, strict v1 schemas, canonicalization, wallet adapters and local signature verification. It has no server, HTTP dapp client or request store. better-connect owns the backend request engine, Node Monero loading, persistent adapter storage, HTTP endpoints and Better Auth session cookies. Flutter ports the wallet protocol to Dart and adds app_links lifecycle integration. Shared vectors verify canonical bytes across all three packages.

Named presets and built-in verification cover Core Blockchain, Ethereum, Polygon, Base, Bitcoin, Solana, BNB Smart Chain, TRON, Monero, Stellar, Litecoin, XRP, Zcash and Cardano, plus alternate Bitcoin legacy and XRP Ed25519 methods. Raw Ed25519 remains supported. [chains.md](chains.md) specifies address limits and encoding rules. Tests cover every chain through real signature verification, unrelated-key substitution, message-field changes, network/algorithm mismatches and one-time redemption. Additional checks use the official Core and Stellar vectors, independent Emurgo CIP-8 signing, Cardano protected-header and credential tampering, and rejection of Monero view-key authentication.

The live runner uses native OpenSSL for Core, Dart Ed25519 for the raw-key fixture, and test-only host-wallet bridges for the other chain methods. All seventeen paths traverse the Dart wallet lifecycle and actual Better Auth session creation. They do not claim integration with every mobile wallet or hardware device. Earlier native Android/iOS build and link checks remain applicable; this expansion changes protocol adapters and verification, not platform registration.

The URI is connect://<lowercase-domain>/connect/v1/<64-hex-request-id>; see protocol.md for exact schemas, signing semantics, endpoint routes, security boundaries and errors, and platforms.md for Android/iOS registration.

## Deployment prerequisites and limits

- Configure registry ownership/trusted publishing before using release tags. Cross-repository CI requires access to the sibling repository; private repositories need an appropriately scoped checkout credential.
- Host wallets provide signing adapters, including mobile Ed448/native key management. The OpenSSL fixture is only a test-host bridge.
- The local core/raw namespace labels are not claimed as registered CAIP namespaces. Confirm a future official XCB namespace before changing the versioned protocol mapping.
- ERC-1271, script/multisignature account authority, automatic callbacks, and address types outside the explicit chain table are unsupported.
- The default database path is tested against real SQLite. Other Better Auth adapters must preserve conditional updates and unique constraints; run their database integration tests before deployment. Session-creation failure after consumption requires a new sign-in request.
- Universal/App Link domain associations require the host's real domain, signing identities and deployed association files. These domain-verification flows and physical hardware signers were not exercised.

Browser coverage includes local request creation, EIP-1193 account and chain checks before/after signing, origin binding, expiry, cancellation and single-use verification. The installed tarball is exercised in Chromium with networking and persistent storage disabled. All seventeen verifier fixtures run through the browser API and through Better Auth's independently owned backend. Package checks assert that server files, request-store APIs and the server/dapp/browser entry points are absent.
