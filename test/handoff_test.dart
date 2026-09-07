import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';
import 'connect_test.dart' show vectors, now, Provider, Signer, selection;

void main() {
  final responses = <String>[];
  for (final dynamic value in vectors()) {
    final v = value as Map<String, dynamic>;
    test('offline approval and encrypted response ${v['name']}', () async {
      final c = v['challenge'] as Map<String, dynamic>;
      final proof = v['proof'] as Map<String, dynamic>;
      final payload = base64Url
          .encode(
            utf8.encode(
              jsonEncode({
                'type': 'connect:handoff:1',
                'challenge': c,
                'key': '01' * 32,
              }),
            ),
          )
          .replaceAll('=', '');
      final uri =
          'connect://${c['domain']}/connect/v1/${c['requestId']}#$payload';
      var signed = 0;
      final client = ConnectClient(
        now: () => now,
        accountProvider: Provider([
          Signer(selection(proof), (bytes) async {
            signed++;
            expect(utf8.decode(bytes), v['canonical']);
            return WalletSignature(
              proof['signature'] as String,
              publicKey: proof['publicKey'] as String?,
            );
          }),
        ]),
      );
      final request = await client.resolve(uri);
      expect(signed, 0);
      expect(request.handoff, isNotNull);
      await request.approve(request.compatibleAccounts.first);
      expect(signed, 1);
      expect(request.state, ConnectState.responseReady);
      expect(request.response, isNotNull);
      responses.add(request.response!);
      await expectLater(
        request.approve(request.compatibleAccounts.first),
        throwsA(isA<ConnectException>()),
      );
      expect(
        () => ConnectHandoff.parse(
          uri,
          expectedOrigin: 'https://evil.example',
          now: () => now,
        ),
        throwsA(isA<ConnectException>()),
      );
      expect(
        () => ConnectHandoff.parse(
          uri,
          now: () => now.add(const Duration(minutes: 10)),
        ),
        throwsA(isA<ConnectException>()),
      );
    });
  }
  test('BLE frames are bounded and reconstruct the complete packet', () {
    final buffer = ConnectBleResponseBuffer();
    expect(buffer.frame(0), Uint8List(8));
    final input = 'encrypted response ' * 100;
    buffer.publish(input);
    final result = <int>[];
    while (result.length < input.length) {
      final frame = buffer.frame(result.length);
      expect(frame.length, lessThanOrEqualTo(20));
      final header = ByteData.sublistView(frame);
      expect(header.getUint32(0, Endian.little), input.length);
      expect(header.getUint32(4, Endian.little), result.length);
      result.addAll(frame.sublist(8));
    }
    expect(utf8.decode(result), input);
    expect(() => buffer.frame(-1), throwsA(isA<ConnectException>()));
    expect(() => buffer.publish('x' * 32769), throwsA(isA<ConnectException>()));
    buffer.clear();
    expect(buffer.frame(0), Uint8List(8));
  });
  tearDownAll(() {
    final path = Platform.environment['CONNECT_DART_RESPONSES'];
    if (path != null) File(path).writeAsStringSync(jsonEncode(responses));
  });
}
