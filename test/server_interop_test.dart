import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';
import 'connect_test.dart'
    show Provider, Signer, hex, unhex, vectors, selection;

// Integration-only adapter: production HttpsNetwork never permits plaintext.
class LocalTestNetwork implements ConnectNetwork {
  final String endpoint;
  final _client = HttpClient();
  LocalTestNetwork(this.endpoint);
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic>? body,
  ]) async {
    final request = await _client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse('$endpoint/$action'),
    );
    request.headers.set('origin', 'https://example.com');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final data =
        jsonDecode(await utf8.decoder.bind(response).join())
            as Map<String, dynamic>;
    if (response.statusCode != 200) {
      throw StateError('Server status ${response.statusCode}: $data');
    }
    return data;
  }

  @override
  Future<Object?> challenge(ConnectTarget t) =>
      call('challenge?requestId=${t.requestId}');
  @override
  Future<Object?> approve(ConnectTarget t, Map<String, dynamic> proof) =>
      call('approve', proof);
  void close() => _client.close(force: true);
}

Future<WalletSignature> nativeEd448(
  Uint8List message,
  Map<String, dynamic> vector,
) async {
  final dir = await Directory.systemTemp.createTemp('connect-ed448-test-');
  try {
    // Public deterministic test seed, encoded as RFC8410 PKCS#8 for OpenSSL.
    final seed = vector['testSeed'] as String;
    await File(
      '${dir.path}/key.der',
    ).writeAsBytes(unhex('3047020100300506032b6571043b0439$seed'));
    await File('${dir.path}/message').writeAsBytes(message);
    final result = await Process.run('openssl', [
      'pkeyutl',
      '-sign',
      '-rawin',
      '-keyform',
      'DER',
      '-inkey',
      '${dir.path}/key.der',
      '-in',
      '${dir.path}/message',
      '-out',
      '${dir.path}/signature',
    ]);
    if (result.exitCode != 0) {
      throw StateError('OpenSSL Ed448 bridge failed: ${result.stderr}');
    }
    return WalletSignature(
      hex(await File('${dir.path}/signature').readAsBytes()),
      publicKey: (vector['proof'] as Map)['publicKey'] as String,
    );
  } finally {
    await dir.delete(recursive: true);
  }
}

void main() {
  final endpoint = Platform.environment['CONNECT_TEST_URL'];
  test('OpenSSL Ed448 host signing bridge matches shared vector', () async {
    final v = vectors().first as Map<String, dynamic>;
    final sig = await nativeEd448(unhex(v['canonicalHex'] as String), v);
    expect(sig.signature, (v['proof'] as Map)['signature']);
  });
  for (final vector in vectors()) {
    final v = vector as Map<String, dynamic>;
    final profile = (v['proof'] as Map)['profile'] as String;
    test(
      "desktop -> QR -> Dart ${v['name']} -> Better Auth desktop cookie",
      () async {
        final network = LocalTestNetwork(endpoint!);
        final created = await network.call('create', {});
        // Only the URI is passed into the wallet. The test desktop retains the secret.
        final wallet = Signer(selection(v['proof'] as Map<String, dynamic>), (
          bytes,
        ) async {
          if (profile == 'xcb-ed448') return nativeEd448(bytes, v);
          if (profile != 'raw-ed25519') {
            final result = await Process.run('node', [
              '../better-connect/scripts/sign-test-message.mjs',
              profile,
              ((v['proof'] as Map)['account'] as Map)['reference'] as String,
              hex(bytes),
            ]);
            if (result.exitCode != 0) {
              throw StateError('Host wallet failed: ${result.stderr}');
            }
            final signed =
                jsonDecode(result.stdout as String) as Map<String, dynamic>;
            return WalletSignature(
              signed['signature'] as String,
              publicKey: signed['publicKey'] as String?,
            );
          }
          final algorithm = Ed25519(),
              key = await Ed25519().newKeyPairFromSeed(
                unhex(v['testSeed'] as String),
              );
          final sig = await algorithm.sign(bytes, keyPair: key);
          return WalletSignature(
            hex(sig.bytes),
            publicKey: hex((await key.extractPublicKey()).bytes),
          );
        });
        final client = ConnectClient(
          accountProvider: Provider([wallet]),
          network: network,
        );
        try {
          final request = await client.resolve(created['connectUri'] as String);
          expect(request.state, ConnectState.awaitingUserApproval);
          await request.approve(request.compatibleAccounts.first);
          expect(request.state, ConnectState.approved);
          final result = await network.call('redeem', {
            'requestId': created['requestId'],
            'redeemSecret': created['redeemSecret'],
          });
          expect(result['success'], true);
        } finally {
          await client.dispose();
          network.close();
        }
      },
      skip: endpoint == null
          ? 'Run better-connect/scripts/flutter-interop.mjs to start the real server'
          : false,
    );
  }
}
