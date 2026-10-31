import 'providers.dart';

void Function() injectProviders(
  Map<Blockchain, InjectedProvider> providers,
  UniversalProvider connect,
) => throw UnsupportedError('Provider injection requires a browser');
