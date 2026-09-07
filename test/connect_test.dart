import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

List<dynamic> vectors() =>
    jsonDecode(File('test/fixtures/conformance.json').readAsStringSync())
        as List;
Uint8List unhex(String s) => Uint8List.fromList([
  for (var i = 0; i < s.length; i += 2)
    int.parse(s.substring(i, i + 2), radix: 16),
]);
String hex(List<int> b) =>
    b.map((i) => i.toRadixString(16).padLeft(2, '0')).join();
final now = DateTime.parse('2026-09-07T10:00:00.000Z');
SigningSelection selection(Map<String, dynamic> p) => SigningSelection(
  account: WalletIdentity.fromJson(p['account']),
  profile: p['profile'] as String,
  alg: p['alg'] as int?,
);

class Signer implements WalletAccount {
  @override
  final SigningSelection selection;
  final Future<WalletSignature> Function(Uint8List) callback;
  Signer(this.selection, this.callback);
  @override
  Future<WalletSignature> sign(Uint8List payload) => callback(payload);
}

class Provider implements WalletAccountProvider {
  final List<WalletAccount> accounts;
  Provider(this.accounts);
  @override
  Future<List<WalletAccount>> getAccounts() async => accounts;
}

class Network implements ConnectNetwork {
  final Map<String, dynamic> data;
  int submitted = 0;
  Object? response;
  Network(this.data);
  @override
  Future<Object?> challenge(ConnectTarget t) async => data;
  @override
  Future<Object?> approve(ConnectTarget t, Map<String, dynamic> p) async {
    submitted++;
    return response ?? {'requestId': t.requestId, 'status': 'APPROVED'};
  }
}

void main() {
  for (final dynamic item in vectors()) {
    final v = item as Map<String, dynamic>;
    test('shared canonical bytes ${v['name']}', () async {
      final c = ConnectChallenge.fromJson(v['challenge'], now: now),
          s = selection(v['proof'] as Map<String, dynamic>);
      expect(canonicalMessage(c, s), v['canonical']);
      expect(hex(canonicalBytes(c, s)), v['canonicalHex']);
      if (v['name'] == 'raw-ed25519') {
        final algorithm = Ed25519(),
            key = await Ed25519().newKeyPairFromSeed(
              unhex(v['testSeed'] as String),
            );
        final signature = await algorithm.sign(
          canonicalBytes(c, s),
          keyPair: key,
        );
        expect(hex(signature.bytes), (v['proof'] as Map)['signature']);
        expect(
          await algorithm.verify(canonicalBytes(c, s), signature: signature),
          isTrue,
        );
      }
    });
  }
  test('strict URI transports', () {
    final parser = UriTransport(),
        uri = 'connect://example.com/connect/v1/${'a' * 64}';
    expect(
      parser.parse(uri).origin,
      parser.parse(uri.replaceFirst('connect:', 'https:')).origin,
    );
    for (final bad in [
      '$uri\n',
      '$uri?redeemSecret=secret',
      '$uri#fragment',
      '$uri/',
      uri.replaceFirst('v1', 'v2'),
      uri.replaceFirst('example.com', 'user@example.com'),
      uri.replaceFirst('example.com', 'EXAMPLE.com'),
      uri.replaceFirst('example.com', '127.0.0.1'),
      uri.replaceFirst('example.com', 'example.com:443'),
      uri.replaceFirst('example.com', 'example.com.'),
      uri.replaceFirst('/connect/', '/x/../connect/'),
      uri.replaceFirst('connect:', 'http:'),
    ]) {
      expect(
        () => parser.parse(bad),
        throwsA(isA<ConnectException>()),
        reason: bad,
      );
    }
  });
  test('challenge binding, strict schema, times and expiry', () {
    final raw = vectors().first['challenge'] as Map<String, dynamic>,
        target = ConnectTarget('https://example.com', 'a' * 64);
    for (final patch in [
      {'domain': 'evil.com'},
      {'origin': 'https://evil.com'},
      {'requestId': 'c' * 64},
      {'version': 2},
      {'nonce': '${'a' * 64}\n'},
      {'issuedAt': '2026-02-30T10:00:00.000Z'},
      {'expiresAt': now.toIso8601String()},
      {'redeemSecret': 'secret'},
    ]) {
      expect(
        () => ConnectChallenge.fromJson(
          {...raw, ...patch},
          target: target,
          now: now,
        ),
        throwsA(isA<ConnectException>()),
      );
    }
  });
  test(
    'explicit approval, local reject, replay and server confirmation',
    () async {
      final v = vectors()[1], data = v['challenge'] as Map<String, dynamic>;
      var calls = 0;
      final signer = Signer(selection(v['proof'] as Map<String, dynamic>), (
            p,
          ) async {
            calls++;
            return const WalletSignature('00');
          }),
          network = Network(data);
      final client = ConnectClient(
        accountProvider: Provider([signer]),
        network: network,
        now: () => now,
      );
      final request = await client.resolve(
        ConnectTarget(data['origin'], data['requestId']).connectUri,
      );
      expect(calls, 0);
      await request.approve(request.compatibleAccounts.first);
      expect(request.state, ConnectState.approved);
      expect(calls, 1);
      await expectLater(
        request.approve(request.compatibleAccounts.first),
        throwsA(isA<ConnectException>()),
      );
      await expectLater(
        client.resolve(request.challenge.connectUri),
        throwsA(isA<ConnectException>()),
      );
      await client.dispose();
    },
  );
  test('cancel during signing prevents submission', () async {
    final v = vectors()[1],
        result = Completer<WalletSignature>(),
        network = Network(v['challenge'] as Map<String, dynamic>);
    final signer = Signer(
      selection(v['proof'] as Map<String, dynamic>),
      (_) => result.future,
    );
    final client = ConnectClient(
      accountProvider: Provider([signer]),
      network: network,
      now: () => now,
    );
    final request = await client.resolve(
      ConnectTarget('https://example.com', 'a' * 64).connectUri,
    );
    final approval = request.approve(request.compatibleAccounts.first);
    request.cancel();
    result.complete(const WalletSignature('00'));
    await expectLater(approval, throwsA(isA<ConnectException>()));
    expect(network.submitted, 0);
    expect(request.state, ConnectState.cancelled);
    await client.dispose();
  });
  test('expiry checked again after signing', () async {
    final v = vectors()[1],
        network = Network(v['challenge'] as Map<String, dynamic>);
    var time = now;
    final signer = Signer(selection(v['proof'] as Map<String, dynamic>), (
      _,
    ) async {
      time = now.add(const Duration(minutes: 5));
      return const WalletSignature('00');
    });
    final client = ConnectClient(
      accountProvider: Provider([signer]),
      network: network,
      now: () => time,
    );
    final request = await client.resolve(
      ConnectTarget('https://example.com', 'a' * 64).connectUri,
    );
    await expectLater(
      request.approve(request.compatibleAccounts.first),
      throwsA(isA<ConnectException>()),
    );
    expect(network.submitted, 0);
    expect(request.state, ConnectState.expired);
    await client.dispose();
  });
  test('HTTP redirect rejected and response size bounded', () async {
    final target = ConnectTarget('https://example.com', 'a' * 64);
    for (final response in [
      http.Response('', 302),
      http.Response('x' * 20000, 200),
    ]) {
      final network = HttpsNetwork(
        client: MockClient((r) async {
          expect(r.followRedirects, isFalse);
          return response;
        }),
      );
      await expectLater(
        network.challenge(target),
        throwsA(isA<ConnectException>()),
      );
      network.close();
    }
  });
}
