# Flutter platform integration

Create `ConnectLinks` early after `WidgetsFlutterBinding.ensureInitialized()`, subscribe to `client.requests`, and call `links.start()`. The helper receives both cold-start and running-app links using app_links raw-string APIs. It suppresses duplicate delivery of the same string; the client additionally rejects already-handled requests. Call `links.dispose()` and `client.dispose()` when the owner is destroyed. QR scanners and clipboard UI pass their decoded text to `client.resolve(text)`; no scanner or clipboard dependency is imposed.

## Android

Inside the wallet activity in AndroidManifest.xml:

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
<intent-filter>
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="connect" />
</intent-filter>
```

Add the INTERNET permission at the manifest root. Keep the activity exported for link dispatch and use singleTop launch mode. The checked-in example includes this configuration. Test cold and warm dispatch with `adb shell am start -W -a android.intent.action.VIEW -d 'connect://example.com/connect/v1/<64-hex-id>'`.

For verified App Links, add a separate autoVerify HTTPS intent filter scoped to your domain and `/connect/v1/`, and serve `/.well-known/assetlinks.json` with the real application ID and SHA-256 release-signing certificate fingerprint. Keep custom-scheme and verified HTTPS filters separate. Do not use placeholder association files in production.

## iOS

In Runner/Info.plist:

```xml
<key>FlutterDeepLinkingEnabled</key><false/>
<key>CFBundleURLTypes</key>
<array><dict>
  <key>CFBundleURLName</key><string>your.wallet.connect</string>
  <key>CFBundleURLSchemes</key><array><string>connect</string></array>
</dict></array>
```

Test with `xcrun simctl openurl booted 'connect://example.com/connect/v1/<64-hex-id>'`. Universal Links also require an Associated Domains entitlement `applinks:your.domain` and a served `/.well-known/apple-app-site-association` file associating your Team ID and Bundle ID with `/connect/v1/*`. Actual domain ownership, signing identities and installed-device association must be verified by the host application.

## Multiple wallets and other platforms

Custom schemes do not establish app ownership. Android may show a resolver, apply a saved default or follow OS routing policy; iOS does not guarantee a chooser or deterministic routing between apps registering the same scheme. `connect://` is not a secure universal wallet chooser. The protocol and OS dispatch are separate concerns. Prefer domain-verified links for app ownership, or an explicitly selected wallet-specific scheme via `UriTransport(schemes: {'mywallet'})`.

Core parsing, canonicalization and wallet state are portable to Flutter desktop/web. app_links platform registration and application lifecycle differ across macOS, Windows and Linux; the example targets Android/iOS only. Browser CORS, forbidden redirects and secure origin access also apply to Flutter web. Hardware-backed keys need host-native bridges; the package does not export private signing keys. Dart cryptography supplies the example's Ed25519; XCB Ed448 is delegated to a native wallet signer. The OpenSSL bridge in tests is a desktop conformance fixture, not a mobile key-management implementation.

## Troubleshooting

`invalidUri`: use exact lowercase syntax, no query, ports, IP addresses or whitespace. `domainMismatch`: align the QR, TLS endpoint, challenge origin and server baseURL. `noCompatibleAccount`: configure a requirement matching the wallet's namespace, network, profile and algorithm. `expiredRequest`: create a new request and check device clocks. `replayedRequest`: reuse the existing request UI rather than reopening its URI. `serverRejected`: inspect safe server error codes and verify the wallet is signing canonical bytes without an extra prefix/hash. Unverified HTTPS links may open the browser; registration and association files belong to the host app, not the protocol package.

Sources: [Flutter deep links](https://docs.flutter.dev/ui/navigation/deep-linking), [Android link dispatch](https://developer.android.com/training/app-links/create-deeplinks), [Apple custom schemes](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app).

## Nearby Bluetooth

Android requires minSdk 24. Add `BLUETOOTH_ADVERTISE` and `BLUETOOTH_CONNECT` to the manifest, plus legacy `BLUETOOTH` and `BLUETOOTH_ADMIN` with `android:maxSdkVersion="30"`. The peripheral requests runtime permission when starting. iOS and macOS require `NSBluetoothAlwaysUsageDescription`; macOS also needs its Bluetooth entitlement if sandboxed. The example includes Android/iOS configuration. Keep the app foregrounded for advertising; background operation is not implemented.

Check `ConnectBluetoothPeripheral.isSupportedPlatform` before constructing it. Show and confirm the requested origin before calling `start()`, publish `request.response` only after approval, and call `stop()` on cancellation or disposal. A full handoff URI intentionally carries a fragment; the legacy short lookup URI does not. See [wire framing and fallback channels](NEARBY.md).
