# flutter_connect

Flutter wallet library for Connect v1. Handles full `connect://` links and QR text for any dapp; validates the challenge, asks the user to approve signing, and returns an encrypted proof through Bluetooth or another channel. Better Auth is optional. See [nearby integration](doc/nearby.md).

```yaml
dependencies:
  flutter_connect: ^0.2.0
```

```dart
final connect = ConnectClient(
  accountProvider: myWalletAccountProvider,
);
connect.requests.listen((request) {
  // Present domain/origin, account, network, profile and expiry in trusted UI.
});
final request = await connect.resolve(scannedQrText);
// From an explicit Approve button only:
await request.approve(request.compatibleAccounts.first);
```

A `WalletAccountProvider` returns `WalletAccount` objects with a `SigningSelection` and `sign(Uint8List canonicalPayload)`. The selection contains `WalletIdentity(namespace, reference, address)`, profile and COSE algorithm (or null). Signatures are returned as `WalletSignature`; private keys remain inside the account implementation. `ConnectRequest` exposes immutable `challenge`, `compatibleAccounts`, `state`, `approve`, `reject` and `cancel`.

```dart
class XcbAccount implements WalletAccount {
  @override
  final SigningSelection selection;
  final Future<WalletSignature> Function(Uint8List) nativeSign;
  XcbAccount(String address, this.nativeSign)
      : selection = SigningSelection(
          account: WalletIdentity(namespace: 'core', reference: '1', address: address),
          profile: 'xcb-ed448', alg: coseEd448);
  @override
  Future<WalletSignature> sign(Uint8List payload) => nativeSign(payload);
}
```

The native XCB signer must use pure Ed448 over the supplied bytes, without extra hashing/prefixing, and return a 57-byte public key plus 114-byte signature as lowercase hex. An Ethereum adapter selects `eip155`, decimal chain reference, an EIP-55 address, `ethereum-siwe`, and null algorithm; it passes the canonical bytes to EIP-191 personal_sign. Bitcoin selects `bitcoin-bip322-p2wpkh` with its BIP122 reference and signs using BIP-322 simple. The host implements wallet signing; the SDK encrypts responses without receiving private signing keys.

```dart
WidgetsFlutterBinding.ensureInitialized();
final links = ConnectLinks(client: connect, onError: showSafeError);
await links.start(); // cold-start and running-app links
// On owner disposal: await links.dispose(); await connect.dispose();
```

Register Android/iOS schemes using [platform setup](doc/platforms.md); the checked-in [example](example) includes the required manifest/plist entries and an ephemeral Ed25519 account with a native confirmation screen. QR scanners, clipboard controls and navigation remain host-app choices. For direct invocation use `resolveTarget(ConnectTarget(origin, requestId))`. HTTPS/Universal/App Links resolve to identical canonical bytes. Same-device login uses the same protocol and manual return to the browser; arbitrary callback URLs are rejected.

A full handoff needs no `ConnectNetwork`. Short-URI HTTP compatibility requires explicitly passing `network: HttpsNetwork()`. `responseReady` means the proof is ready to return, not that portal sign-in succeeded.

```dart
// After showing and confirming request.challenge.origin:
final peripheral = ConnectBluetoothPeripheral(
  handoff: request.handoff!, onError: showSafeError,
);
await peripheral.start();
// From an explicit signing approval:
await request.approve(request.compatibleAccounts.first);
peripheral.publish(request.response!);
// On cancellation/disposal: await peripheral.stop();
```


Named presets cover Core Blockchain, Ethereum, Polygon, Base, Bitcoin, Solana, BNB Smart Chain, TRON, Monero, Stellar, Litecoin, XRP, Zcash and Cardano. Use `ChainWalletAccount(chain: ConnectChains.solana, address: address, sign: callback)` to avoid configuring low-level profiles. See [supported addresses and wallet methods](doc/chains.md). Full details are in the [protocol](doc/protocol.md) and [research notes](doc/implementation.md).

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test example/lib example/test
flutter analyze
flutter test
cd example && flutter test
# From the sibling better-connect checkout:
node scripts/flutter-interop.mjs
```

Shared vectors assert identical Dart/TypeScript messages. Dart Ed25519 signatures and an OpenSSL Ed448 host bridge also complete real Better Auth desktop sessions. The OpenSSL fixture requires OpenSSL 3 on the test host; it is not a mobile signing implementation. The standalone suite skips live-server tests unless the integration runner supplies its test endpoint.

See [release setup](doc/release.md). Licensed under the [CORE License](LICENSE).

This package is distributed under the [CORE License](LICENSE). It is not an OSI-approved license.

# Wallet Operations

Connect transports signing requests; the host wallet owns and uses the private key.

`ConnectOperation`, `OperationResponse`, `OperationCapability` and `OperationDispatcher` implement the canonical connect-protocol operation format. Chain adapters validate native payloads and declare capabilities. Wallet/custom operations require explicit host approval; read-only chain operations use separate handlers. Existing account providers supply identities without exposing keys or invoking authentication signers.

See the [operation protocol and API guide](doc/operations.md) and [EVM, Bitcoin PSBT, Solana, Core and balance examples](example/lib/operations.dart). `OperationTransport` handles host messaging, and `OperationCipher` optionally encrypts requests/responses. Existing authentication, links and handoffs remain unchanged.

## Wallet address validation

`validateWalletAccount` checks addresses against an explicit Connect namespace/reference and returns `valid`, `invalid`, or `unsupported`. `isValidWalletAccount` accepts only `valid`. These checks supplement wallet ownership verification. See [coverage, adapter integration and package compatibility](doc/wallet_validation.md).

### Universal operations and browser provider discovery

`UniversalProvider` routes the existing Connect operations by a default blockchain
or a per-call override. Native Flutter apps use this API through their existing
`OperationTransport`; browser builds can also inject native blockchain providers.

```dart
final connect = UniversalProvider(
  defaultBlockchain: Blockchain.core,
  routes: {
    Blockchain.core: BlockchainRoute(
      chain: OperationChain('core', '1'), transport: coreTransport),
    Blockchain.ethereum: BlockchainRoute(
      chain: OperationChain('eip155', '1'), transport: evmTransport),
  },
);
await connect.operation(OperationMethods.getAccounts);
await connect.operation(OperationMethods.getBalance,
  blockchain: Blockchain.ethereum, params: {'address': address});
// A call override does not change the default.
connect.defaultBlockchain = Blockchain.ethereum;

// Browser only: handlers implement the corresponding chain's native provider API.
final dispose = injectProviders(connect: connect, providers: {
  Blockchain.core: InjectedProvider(
    info: ProviderInfo(
      name: 'Connect Wallet Protocol', // default
      rdns: 'connect.wallet', // default
      icon: 'ipfs://CID/icon.webp',
      iconUrl: 'https://wallet.example/icon.png',
      extra: {'blockchain': 'core'},
    ),
    request: coreNativeRequest,
    // Optional Stream<ProviderEvent> forwards on/removeListener events to JS.
  ),
});
// On teardown: dispose();
```

All `OperationMethods` work through `request`/`operation`: account listing, message,
transaction, typed data and PSBT signing, sending, switching/adding chains, batch
transaction signing, balances, transactions, blocks, fee estimation and calls.
Params/results remain chain-specific; signing requires an explicit `account`.
The existing dispatcher retains approval, capability and validation checks.
No native RPC translation or implicit authorization occurs during discovery.

Browser globals identify **blockchains, never specific wallets**: `window.core`,
`window.ethereum` (all EVM networks), `window.solana`, `window.bitcoin`,
`window.litecoin`, `window.cardano`, `window.aptos`, `window.ton`, `window.near`,
`window.monero`, and `window.zcash`.
Only supplied blockchains are installed. `window.connect.request({method, params,
blockchain?, account?})` exposes universal routing. Existing globals are preserved.

Core uses `cip6963:announceProvider` / `cip6963:requestProvider`; Ethereum uses
`eip6963:announceProvider` / `eip6963:requestProvider` per
[EIP-6963](https://eips.ethereum.org/EIPS/eip-6963). Each `InjectedProvider` gets a
stable generated UUIDv4 and embedded icon by default, with configurable metadata.
Ethereum icons must be data image URIs; Core also accepts HTTPS/IPFS. Metadata and
announcement details are frozen in JS. Discovery never calls the request handler.
Use distinct UUIDs for distinct providers. Other chains can specify a custom
`discoveryPrefix`; these prefixes are host-defined, not standardized 6963 protocols.
Metadata is untrusted display data. The library does not fetch remote icons.

### Native universal wallet API

`UniversalWalletProvider` adds named native operations, provider selection, active
connection state, capabilities and typed errors. `UniversalProvider` retains the
existing Connect operation-transport API.

```dart
final discovery = installWalletProvider(adapters: nativeSdkAdapters);
final api = discovery.api;
// Render getProviders() and connect only after an explicit wallet selection.
await api.connect(options: WalletCallOptions(
  blockchain: Blockchain.core, providerId: selectedProviderId));
final accounts = await api.getAccounts();
// A call override does not change the active connection:
await api.getBalance(options: const WalletCallOptions(blockchain: Blockchain.solana));
// Teardown: discovery.dispose();
```

Native apps supply SDK adapters; browser builds also discover window providers and
install `window.connect` when absent. See [provider documentation](doc/wallet-provider.md),
[examples](doc/examples.md) and [actual capabilities](doc/blockchains.md).

Ethereum and Core also support opt-in transaction signing, fee estimates, preparation,
simulation, receipt waiting, token/contract operations and deployment calldata. Both
chains have local ABI codecs, including arrays and tuples; Ethereum EOA message
verification is local. Configure the selected wallet's `ethereumRpcMethods` or
`coreRpcMethods`. See [current support](doc/blockchains.md) and
[contracts](doc/smart-contracts.md) for native formats and remaining limits.
