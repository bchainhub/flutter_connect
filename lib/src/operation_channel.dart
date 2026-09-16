import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'operations.dart';
import 'protocol.dart';

/// Pairing encryption follows the existing Connect AES-GCM convention.
/// The host supplies a session pairing key, never a wallet signing key.
/// Encryption does not establish wallet ownership. Never log pairing keys.
class OperationCipher {
  final String _origin, _requestId;
  final SecretKey _key;
  OperationCipher._(this._origin, this._requestId, this._key);
  factory OperationCipher(
    String origin,
    String requestId,
    List<int> pairingKey,
  ) {
    try {
      validateOrigin(origin);
      identifier(requestId);
      if (pairingKey.length != 32 || pairingKey.any((v) => v < 0 || v > 255)) {
        throw StateError('invalid');
      }
      return OperationCipher._(
        origin,
        requestId,
        SecretKey(List.of(pairingKey)),
      );
    } catch (_) {
      throw OperationException('INVALID_PARAMS');
    }
  }
  Future<String> sealRequest(ConnectOperation request) {
    if (request.requestId != _requestId) {
      throw OperationException('INVALID_PARAMS');
    }
    return _seal(request.serialize(), 'request');
  }

  Future<String> sealResponse(OperationResponse response) {
    if (response.requestId != _requestId) {
      throw OperationException('INVALID_PARAMS');
    }
    return _seal(response.serialize(), 'response');
  }

  Future<ConnectOperation> openRequest(String packet) async {
    final request = ConnectOperation.fromJson(await _open(packet, 'request'));
    if (request.requestId != _requestId) {
      throw OperationException('INVALID_PARAMS');
    }
    return request;
  }

  Future<OperationResponse> openResponse(String packet) async =>
      OperationResponse.fromJson(
        await _open(packet, 'response'),
        expectedRequestId: _requestId,
      );
  List<int> _aad(String kind) =>
      utf8.encode('connect:operation:1/$kind/$_origin/$_requestId');
  String _encode(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
  List<int> _decode(Object? value) {
    if (value is! String || !matches(r'[A-Za-z0-9_-]+', value)) {
      throw OperationException('INVALID_PARAMS');
    }
    final bytes = base64Url.decode(base64Url.normalize(value));
    if (_encode(bytes) != value) throw OperationException('INVALID_PARAMS');
    return bytes;
  }

  Future<String> _seal(String plaintext, String kind) async {
    try {
      final bytes = utf8.encode(plaintext);
      if (bytes.length > maxOperationBytes) {
        throw OperationException('INVALID_PARAMS');
      }
      final box = await AesGcm.with256bits().encrypt(
        bytes,
        secretKey: _key,
        aad: _aad(kind),
      );
      return jsonEncode({
        'type': 'connect:operation:encrypted:1',
        'kind': kind,
        'requestId': _requestId,
        'iv': _encode(box.nonce),
        'ciphertext': _encode([...box.cipherText, ...box.mac.bytes]),
      });
    } catch (_) {
      throw OperationException('INVALID_PARAMS');
    }
  }

  Future<String> _open(String input, String kind) async {
    try {
      if (input.length > 32768) throw OperationException('INVALID_PARAMS');
      final p = object(jsonDecode(input), [
        'type',
        'kind',
        'requestId',
        'iv',
        'ciphertext',
      ]);
      if (p['type'] != 'connect:operation:encrypted:1' ||
          p['kind'] != kind ||
          p['requestId'] != _requestId) {
        throw OperationException('INVALID_PARAMS');
      }
      final iv = _decode(p['iv']), bytes = _decode(p['ciphertext']);
      if (iv.length != 12 ||
          bytes.length < 16 ||
          bytes.length > maxOperationBytes + 16) {
        throw OperationException('INVALID_PARAMS');
      }
      final plaintext = await AesGcm.with256bits().decrypt(
        SecretBox(
          bytes.sublist(0, bytes.length - 16),
          nonce: iv,
          mac: Mac(bytes.sublist(bytes.length - 16)),
        ),
        secretKey: _key,
        aad: _aad(kind),
      );
      return utf8.decode(plaintext);
    } catch (_) {
      throw OperationException('INVALID_PARAMS');
    }
  }
}
