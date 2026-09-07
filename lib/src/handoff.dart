import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'protocol.dart';

const connectBleControlUuid = 'b6c01402-df5b-4b79-9f8d-8a642b9cd001';
const connectBleResponseUuid = 'b6c01403-df5b-4b79-9f8d-8a642b9cd001';
String handoffServiceUuid(String id) {
  identifier(id);
  return '${id.substring(0, 8)}-${id.substring(8, 12)}-${id.substring(12, 16)}-${id.substring(16, 20)}-${id.substring(20, 32)}';
}

String _encode(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
List<int> _decode(String text) {
  if (!matches(r'[A-Za-z0-9_-]+', text)) fail('invalidHandoff');
  final bytes = base64Url.decode(base64Url.normalize(text));
  if (_encode(bytes) != text) fail('invalidHandoff');
  return bytes;
}

/// The full challenge and a secret response-encryption key. Never log the URI.
class ConnectHandoff {
  final ConnectChallenge challenge;
  final SecretKey _key;
  final DateTime Function() _now;
  ConnectHandoff._(this.challenge, this._key, this._now);

  /// expectedOrigin must be trusted or explicitly confirmed by the wallet user.
  factory ConnectHandoff.parse(
    String uri, {
    String? expectedOrigin,
    DateTime Function()? now,
  }) {
    try {
      if (uri.length > 32768) fail('invalidHandoff');
      final parts = uri.split('#');
      if (parts.length != 2 || parts[1].isEmpty) fail('invalidHandoff');
      final target = UriTransport(schemes: {'connect'}).parse(parts[0]);
      final data = object(jsonDecode(utf8.decode(_decode(parts[1]))), [
        'type',
        'challenge',
        'key',
      ]);
      if (data['type'] != 'connect:handoff:1' ||
          data['key'] is! String ||
          !matches(r'[a-f0-9]{64}', data['key']) ||
          (expectedOrigin != null &&
              target.origin != validateOrigin(expectedOrigin))) {
        fail('invalidHandoff');
      }
      final clock = now ?? DateTime.now;
      final challenge = ConnectChallenge.fromJson(
        data['challenge'],
        target: target,
        now: clock(),
      );
      final key = data['key'] as String;
      return ConnectHandoff._(
        challenge,
        SecretKey([
          for (var i = 0; i < key.length; i += 2)
            int.parse(key.substring(i, i + 2), radix: 16),
        ]),
        clock,
      );
    } catch (_) {
      fail('invalidHandoff');
    }
  }
  String get serviceUuid => handoffServiceUuid(challenge.requestId);
  Future<String> sealProof(Map<String, dynamic> proof) async {
    challenge.validateTime(_now());
    if (proof['requestId'] != challenge.requestId) fail('invalidHandoff');
    final bytes = utf8.encode(jsonEncode(proof));
    if (bytes.length > 16384) fail('invalidHandoff');
    final box = await AesGcm.with256bits().encrypt(
      bytes,
      secretKey: _key,
      aad: utf8.encode('${challenge.origin}/${challenge.requestId}'),
    );
    challenge.validateTime(_now());
    return jsonEncode({
      'type': 'connect:response:1',
      'requestId': challenge.requestId,
      'iv': _encode(box.nonce),
      'ciphertext': _encode([...box.cipherText, ...box.mac.bytes]),
    });
  }
}

/// Bounded transport framing shared with Web Bluetooth. No key or plaintext proof is exposed.
class ConnectBleResponseBuffer {
  Uint8List? _bytes;
  void publish(String response) {
    final bytes = Uint8List.fromList(utf8.encode(response));
    if (bytes.isEmpty || bytes.length > 32768) fail('invalidHandoff');
    _bytes = bytes;
  }

  void clear() {
    _bytes = null;
  }

  Uint8List frame(int offset) {
    final bytes = _bytes;
    if (offset < 0 || offset > (bytes?.length ?? 0)) {
      fail('invalidBluetoothFrame');
    }
    final length = bytes == null ? 0 : (bytes.length - offset).clamp(0, 12);
    final frame = Uint8List(8 + length);
    final header = ByteData.sublistView(frame);
    header.setUint32(0, bytes?.length ?? 0, Endian.little);
    header.setUint32(4, offset, Endian.little);
    if (length > 0) frame.setRange(8, frame.length, bytes!, offset);
    return frame;
  }
}
