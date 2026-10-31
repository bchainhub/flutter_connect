import 'providers.dart';
import 'wallet_provider.dart';
import 'wallet_discovery_stub.dart'
    if (dart.library.js_interop) 'wallet_discovery_web.dart'
    as platform;

class NativeWalletConfiguration {
  final Iterable<String>? rpcMethods;
  final Iterable<String> networks;
  final Map<WalletMethod, WalletHandler> handlers;
  final void Function(Object?, WalletMethod)? validateTransaction;
  const NativeWalletConfiguration({
    this.rpcMethods,
    this.networks = const [],
    this.handlers = const {},
    this.validateTransaction,
  });
}

class WalletDiscovery {
  final UniversalWalletProvider api;
  final void Function() refresh, dispose;
  final bool installed;
  WalletDiscovery({
    required this.api,
    required this.refresh,
    required this.dispose,
    this.installed = false,
  });
}

/// Native apps register their SDK adapters; browser builds also discover window providers.
WalletDiscovery discoverWalletProviders({
  Iterable<WalletAdapter> adapters = const [],
  NativeWalletConfiguration Function(Blockchain, String)? configure,
  bool install = false,
}) => platform.discoverWalletProviders(
  adapters: adapters,
  configure: configure,
  install: install,
);
WalletDiscovery installWalletProvider({
  Iterable<WalletAdapter> adapters = const [],
  NativeWalletConfiguration Function(Blockchain, String)? configure,
}) => discoverWalletProviders(
  adapters: adapters,
  configure: configure,
  install: true,
);
