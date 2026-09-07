import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_connect/flutter_connect.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chain catalog agrees with shared proofs and signing requirements', () {
    final vectors =
        jsonDecode(File('test/fixtures/conformance.json').readAsStringSync())
            as List;
    for (final chain in ConnectChains.all) {
      final v = vectors.firstWhere(
        (v) =>
            v['proof']['profile'] == chain.profile &&
            v['proof']['account']['reference'] == chain.reference,
      );
      final selection = chain.account(
        v['proof']['account']['address'] as String,
      );
      expect(chain.requirement.accepts(selection), true);
      final challenge = ConnectChallenge.fromJson(
        v['challenge'],
        now: DateTime.parse(v['challenge']['issuedAt']),
      );
      expect(canonicalMessage(challenge, selection), v['canonical']);
    }
    expect(
      requirementsFor([ConnectChains.solana, ConnectChains.solana]),
      hasLength(1),
    );
    expect(ConnectChains.all, hasLength(16));
  });
  test('ordinary wallet adapter preserves canonical bytes and proof', () async {
    final bytes = Uint8List.fromList(utf8.encode('Connect authentication'));
    final account = ChainWalletAccount(
      chain: ConnectChains.solana,
      address: 'testaddress',
      sign: (received) async {
        expect(received, bytes);
        return const WalletSignature('signature');
      },
    );
    expect(account.selection.profile, 'solana-ed25519');
    expect((await account.sign(bytes)).signature, 'signature');
    final custom = ConnectChain.evm('Arbitrum', 42161);
    expect(custom.reference, '42161');
    expect(custom.profile, 'ethereum-siwe');
    expect(() => ConnectChain.evm('bad', 0), throwsA(isA<ConnectException>()));
  });
}
