# Connect reference wallet

Run `flutter pub get` and `flutter run` on Android/iOS. The example registers `connect://`, receives cold/warm links, and accepts QR-decoded or pasted URI text through its input field. It displays validated relying-party and account information and signs only after the Approve button is pressed.

The example uses a freshly generated in-memory Ed25519 account. Configure better-connect with `{ namespace: 'raw', reference: 'ed25519', profile: 'raw-ed25519', alg: -19 }`. The key is lost when the application restarts; this is a test wallet, not a persistent account manager.

For Core and Ethereum wallets, replace DemoAccounts with your native account provider as described in the package README. XCB signs pure canonical Ed448 bytes; Ethereum uses personal_sign over the canonical SIWE bytes. Do not put private keys in application configuration or source files.

Platform registration and HTTPS association instructions are in [PLATFORMS.md](../doc/PLATFORMS.md). `flutter test` runs the initial-screen widget test. The sibling better-connect integration runner exercises actual Dart signatures and desktop session redemption.
