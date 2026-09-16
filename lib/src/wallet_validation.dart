import 'package:flutter_wallet_validator/flutter_wallet_validator.dart'
    as validator;
import 'protocol.dart';
import 'operations.dart';

enum WalletValidationStatus { valid, invalid, unsupported }

class WalletValidationResult {
  final WalletValidationStatus status;
  const WalletValidationResult(this.status);
}

const _networks = <String, String>{
  'core:1': 'xcb',
  'core:3': 'xab',
  'bip122:000000000019d6689c085ae165831e93': 'btc',
  'bip122:12a765e31ffd4059bada1e25190f6e98': 'ltc',
  'solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp': 'sol',
  'tron:728126428': 'trx',
  'xrpl:0': 'xrp',
  'stellar:pubnet': 'xlm',
  'cip34:1-764824073': 'ada',
};
const _invalid = WalletValidationResult(WalletValidationStatus.invalid);
const _unsupported = WalletValidationResult(WalletValidationStatus.unsupported);
WalletValidationResult _valid(bool value) => value
    ? const WalletValidationResult(WalletValidationStatus.valid)
    : _invalid;
int _base58Length(String value) {
  const alphabet = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
  var number = BigInt.zero;
  for (final c in value.codeUnits) {
    final digit = alphabet.indexOf(String.fromCharCode(c));
    if (digit < 0) throw const FormatException();
    number = number * BigInt.from(58) + BigInt.from(digit);
  }
  return (number.bitLength + 7) ~/ 8 +
      value.codeUnits.takeWhile((c) => c == 49).length;
}

WalletValidationResult _cardano(String address) {
  // Bech32 checksum + Shelley header/length. Pointer and Byron forms remain host-owned.
  if (address != address.toLowerCase()) return _invalid;
  final separator = address.lastIndexOf('1');
  if (separator < 1 || separator + 7 > address.length) return _invalid;
  final hrp = address.substring(0, separator);
  if (hrp != 'addr' && hrp != 'stake') return _invalid;
  const alphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
  final words = address
      .substring(separator + 1)
      .codeUnits
      .map((c) => alphabet.indexOf(String.fromCharCode(c)))
      .toList();
  if (words.any((v) => v < 0)) return _invalid;
  final values = [
    ...hrp.codeUnits.map((v) => v >> 5),
    0,
    ...hrp.codeUnits.map((v) => v & 31),
    ...words,
  ];
  var check = 1;
  const generators = [
    0x3b6a57b2,
    0x26508e6d,
    0x1ea119fa,
    0x3d4233dd,
    0x2a1462b3,
  ];
  for (final value in values) {
    final top = check >> 25;
    check = ((check & 0x1ffffff) << 5) ^ value;
    for (var i = 0; i < 5; i++) {
      if (((top >> i) & 1) != 0) check ^= generators[i];
    }
  }
  if (check != 1) return _invalid;
  var acc = 0, bits = 0;
  final bytes = <int>[];
  for (final word in words.take(words.length - 6)) {
    acc = ((acc << 5) | word) & 0xffff;
    bits += 5;
    while (bits >= 8) {
      bits -= 8;
      bytes.add((acc >> bits) & 255);
    }
  }
  if (bits >= 5 || ((acc << (8 - bits)) & 255) != 0 || bytes.isEmpty) {
    return _invalid;
  }
  if ((bytes[0] & 15) != 1) return _invalid;
  final type = bytes[0] >> 4;
  if (type <= 3) return _valid(hrp == 'addr' && bytes.length == 57);
  if (type == 6 || type == 7) {
    return _valid(hrp == 'addr' && bytes.length == 29);
  }
  if (type == 14 || type == 15) {
    return _valid(hrp == 'stake' && bytes.length == 29);
  }
  return _unsupported;
}

/// Address validity only: does not establish wallet ownership or selected network.
/// Unknown references/formats return unsupported and require host validation.
WalletValidationResult validateWalletAccount(WalletIdentity account) {
  try {
    final namespace = account.namespace,
        reference = account.reference,
        address = account.address;
    if (![
      namespace,
      reference,
      address,
    ].every((v) => v.length <= 128 && matches(r'[a-zA-Z0-9._-]+', v))) {
      return _invalid;
    }
    final network = namespace == 'eip155'
        ? 'evm'
        : _networks['$namespace:$reference'];
    if (network == null) return _unsupported;
    if (network == 'evm' && !matches(r'[1-9][0-9]{0,14}', reference)) {
      return _invalid;
    }
    final body = address.length >= 2 ? address.substring(2) : '';
    final packageAddress =
        network == 'evm' &&
            (body == body.toUpperCase() || body == body.toLowerCase())
        ? address.toLowerCase()
        : address;
    final upstream = validator.validateWalletAddress(
      packageAddress,
      options: validator.ValidationOptions(
        network: [network],
        testnet: network == 'xab',
        enabledLegacy: true,
        nsDomains: const [],
      ),
    );
    if (network == 'evm') {
      return _valid(matches(r'0x[0-9a-fA-F]{40}', address) && upstream.isValid);
    }
    if (network == 'xcb' || network == 'xab') {
      return _valid(
        address.toLowerCase().startsWith(network == 'xcb' ? 'cb' : 'ab') &&
            upstream.isValid,
      );
    }
    if (network == 'sol') return _valid(_base58Length(address) == 32);
    if (network == 'ada') return _cardano(address);
    if (network == 'btc' || network == 'ltc') {
      final hrp = network == 'btc' ? 'bc' : 'ltc';
      // Only mainnet references are mapped. testnet=true is never used for these.
      if (address.toLowerCase().startsWith('${hrp}1') && address.length > 90) {
        return _invalid;
      }
    }
    return _valid(upstream.isValid);
  } catch (_) {
    return _invalid;
  }
}

bool isValidWalletAccount(WalletIdentity account) =>
    validateWalletAccount(account).status == WalletValidationStatus.valid;

/// Composes address checks with the existing mandatory host account policy.
OperationChainAdapter withWalletValidation(OperationChainAdapter adapter) =>
    OperationChainAdapter(
      capabilities: adapter.capabilities,
      handlers: adapter.handlers,
      validateAccount: (account) async =>
          validateWalletAccount(account).status !=
              WalletValidationStatus.invalid &&
          await adapter.validateAccount(account),
      validateOperation: adapter.validateOperation,
      prepareMessage: adapter.prepareMessage,
      normalizeResult: adapter.normalizeResult,
      translateError: adapter.translateError,
    );
