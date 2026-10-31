import 'dart:async';
import 'dart:math';
import 'operations.dart';
import 'protocol.dart';
import 'provider_platform_stub.dart'
    if (dart.library.js_interop) 'provider_platform_web.dart'
    as platform;

/// Blockchain families used for provider routing and compatibility globals.
enum Blockchain {
  core,
  ethereum,
  solana,
  bitcoin,
  litecoin,
  cardano,
  aptos,
  ton,
  near,
  monero,
  zcash,
}

const defaultProviderIcon =
    'data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2296%22%20height%3D%2296%22%3E%3Crect%20width%3D%2296%22%20height%3D%2296%22%20rx%3D%2220%22%20fill%3D%22%232458db%22%2F%3E%3Cpath%20d%3D%22M66%2028H42a20%2020%200%200%200%200%2040h24%22%20fill%3D%22none%22%20stroke%3D%22white%22%20stroke-width%3D%2210%22%2F%3E%3C%2Fsvg%3E';

typedef CIP6963ProviderInfo = ProviderInfo;
typedef EIP6963ProviderInfo = ProviderInfo;

/// Public wallet identity announced during CIP-6963 or EIP-6963 discovery.
class ProviderInfo {
  final Map<String, Object?> extra;
  final String uuid, name, rdns, icon;
  final String? iconUrl;
  ProviderInfo({
    String? uuid,
    this.name = 'Connect Wallet Protocol',
    this.rdns = 'connect.wallet',
    this.icon = defaultProviderIcon,
    this.iconUrl,
    Map<String, Object?> extra = const {},
  }) : uuid = uuid ?? _uuid(),
       extra = Map.unmodifiable(extra) {
    if (!RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          caseSensitive: false,
        ).hasMatch(this.uuid) ||
        name.isEmpty ||
        name.length > 256 ||
        rdns.length > 253 ||
        !RegExp(
          r'^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$',
          caseSensitive: false,
        ).hasMatch(rdns)) {
      throw ArgumentError('Invalid provider identity');
    }
    if (icon.length > 262144 ||
        !RegExp(
          r'^(data:image/|https://|ipfs://)',
          caseSensitive: false,
        ).hasMatch(icon) ||
        (iconUrl != null &&
            !RegExp(
              r'^(https://|ipfs://)',
              caseSensitive: false,
            ).hasMatch(iconUrl!))) {
      throw ArgumentError('Invalid provider icon');
    }
  }
  Map<String, Object?> toJson() => {
    ...extra,
    'uuid': uuid,
    'name': name,
    'rdns': rdns,
    'icon': icon,
    if (iconUrl != null) 'iconUrl': iconUrl,
  };
}

String _uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Binds a blockchain identity to an operation transport.
class BlockchainRoute {
  final OperationChain chain;
  final OperationTransport transport;
  BlockchainRoute({required this.chain, required this.transport});
}

/// Chain-specific params pass unchanged through the existing operation transport.
class UniversalProvider {
  final Map<Blockchain, BlockchainRoute> routes;
  Blockchain defaultBlockchain;
  UniversalProvider({
    required Map<Blockchain, BlockchainRoute> routes,
    this.defaultBlockchain = Blockchain.core,
  }) : routes = Map.unmodifiable(routes);
  Future<Object?> request({
    required String method,
    Map<String, Object?> params = const {},
    Blockchain? blockchain,
    WalletIdentity? account,
  }) async {
    final route = routes[blockchain ?? defaultBlockchain];
    if (route == null) throw OperationException('UNSUPPORTED_CHAIN');
    final response = await requestOperation(
      route.transport,
      ConnectOperation(
        operation: method,
        chain: route.chain,
        account: account,
        params: params,
      ),
    );
    if (response.error != null) throw OperationException(response.error!.code);
    return response.result;
  }

  Future<Object?> operation(
    String method, {
    Map<String, Object?> params = const {},
    Blockchain? blockchain,
    WalletIdentity? account,
  }) => request(
    method: method,
    params: params,
    blockchain: blockchain,
    account: account,
  );
}

typedef ProviderRequest =
    Future<Object?> Function(String method, Object? params);

class InjectedProvider {
  final ProviderInfo info;
  final ProviderRequest request;
  final Stream<ProviderEvent>? events;

  /// Override only for a host-defined discovery protocol on other chains.
  final String? discoveryPrefix;
  InjectedProvider({
    ProviderInfo? info,
    required this.request,
    this.events,
    this.discoveryPrefix,
  }) : info = info ?? ProviderInfo();
}

/// Browser only. Native wallets use UniversalProvider through their host transport.
void Function() injectProviders({
  required Map<Blockchain, InjectedProvider> providers,
  required UniversalProvider connect,
}) {
  if (providers.values.map((p) => p.info.uuid).toSet().length !=
      providers.length) {
    throw ArgumentError('Provider instances require distinct UUIDs');
  }
  for (final entry in providers.entries) {
    if (entry.key == Blockchain.ethereum &&
        !entry.value.info.icon.toLowerCase().startsWith('data:image/')) {
      throw ArgumentError('EIP-6963 requires a data image icon');
    }
  }
  return platform.injectProviders(providers, connect);
}

class ProviderEvent {
  final String name;
  final List<Object?> arguments;
  ProviderEvent(this.name, [List<Object?> arguments = const []])
    : arguments = List.unmodifiable(arguments);
}
