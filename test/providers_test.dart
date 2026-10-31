import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';

class EchoTransport implements OperationTransport {
  final List<ConnectOperation> requests = [];
  @override
  Future<String> exchange(String input) async {
    final request = ConnectOperation.fromJson(jsonDecode(input));
    requests.add(request);
    return OperationResponse.success(
      request.requestId,
      request.chain.namespace,
    ).serialize();
  }
}

void main() {
  test('default and custom discovery identity', () {
    final info = ProviderInfo();
    expect(info.name, 'Connect Wallet Protocol');
    expect(info.rdns, 'connect.wallet');
    expect(info.uuid, isNot(ProviderInfo().uuid));
    final custom = ProviderInfo(
      name: 'Wallet',
      rdns: 'org.example',
      icon: 'ipfs://cid/icon.webp',
      iconUrl: 'https://example.org/icon.png',
      extra: {'blockchain': 'core'},
    );
    expect(custom.toJson()['blockchain'], 'core');
    expect(custom.toJson()['name'], 'Wallet');
    expect(() => ProviderInfo(uuid: 'bad'), throwsArgumentError);
    expect(
      () => ProviderInfo(icon: 'http://example.org/icon.png'),
      throwsArgumentError,
    );
    expect(() => ProviderInfo(rdns: 'bad'), throwsArgumentError);
  });
  test('universal routing default and call override', () async {
    final transport = EchoTransport();
    final provider = UniversalProvider(
      routes: {
        Blockchain.core: BlockchainRoute(
          chain: OperationChain('core', '1'),
          transport: transport,
        ),
        Blockchain.ethereum: BlockchainRoute(
          chain: OperationChain('eip155', '1'),
          transport: transport,
        ),
      },
    );
    expect(
      await provider.operation(
        OperationMethods.getBlock,
        params: {'number': 'latest'},
      ),
      'core',
    );
    expect(
      await provider.operation(
        OperationMethods.getBalance,
        blockchain: Blockchain.ethereum,
      ),
      'eip155',
    );
    expect(provider.defaultBlockchain, Blockchain.core);
    provider.defaultBlockchain = Blockchain.ethereum;
    expect(await provider.operation(OperationMethods.getAccounts), 'eip155');
    expect(transport.requests.first.params, {'number': 'latest'});
    await expectLater(
      provider.operation(OperationMethods.getBlock, blockchain: Blockchain.ton),
      throwsA(isA<OperationException>()),
    );
  });
}
