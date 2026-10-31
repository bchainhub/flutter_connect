import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/digests/keccak.dart';
import 'package:pointycastle/digests/sha3.dart';
import 'providers.dart';
import 'wallet_provider.dart';

typedef AbiParameter = Map<String, Object?>;
Map<String, Object?> providerObject(Object? input) {
  if (input is! Map) {
    throw InvalidTransactionError('Expected a native request object.');
  }
  return Map<String, Object?>.from(input);
}

BigInt providerQuantity(Object? value) {
  if (value is! String && value is! int && value is! BigInt) {
    throw InvalidTransactionError('Expected a nonnegative integer.');
  }
  final text = value.toString();
  if (!RegExp(r'^(?:0x[0-9a-fA-F]+|[0-9]+)$').hasMatch(text)) {
    throw InvalidTransactionError('Invalid integer quantity.');
  }
  return BigInt.parse(text);
}

String providerHexQuantity(Object? value) =>
    '0x${providerQuantity(value).toRadixString(16)}';
Uint8List providerBytes(Object? input) {
  if (input is String) return Uint8List.fromList(utf8.encode(input));
  if (input is List<int> && input.every((v) => v >= 0 && v < 256)) {
    return Uint8List.fromList(input);
  }
  throw InvalidTransactionError('Message must be a string or bytes.');
}

String providerHex(List<int> bytes) =>
    '0x${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
Uint8List providerUnhex(Object? input) {
  if (input is! String || !RegExp(r'^0x(?:[0-9a-fA-F]{2})*$').hasMatch(input)) {
    throw InvalidTransactionError('Expected hex bytes.');
  }
  return Uint8List.fromList([
    for (var i = 2; i < input.length; i += 2)
      int.parse(input.substring(i, i + 2), radix: 16),
  ]);
}

bool providerCoreAddressValid(Object? value) {
  if (value is String &&
      RegExp(r'^0{43}[0-9]$').hasMatch(
        value.replaceFirst(RegExp(r'^0x', caseSensitive: false), ''),
      )) {
    return true;
  }
  if (value is String) {
    value = value.replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
  }
  if (value is! String ||
      !RegExp(r'^[a-fA-F]{2}[0-9]{2}[0-9a-fA-F]{40}$').hasMatch(value)) {
    return false;
  }
  final rearranged = value.substring(4) + value.substring(0, 4);
  final decimal = rearranged
      .split('')
      .map((c) => int.parse(c, radix: 16).toString())
      .join();
  return BigInt.parse(decimal) % BigInt.from(97) == BigInt.one;
}

String providerAddress(
  Object? value,
  Blockchain blockchain, [
  Object? network,
]) {
  if (blockchain == Blockchain.core
      ? !providerCoreAddressValid(value)
      : value is! String || !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value)) {
    throw InvalidTransactionError('Invalid ${blockchain.name} address.');
  }
  final address = blockchain == Blockchain.core
      ? (value as String).replaceFirst(RegExp(r'^0x', caseSensitive: false), '')
      : value as String;
  if (blockchain == Blockchain.core && network != null) {
    final id = providerQuantity(network);
    final prefix = id == BigInt.one
        ? 'cb'
        : id == BigInt.from(3) || id == BigInt.from(4)
        ? 'ab'
        : id >= BigInt.from(10)
        ? 'ce'
        : null;
    if (prefix == null) {
      throw InvalidTransactionError(
        'Unassigned Core network ID; private networks start at 10.',
      );
    }
    if (!RegExp(r'^0{43}[0-9]$').hasMatch(address) &&
        !address.toLowerCase().startsWith(prefix)) {
      throw NetworkMismatchError(
        'ICAN prefix does not match the selected Core network.',
      );
    }
  }
  return address;
}

Uint8List providerHash(List<int> bytes, Blockchain blockchain) =>
    blockchain == Blockchain.core
    ? SHA3Digest(256).process(Uint8List.fromList(bytes))
    : KeccakDigest(256).process(Uint8List.fromList(bytes));
List<AbiParameter> _parameters(Object? value) =>
    value == null ? [] : (value as List).map(providerObject).toList();
String _type(AbiParameter p) => p['type'] as String;
AbiParameter _base(AbiParameter p, String type) => {...p, 'type': type};
RegExpMatch? _array(AbiParameter p) =>
    RegExp(r'^(.*)\[([0-9]*)\]$').firstMatch(_type(p));
String _signature(AbiParameter p) {
  final type = _type(p);
  if (type.startsWith('tuple')) {
    return '(${_parameters(p['components']).map(_signature).join(',')})${type.substring(5)}';
  }
  return type
      .replaceFirst(RegExp(r'^uint(?=\[|$)'), 'uint256')
      .replaceFirst(RegExp(r'^int(?=\[|$)'), 'int256');
}

AbiParameter _function(Map<String, Object?> r) {
  final name = r['functionName'];
  if (name is! String || r['abi'] is! List) {
    throw InvalidTransactionError('ABI and functionName are required.');
  }
  final matches = _parameters(r['abi'])
      .where(
        (f) =>
            f['type'] == 'function' &&
            (f['name'] == name ||
                '${f['name']}(${_parameters(f['inputs']).map(_signature).join(',')})' ==
                    name),
      )
      .toList();
  if (matches.length != 1) {
    throw InvalidTransactionError(
      'Select one ABI function; use its full signature for overloads.',
    );
  }
  return matches.single;
}

bool _dynamic(AbiParameter p) {
  final array = _array(p);
  if (array != null) return array[2]!.isEmpty || _dynamic(_base(p, array[1]!));
  return ['bytes', 'string'].contains(_type(p)) ||
      (_type(p) == 'tuple' && _parameters(p['components']).any(_dynamic));
}

int _size(AbiParameter p) {
  if (_dynamic(p)) return 32;
  final array = _array(p);
  if (array != null) {
    final n = int.parse(array[2]!);
    if (n > 4096) throw InvalidTransactionError('ABI array limit exceeded.');
    return n * _size(_base(p, array[1]!));
  }
  if (_type(p) == 'tuple') {
    return _parameters(p['components']).fold(0, (n, p) => n + _size(p));
  }
  return 32;
}

Uint8List _join(Iterable<List<int>> lists) =>
    Uint8List.fromList(lists.expand((v) => v).toList());
Uint8List _word(BigInt value) {
  if (value < BigInt.zero || value >= (BigInt.one << 256)) {
    throw InvalidTransactionError('ABI integer overflow.');
  }
  final hex = value.toRadixString(16).padLeft(64, '0');
  return providerUnhex('0x$hex');
}

List<Object?> _tupleValues(List<AbiParameter> parameters, Object? input) {
  final values = input is List
      ? input.cast<Object?>()
      : parameters.map((p) => providerObject(input)[p['name']]).toList();
  if (values.length != parameters.length) {
    throw InvalidTransactionError('Incorrect ABI argument count.');
  }
  return values;
}

Uint8List _encodeTuple(
  List<AbiParameter> parameters,
  List<Object?> values,
  Blockchain blockchain,
  int depth,
) {
  if (depth > 32 ||
      parameters.length > 4096 ||
      parameters.length != values.length) {
    throw InvalidTransactionError('Invalid ABI tuple.');
  }
  var offset = parameters.fold(0, (n, p) => n + _size(p));
  final head = <List<int>>[], tail = <List<int>>[];
  for (var i = 0; i < parameters.length; i++) {
    final encoded = _encode(parameters[i], values[i], blockchain, depth + 1);
    if (_dynamic(parameters[i])) {
      head.add(_word(BigInt.from(offset)));
      tail.add(encoded);
      offset += encoded.length;
    } else {
      head.add(encoded);
    }
  }
  return _join([...head, ...tail]);
}

Uint8List _encode(
  AbiParameter p,
  Object? value,
  Blockchain blockchain,
  int depth,
) {
  if (depth > 32) throw InvalidTransactionError('ABI nesting limit exceeded.');
  final type = _type(p), array = _array(p);
  if (array != null) {
    if (value is! List ||
        value.length > 4096 ||
        (array[2]!.isNotEmpty && value.length != int.parse(array[2]!))) {
      throw InvalidTransactionError('Invalid ABI array.');
    }
    final encoded = _encodeTuple(
      List.filled(value.length, _base(p, array[1]!)),
      value.cast<Object?>(),
      blockchain,
      depth + 1,
    );
    return array[2]!.isEmpty
        ? _join([_word(BigInt.from(value.length)), encoded])
        : encoded;
  }
  if (type == 'tuple') {
    final fields = _parameters(p['components']);
    return _encodeTuple(
      fields,
      _tupleValues(fields, value),
      blockchain,
      depth + 1,
    );
  }
  if (type == 'address') {
    final address = providerAddress(value, blockchain);
    return _word(
      BigInt.parse(blockchain == Blockchain.core ? '0x$address' : address),
    );
  }
  if (type == 'bool') {
    if (value is! bool) throw InvalidTransactionError('Expected ABI boolean.');
    return _word(value ? BigInt.one : BigInt.zero);
  }
  final integer = RegExp(r'^(u?int)([0-9]*)$').firstMatch(type);
  if (integer != null) {
    final bits = int.parse(integer[2]!.isEmpty ? '256' : integer[2]!);
    if (bits < 8 || bits > 256 || bits % 8 != 0) {
      throw UnsupportedMethodError('Invalid ABI integer width.');
    }
    final signed = integer[1] == 'int';
    BigInt n;
    try {
      n = value is BigInt ? value : BigInt.parse(value.toString());
    } catch (_) {
      throw InvalidTransactionError('Expected ABI integer.');
    }
    final minimum = signed ? -(BigInt.one << (bits - 1)) : BigInt.zero,
        maximum = BigInt.one << (signed ? bits - 1 : bits);
    if (n < minimum || n >= maximum) {
      throw InvalidTransactionError('ABI integer overflow.');
    }
    if (n.isNegative) n += (BigInt.one << 256);
    return _word(n);
  }
  final fixed = RegExp(r'^bytes([0-9]+)$').firstMatch(type);
  if (type == 'bytes' || type == 'string' || fixed != null) {
    final bytes = type == 'string'
        ? providerBytes(
            value is String
                ? value
                : throw InvalidTransactionError('Expected ABI string.'),
          )
        : value is List<int>
        ? Uint8List.fromList(value)
        : providerUnhex(value);
    if (fixed != null) {
      final size = int.parse(fixed[1]!);
      if (size < 1 || size > 32) {
        throw UnsupportedMethodError('Invalid fixed bytes width.');
      }
      if (bytes.length != size) {
        throw InvalidTransactionError('Incorrect fixed bytes length.');
      }
      return _join([bytes, List.filled(32 - size, 0)]);
    }
    return _join([
      _word(BigInt.from(bytes.length)),
      bytes,
      List.filled((32 - bytes.length % 32) % 32, 0),
    ]);
  }
  throw UnsupportedMethodError('Unsupported ABI type: $type');
}

Uint8List _slice(Uint8List data, int offset, int length) {
  if (offset < 0 || length < 0 || offset + length > data.length) {
    throw InvalidTransactionError('ABI result is out of bounds.');
  }
  return data.sublist(offset, offset + length);
}

BigInt _read(Uint8List data, int offset) =>
    BigInt.parse(providerHex(_slice(data, offset, 32)));
int _offset(Uint8List data, int offset) {
  final n = _read(data, offset);
  if (n > BigInt.from(data.length)) {
    throw InvalidTransactionError('Invalid ABI offset/length.');
  }
  return n.toInt();
}

List<Object?> _decodeTuple(
  List<AbiParameter> parameters,
  Uint8List data,
  int base,
  Blockchain blockchain,
  int depth,
) {
  if (depth > 32 || parameters.length > 4096) {
    throw InvalidTransactionError('ABI result limit exceeded.');
  }
  var cursor = base;
  final output = <Object?>[];
  for (final p in parameters) {
    final offset = _dynamic(p) ? base + _offset(data, cursor) : cursor;
    output.add(_decode(p, data, offset, blockchain, depth + 1));
    cursor += _size(p);
  }
  return output;
}

Object? _decode(
  AbiParameter p,
  Uint8List data,
  int offset,
  Blockchain blockchain,
  int depth,
) {
  if (depth > 32) throw InvalidTransactionError('ABI nesting limit exceeded.');
  final type = _type(p), array = _array(p);
  if (array != null) {
    final n = array[2]!.isEmpty ? _offset(data, offset) : int.parse(array[2]!);
    if (n > 4096) throw InvalidTransactionError('ABI array limit exceeded.');
    return _decodeTuple(
      List.filled(n, _base(p, array[1]!)),
      data,
      offset + (array[2]!.isEmpty ? 32 : 0),
      blockchain,
      depth + 1,
    );
  }
  if (type == 'tuple') {
    return _decodeTuple(
      _parameters(p['components']),
      data,
      offset,
      blockchain,
      depth + 1,
    );
  }
  if (type == 'string' || type == 'bytes') {
    final length = _offset(data, offset);
    final bytes = _slice(data, offset + 32, length);
    return type == 'string' ? utf8.decode(bytes) : providerHex(bytes);
  }
  final word = _read(data, offset);
  if (type == 'address') {
    final width = blockchain == Blockchain.core ? 22 : 20;
    if (word >= (BigInt.one << (width * 8))) {
      throw InvalidTransactionError('Invalid ABI address padding.');
    }
    final address = word.toRadixString(16).padLeft(width * 2, '0');
    return blockchain == Blockchain.core
        ? providerAddress(address, blockchain)
        : '0x$address';
  }
  if (type == 'bool') {
    if (word > BigInt.one) {
      throw InvalidTransactionError('Invalid ABI boolean.');
    }
    return word == BigInt.one;
  }
  final integer = RegExp(r'^(u?int)([0-9]*)$').firstMatch(type);
  if (integer != null) {
    final bits = int.parse(integer[2]!.isEmpty ? '256' : integer[2]!);
    if (bits < 8 || bits > 256 || bits % 8 != 0) {
      throw UnsupportedMethodError('Invalid integer width.');
    }
    final signed = integer[1] == 'int';
    final n = signed && (word >> 255).isOdd ? word - (BigInt.one << 256) : word;
    final limit = BigInt.one << (signed ? bits - 1 : bits);
    if (n < (signed ? -limit : BigInt.zero) || n >= limit) {
      throw InvalidTransactionError('Invalid ABI integer padding.');
    }
    return n;
  }
  final fixed = RegExp(r'^bytes([0-9]+)$').firstMatch(type);
  if (fixed != null) {
    final n = int.parse(fixed[1]!);
    if (n < 1 || n > 32) {
      throw UnsupportedMethodError('Invalid fixed bytes width.');
    }
    final bytes = _slice(data, offset, 32);
    if (bytes.skip(n).any((v) => v != 0)) {
      throw InvalidTransactionError('Invalid ABI bytes padding.');
    }
    return providerHex(bytes.take(n).toList());
  }
  throw UnsupportedMethodError('Unsupported ABI type: $type');
}

String encodeWalletContract(Object? input, Blockchain blockchain) {
  final r = providerObject(input), f = _function(r);
  final parameters = _parameters(f['inputs']);
  final values = _tupleValues(parameters, r['args'] ?? []);
  final signature = '${f['name']}(${parameters.map(_signature).join(',')})';
  return providerHex(
    _join([
      providerHash(utf8.encode(signature), blockchain).sublist(0, 4),
      _encodeTuple(parameters, values, blockchain, 0),
    ]),
  );
}

Object? decodeWalletContract(Object? input, Blockchain blockchain) {
  final r = providerObject(input), f = _function(r);
  final parameters = _parameters(f['outputs']);
  final values = _decodeTuple(
    parameters,
    providerUnhex(r['data']),
    0,
    blockchain,
    0,
  );
  return parameters.length == 1 ? values.single : values;
}

Map<String, Object?> walletContractRequest(
  Object? input,
  Blockchain blockchain,
) {
  final r = providerObject(input);
  final result = {...r}
    ..remove('abi')
    ..remove('functionName')
    ..remove('args')
    ..remove('address');
  if (r['address'] != null) {
    result['to'] = providerAddress(r['address'], blockchain);
  }
  if (r['abi'] != null) result['data'] = encodeWalletContract(r, blockchain);
  return result;
}

Map<String, Object?> walletDeployment(Object? input, Blockchain blockchain) {
  final r = providerObject(input);
  final bytecode = providerUnhex(r['bytecode']);
  if (bytecode.isEmpty || r['to'] != null) {
    throw InvalidTransactionError('Invalid deployment bytecode/destination.');
  }
  final constructors = _parameters(
    r['abi'],
  ).where((p) => p['type'] == 'constructor').toList();
  if (constructors.length > 1) {
    throw InvalidTransactionError('Multiple constructors.');
  }
  final parameters = constructors.isEmpty
      ? <AbiParameter>[]
      : _parameters(constructors.single['inputs']);
  final values = _tupleValues(parameters, r['args'] ?? []);
  final result = {...r}
    ..remove('bytecode')
    ..remove('abi')
    ..remove('args');
  result['data'] = providerHex(
    _join([bytecode, _encodeTuple(parameters, values, blockchain, 0)]),
  );
  return result;
}
