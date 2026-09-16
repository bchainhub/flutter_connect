import 'dart:typed_data';
import 'package:connect_wallet_example/operations.dart';
import 'package:flutter_connect/flutter_connect.dart';
import 'package:flutter_test/flutter_test.dart';

class ExampleAccount implements WalletAccount {
  @override
  final SigningSelection selection;
  ExampleAccount(ConnectChain chain)
    : selection = chain.account(
        {
          'core': 'cb23f5e89ba978317da861b7ad06ba3103d41c876098',
          'eip155': '0x1a642f0E3c3aF545E7AcBD38b07251B3990914F1',
          'bip122': 'bc1q0xcqpzrky6eff2g52qdye53xkk9jxkvrh6yhyw',
          'solana': 'AKnL4NNf3DGWZJS6cPknBuEGnVsV4A4m5tgebLHaRSZ9',
        }[chain.namespace]!,
      );
  @override
  Future<WalletSignature> sign(Uint8List payload) async =>
      throw StateError('Authentication signer must not run');
}

class ExampleHost implements OperationsHost, WalletAccountProvider {
  int approvals = 0, signatures = 0, reads = 0;
  final identities = [
    ConnectChains.ethereum,
    ConnectChains.bitcoin,
    ConnectChains.solana,
    ConnectChains.core,
  ].map(ExampleAccount.new).toList();
  @override
  WalletAccountProvider get accounts => this;
  @override
  Future<List<WalletAccount>> getAccounts() async => identities;
  @override
  bool approve(
    ConnectOperation request,
    OperationContext context,
    Object? preparedMessage,
  ) {
    approvals++;
    return true;
  }

  @override
  bool validateAccount(WalletIdentity account) => true;
  @override
  void validateOperation(ConnectOperation request) {
    // Test host only. Real hosts must use chain SDK validation before approval.
    expect(request.params, isNotEmpty);
  }

  Object sign(ConnectOperation request) {
    signatures++;
    return {'signed': 'example-only'};
  }

  @override
  Object signEvm(ConnectOperation request, OperationContext context) =>
      sign(request);
  @override
  Object signPsbt(ConnectOperation request, OperationContext context) =>
      sign(request);
  @override
  Object signSolana(ConnectOperation request, OperationContext context) =>
      sign(request);
  @override
  Object signCore(ConnectOperation request, OperationContext context) =>
      sign(request);
  @override
  Object getBalance(ConnectOperation request, OperationContext context) {
    reads++;
    return '100';
  }
}

void main() {
  test(
    'native payload examples sign four requests and read balance independently',
    () async {
      final host = ExampleHost();
      final dispatcher = createExampleOperations(host);
      final a = host.identities.map((a) => a.selection.account).toList();
      final requests = exampleRequests(
        evm: a[0],
        bitcoin: a[1],
        solana: a[2],
        core: a[3],
        evmTransaction: {'value': '0x1'},
        psbt: 'cHNidP8=',
        solanaTransaction: 'AQID',
        coreTransaction: {'energy': '21000'},
      );
      for (final request in requests) {
        expect(
          (await dispatcher.dispatch(
            request,
            origin: 'https://example.com',
          )).isSuccess,
          isTrue,
        );
      }
      expect(host.approvals, 4);
      expect(host.signatures, 4);
      expect(host.reads, 1);
    },
  );
}
