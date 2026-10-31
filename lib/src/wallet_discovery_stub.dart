import 'providers.dart';
import 'wallet_provider.dart';
import 'wallet_discovery.dart';

WalletDiscovery discoverWalletProviders({
  Iterable<WalletAdapter> adapters = const [],
  NativeWalletConfiguration Function(Blockchain, String)? configure,
  bool install = false,
}) {
  final api = UniversalWalletProvider(adapters);
  return WalletDiscovery(api: api, refresh: () {}, dispose: api.dispose);
}
