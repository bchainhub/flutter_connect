import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256k1.dart';
import 'providers.dart';
import 'wallet_provider.dart';
import 'provider_abi.dart';

const coreRpcMethods = {
  'xcb_requestAccounts',
  'xcb_accounts',
  'xcb_networkId',
  'xcb_getBalance',
  'xcb_getCode',
  'xcb_getStorageAt',
  'xcb_sendTransaction',
  'xcb_signTransaction',
  'personal_sign',
  'xcb_sign',
  'xcb_signTypedData_v4',
  'xcb_call',
  'xcb_estimateEnergy',
  'xcb_energyPrice',
  'xcb_blockNumber',
  'xcb_getBlockByNumber',
  'xcb_getBlockByHash',
  'xcb_getTransactionByHash',
  'xcb_getTransactionReceipt',
  'xcb_getTransactionCount',
  'xcb_sendRawTransaction',
  'xcb_getLogs',
};
const additionalEthereumRpcMethods = {
  'eth_signTransaction',
  'eth_getCode',
  'eth_getStorageAt',
  'eth_getBlockByHash',
  'eth_feeHistory',
  'eth_maxPriorityFeePerGas',
};
String canonicalProviderNetwork(Object? value, Blockchain blockchain) =>
    [Blockchain.ethereum, Blockchain.core].contains(blockchain) &&
        RegExp(r'^(?:0x[0-9a-fA-F]+|[0-9]+)$').hasMatch(value.toString())
    ? providerQuantity(value).toString()
    : value.toString();
bool providerNetworkMatches(
  Object? value,
  Object expected,
  Blockchain blockchain,
) {
  if (value is Map) {
    if ([Blockchain.bitcoin, Blockchain.litecoin].contains(blockchain) &&
        value['enum'] != null) {
      return providerNetworkMatches(value['enum'], expected, blockchain);
    }
    final numeric = RegExp(
      r'^(?:0x[0-9a-fA-F]+|[0-9]+)$',
    ).hasMatch(expected.toString());
    final keys = blockchain == Blockchain.core
        ? ['networkId', 'chainId', 'id', 'name', 'network']
        : numeric
        ? ['chainId', 'networkId', 'id', 'chain', 'name', 'network']
        : ['name', 'network', 'cluster', 'chainId', 'networkId', 'chain', 'id'];
    for (final key in keys) {
      if (value[key] != null) {
        return providerNetworkMatches(value[key], expected, blockchain);
      }
    }
    return false;
  }
  return canonicalProviderNetwork(value, blockchain) ==
      canonicalProviderNetwork(expected, blockchain);
}

Object? assertProviderPayloadNetwork(
  Object? input,
  Object? expected,
  Blockchain blockchain,
) {
  if (input is! Map) return expected;
  final domain = input['domain'] is Map ? input['domain'] as Map : const {};
  final payload = blockchain == Blockchain.core
      ? input['networkId'] ?? domain['networkId']
      : blockchain == Blockchain.ethereum
      ? input['chainId'] ?? domain['chainId']
      : null;
  if (payload != null &&
      expected != null &&
      !providerNetworkMatches(payload, expected, blockchain)) {
    throw NetworkMismatchError(
      'Transaction or signing domain conflicts with the requested network.',
    );
  }
  return expected ?? payload;
}

bool verifyEthereumWalletMessage(Object? input) {
  final r = providerObject(input);
  final expected = providerAddress(r['address'], Blockchain.ethereum);
  final message = providerBytes(r['message']);
  final signature = providerUnhex(r['signature']);
  if (signature.length != 65 && signature.length != 64) return false;
  final bytes = signature.length == 65
      ? signature
      : Uint8List.fromList([...signature, 27 + ((signature[32] & 128) >> 7)]);
  if (signature.length == 64) bytes[32] &= 127;
  var recovery = bytes[64];
  if (recovery >= 27) recovery -= 27;
  if (recovery < 0 || recovery > 1) return false;
  final curve = ECCurve_secp256k1();
  final n = curve.n;
  final rr = BigInt.parse(providerHex(bytes.sublist(0, 32))),
      s = BigInt.parse(providerHex(bytes.sublist(32, 64)));
  if (rr <= BigInt.zero || rr >= n || s <= BigInt.zero || s > n >> 1) {
    return false;
  }
  final digest = providerHash([
    ...utf8.encode('\x19Ethereum Signed Message:\n${message.length}'),
    ...message,
  ], Blockchain.ethereum);
  try {
    final point = curve.curve.decodePoint(
      Uint8List.fromList([2 + recovery, ...bytes.sublist(0, 32)]),
    );
    if (point == null || !(point * n)!.isInfinity) return false;
    final inverse = rr.modInverse(n), e = BigInt.parse(providerHex(digest));
    final ECPoint? publicKey =
        (point * ((s * inverse) % n))! +
        (curve.G * (((-e) % n * inverse) % n))!;
    if (publicKey == null || publicKey.isInfinity) return false;
    final hash = providerHash(
      publicKey.getEncoded(false).sublist(1),
      Blockchain.ethereum,
    );
    return providerHex(hash.sublist(12)).toLowerCase() ==
        expected.toLowerCase();
  } catch (_) {
    return false;
  }
}

List<Map<String, Object?>> _tokenAbi(
  String name,
  List<String> inputs,
  List<String> outputs,
) => [
  {
    'type': 'function',
    'name': name,
    'stateMutability': 'nonpayable',
    'inputs': [
      for (var i = 0; i < inputs.length; i++)
        {'name': 'arg$i', 'type': inputs[i]},
    ],
    'outputs': [
      for (final type in outputs) {'type': type},
    ],
  },
];
Map<WalletMethod, WalletHandler> providerRpcActions({
  required Blockchain blockchain,
  required Set<String> methods,
  required Future<Object?> Function(String, Object?) request,
  required bool Function() disposed,
  required void Function(ProviderEvent) emit,
}) {
  final core = blockchain == Blockchain.core,
      prefix = blockchain == Blockchain.core ? 'xcb' : 'eth';
  final h = <WalletMethod, WalletHandler>{};
  String account(WalletCallOptions options) {
    if (options.account == null) {
      throw WalletNotConnectedError('Select an authorized account.');
    }
    final address = providerAddress(
      options.account,
      blockchain,
      core ? options.network : null,
    );
    if (core && RegExp(r'^0{43}[0-9]$').hasMatch(address)) {
      throw InvalidTransactionError('A system address cannot sign.');
    }
    return address;
  }

  String address(Object? input, WalletCallOptions options) => providerAddress(
    input is String
        ? input
        : input is Map
        ? input['address'] ?? options.address ?? options.account
        : options.address ?? options.account,
    blockchain,
  );
  Map<String, Object?> tx(Object? input, WalletCallOptions options) {
    final r = providerObject(input);
    final alias = core ? 'energyLimit' : 'gasLimit',
        units = core ? 'energy' : 'gas';
    if (r[alias] != null) {
      if (r[units] != null &&
          providerQuantity(r[units]) != providerQuantity(r[alias])) {
        throw InvalidTransactionError(
          'Conflicting transaction resource limits.',
        );
      }
      r[units] = r.remove(alias);
    }
    if (r['from'] != null) {
      r['from'] = providerAddress(
        r['from'],
        blockchain,
        core ? options.network ?? r['networkId'] : null,
      );
      if (core && RegExp(r'^0{43}[0-9]$').hasMatch(r['from'] as String)) {
        throw InvalidTransactionError(
          'A system address cannot be a transaction sender.',
        );
      }
    } else if (options.account != null) {
      r['from'] = account(options);
    }
    if (core && r['from'] != null) {
      providerAddress(r['from'], blockchain, options.network ?? r['networkId']);
    }
    if (r['to'] != null) {
      r['to'] = providerAddress(
        r['to'],
        blockchain,
        core ? options.network ?? r['networkId'] : null,
      );
    }
    if (r['from'] != null &&
        options.account != null &&
        r['from'].toString().toLowerCase() !=
            providerAddress(
              options.account,
              blockchain,
              core ? options.network : null,
            ).toLowerCase()) {
      throw InvalidTransactionError(
        'Transaction sender differs from the selected account.',
      );
    }
    if (core &&
        [
          'gas',
          'gasPrice',
          'maxFeePerGas',
          'maxPriorityFeePerGas',
          'chainId',
        ].any((k) => r[k] != null)) {
      throw InvalidTransactionError(
        'Core uses energy, energyPrice and networkId.',
      );
    }
    for (final key
        in core
            ? ['value', 'energy', 'energyPrice', 'nonce', 'networkId', 'type']
            : [
                'value',
                'gas',
                'gasPrice',
                'maxFeePerGas',
                'maxPriorityFeePerGas',
                'nonce',
                'chainId',
                'type',
                'maxFeePerBlobGas',
              ]) {
      if (r[key] != null) r[key] = providerHexQuantity(r[key]);
    }
    if (r['data'] != null) providerUnhex(r['data']);
    if (!core &&
        r['gasPrice'] != null &&
        (r['maxFeePerGas'] != null || r['maxPriorityFeePerGas'] != null)) {
      throw InvalidTransactionError(
        'Legacy gasPrice cannot be combined with EIP-1559 caps.',
      );
    }
    if (!core &&
        r['maxFeePerGas'] != null &&
        r['maxPriorityFeePerGas'] != null &&
        providerQuantity(r['maxPriorityFeePerGas']) >
            providerQuantity(r['maxFeePerGas'])) {
      throw InvalidTransactionError('Priority fee exceeds maximum fee cap.');
    }
    return r;
  }

  void bind(
    WalletMethod method,
    String native, [
    Object? Function(Object?, WalletCallOptions)? params,
  ]) {
    if (methods.contains(native)) {
      h[method] = (input, options) =>
          request(native, params?.call(input, options) ?? []);
    }
  }

  bind(WalletMethod.connect, '${prefix}_requestAccounts');
  bind(WalletMethod.getAccounts, '${prefix}_accounts');
  if (h.containsKey(WalletMethod.connect)) {
    final connect = h[WalletMethod.connect]!;
    h[WalletMethod.connect] = (input, options) async {
      final accounts = await connect(input, options);
      if (accounts is! List || accounts.isEmpty) {
        throw WalletNotConnectedError('Wallet did not authorize any accounts.');
      }
      return accounts;
    };
  }
  bind(WalletMethod.getChainId, core ? 'xcb_networkId' : 'eth_chainId');
  if (!h.containsKey(WalletMethod.connect) &&
      h.containsKey(WalletMethod.getAccounts)) {
    h[WalletMethod.connect] = (_, _) async {
      final accounts = await h[WalletMethod.getAccounts]!(
        null,
        const WalletCallOptions(),
      );
      if (accounts is! List || accounts.isEmpty) {
        throw WalletNotConnectedError(
          'No already-authorized accounts; configure the wallet account-request RPC.',
        );
      }
      return accounts;
    };
  }
  bind(
    WalletMethod.getBalance,
    '${prefix}_getBalance',
    (input, options) => [address(input, options), options.blockTag ?? 'latest'],
  );
  bind(
    WalletMethod.getCode,
    '${prefix}_getCode',
    (input, o) => [address(input, o), o.blockTag ?? 'latest'],
  );
  bind(WalletMethod.getStorage, '${prefix}_getStorageAt', (input, o) {
    final r = providerObject(input),
        position = providerQuantity(providerObject(input)['position']);
    if (position >= BigInt.one << 256) {
      throw InvalidTransactionError('Storage position exceeds 256 bits.');
    }
    return [
      address(r, o),
      providerHexQuantity(position),
      o.blockTag ?? 'latest',
    ];
  });
  bind(
    WalletMethod.getNonce,
    '${prefix}_getTransactionCount',
    (input, options) => [
      address(input, options),
      options.blockTag ?? 'pending',
    ],
  );
  bind(
    WalletMethod.sendTransaction,
    '${prefix}_sendTransaction',
    (input, options) => [tx(input, options)],
  );
  bind(
    WalletMethod.signTransaction,
    '${prefix}_signTransaction',
    (input, options) => [tx(input, options)],
  );
  if (h.containsKey(WalletMethod.signTransaction)) {
    h[WalletMethod.signTransactions] = (input, options) async {
      if (input is! List || input.isEmpty) {
        throw InvalidTransactionError('Expected transactions.');
      }
      final output = <Object?>[];
      for (final item in input) {
        output.add(await h[WalletMethod.signTransaction]!(item, options));
      }
      return output;
    };
  }
  if (h.containsKey(WalletMethod.sendTransaction)) {
    h[WalletMethod.signAndSendTransaction] = h[WalletMethod.sendTransaction]!;
  }
  if (methods.contains('personal_sign')) {
    h[WalletMethod.signMessage] = (input, options) => request('personal_sign', [
      providerHex(providerBytes(input)),
      account(options),
    ]);
  } else if (core && methods.contains('xcb_sign')) {
    h[WalletMethod.signMessage] = (input, options) => request('xcb_sign', [
      account(options),
      providerHex(providerBytes(input)),
    ]);
  }
  bind(WalletMethod.signTypedData, '${prefix}_signTypedData_v4', (
    input,
    options,
  ) {
    Map<String, Object?> data;
    try {
      data = providerObject(input is String ? jsonDecode(input) : input);
    } catch (_) {
      throw InvalidTransactionError('Expected typed data.');
    }
    final domain = providerObject(data['domain'] ?? {});
    if (core) {
      if (domain['chainId'] != null || domain['networkId'] == null) {
        throw InvalidTransactionError(
          'CIP-712 requires networkId, not chainId.',
        );
      }
      if (domain['verifyingContract'] != null) {
        providerAddress(
          domain['verifyingContract'],
          blockchain,
          domain['networkId'],
        );
      }
    }
    return [
      account(options),
      jsonEncode(
        data,
        toEncodable: (value) => value is BigInt
            ? value.toString()
            : throw InvalidTransactionError('Non-JSON typed data.'),
      ),
    ];
  });
  bind(WalletMethod.getBlockNumber, '${prefix}_blockNumber');
  bind(WalletMethod.getGasPrice, core ? 'xcb_energyPrice' : 'eth_gasPrice');
  if (methods.contains('${prefix}_getBlockByNumber') ||
      methods.contains('${prefix}_getBlockByHash')) {
    h[WalletMethod.getBlock] = (input, _) {
      final r = input is Map ? input : const {};
      final value = r['hash'] ?? r['number'] ?? input ?? 'latest';
      final hash =
          r['hash'] != null ||
          value is String && RegExp(r'^0x[0-9a-fA-F]{64}$').hasMatch(value);
      final name = '${prefix}_getBlockBy${hash ? 'Hash' : 'Number'}';
      if (!methods.contains(name)) {
        throw UnsupportedMethodError('Block query mode is not declared.');
      }
      return request(name, [
        value is int || value is BigInt ? providerHexQuantity(value) : value,
        r['includeTransactions'] == true,
      ]);
    };
  }
  Object? hash(Object? input) =>
      input is String ? input : providerObject(input)['hash'];
  bind(
    WalletMethod.getTransaction,
    '${prefix}_getTransactionByHash',
    (input, _) => [hash(input)],
  );
  bind(
    WalletMethod.getTransactionReceipt,
    '${prefix}_getTransactionReceipt',
    (input, _) => [hash(input)],
  );
  bind(WalletMethod.sendRawTransaction, '${prefix}_sendRawTransaction', (
    input,
    _,
  ) {
    if (providerUnhex(input).isEmpty) {
      throw InvalidTransactionError('Empty signed transaction.');
    }
    return [input];
  });
  bind(
    WalletMethod.estimateGas,
    core ? 'xcb_estimateEnergy' : 'eth_estimateGas',
    (input, options) => [tx(input, options)],
  );
  bind(
    WalletMethod.getContractEvents,
    '${prefix}_getLogs',
    (input, _) => [providerObject(input)],
  );
  if (!core) {
    bind(
      WalletMethod.switchNetwork,
      'wallet_switchEthereumChain',
      (input, _) => [
        {
          'chainId': providerHexQuantity(
            input is Map ? input['chainId'] : input,
          ),
        },
      ],
    );
    bind(WalletMethod.addNetwork, 'wallet_addEthereumChain', (input, _) {
      final r = providerObject(input);
      r['chainId'] = providerHexQuantity(r['chainId']);
      return [r];
    });
    bind(
      WalletMethod.watchAsset,
      'wallet_watchAsset',
      (input, _) => providerObject(input),
    );
    if (h.containsKey(WalletMethod.watchAsset)) {
      h[WalletMethod.addToken] = h[WalletMethod.watchAsset]!;
    }
  }
  h[WalletMethod.encodeContractCall] = (input, _) =>
      encodeWalletContract(input, blockchain);
  h[WalletMethod.decodeContractResult] = (input, _) =>
      decodeWalletContract(input, blockchain);
  if (methods.contains('${prefix}_call')) {
    h[WalletMethod.callContract] = (input, options) =>
        request('${prefix}_call', [
          tx(walletContractRequest(input, blockchain), options),
          options.blockTag ?? 'latest',
        ]);
    h[WalletMethod.readContract] = (input, options) async {
      final r = providerObject(input);
      final data = await h[WalletMethod.callContract]!(input, options);
      return r['abi'] != null
          ? decodeWalletContract({...r, 'data': data}, blockchain)
          : data;
    };
    h[WalletMethod.simulateTransaction] = (input, options) => request(
      '${prefix}_call',
      [tx(input, options), options.blockTag ?? 'latest'],
    );
  }
  if (h.containsKey(WalletMethod.sendTransaction)) {
    h[WalletMethod.sendContractTransaction] = (input, options) =>
        h[WalletMethod.sendTransaction]!(
          walletContractRequest(input, blockchain),
          options,
        );
    h[WalletMethod.writeContract] = h[WalletMethod.sendContractTransaction]!;
    h[WalletMethod.deployContract] = (input, options) =>
        h[WalletMethod.sendTransaction]!(
          walletDeployment(input, blockchain),
          options,
        );
    h[WalletMethod.transfer] = (input, options) {
      final r = providerObject(input);
      return h[WalletMethod.sendTransaction]!({
        'to': providerAddress(r['to'], blockchain),
        'value': providerHexQuantity(r['amount'] ?? r['value']),
      }, options);
    };
  }
  if (h.containsKey(WalletMethod.estimateGas)) {
    h[WalletMethod.estimateContractGas] = (input, options) =>
        h[WalletMethod.estimateGas]!(
          walletContractRequest(input, blockchain),
          options,
        );
  }
  if (h.containsKey(WalletMethod.estimateGas) &&
      h.containsKey(WalletMethod.getGasPrice)) {
    h[WalletMethod.estimateFee] = (input, options) async {
      final r = tx(input, options);
      if (r['maxPriorityFeePerGas'] != null && r['maxFeePerGas'] == null) {
        throw InvalidTransactionError(
          'Supply maxFeePerGas for a priority-fee estimate.',
        );
      }
      final units = providerQuantity(
        await h[WalletMethod.estimateGas]!(r, options),
      );
      final price = providerQuantity(
        r['maxFeePerGas'] ??
            r['energyPrice'] ??
            r['gasPrice'] ??
            await h[WalletMethod.getGasPrice]!(null, options),
      );
      return {
        'units': providerHexQuantity(units),
        'price': providerHexQuantity(price),
        'total': providerHexQuantity(units * price),
        'unit': 'native-base-units',
        'isUpperBound': r['maxFeePerGas'] != null,
      };
    };
    h[WalletMethod.estimateTransactionFee] = h[WalletMethod.estimateFee]!;
  }
  if (h.containsKey(WalletMethod.getNonce) ||
      h.containsKey(WalletMethod.estimateGas)) {
    h[WalletMethod.prepareTransaction] = (input, options) async {
      final r = tx(input, options);
      if (r['nonce'] == null && h.containsKey(WalletMethod.getNonce)) {
        r['nonce'] = await h[WalletMethod.getNonce]!(r['from'], options);
      }
      final units = core ? 'energy' : 'gas';
      if (r[units] == null && h.containsKey(WalletMethod.estimateGas)) {
        r[units] = await h[WalletMethod.estimateGas]!(r, options);
      }
      final price = core ? 'energyPrice' : 'gasPrice';
      if (r[price] == null &&
          r['maxFeePerGas'] == null &&
          r['maxPriorityFeePerGas'] == null &&
          h.containsKey(WalletMethod.getGasPrice)) {
        r[price] = await h[WalletMethod.getGasPrice]!(null, options);
      }
      return r;
    };
  }
  if (h.containsKey(WalletMethod.getBalance)) {
    h[WalletMethod.getBalances] = (_, options) async {
      final addresses =
          options.addresses ?? [options.address ?? account(options)];
      return Future.wait(
        addresses.map(
          (target) async => {
            'address': target,
            'balance': await h[WalletMethod.getBalance]!(target, options),
          },
        ),
      );
    };
  }
  if (h.containsKey(WalletMethod.getTransactionReceipt)) {
    h[WalletMethod.getTransactionStatus] = (input, options) async {
      final receipt = await h[WalletMethod.getTransactionReceipt]!(
        input,
        options,
      );
      if (receipt == null) {
        return {'status': 'pending-or-unknown', 'receipt': null};
      }
      final r = providerObject(receipt);
      final result = {
        'status': r['status'] == null
            ? 'mined'
            : providerQuantity(r['status']) == BigInt.zero
            ? 'reverted'
            : 'confirmed',
        'receipt': receipt,
      };
      emit(ProviderEvent('transactionStatusChanged', [result]));
      return result;
    };
    h[WalletMethod.waitForTransaction] = (input, options) async {
      final r = input is String ? {'hash': input} : providerObject(input);
      final timeout = r['timeoutMs'] ?? 30000,
          interval = r['pollIntervalMs'] ?? 1000;
      final confirmations = providerQuantity(r['confirmations'] ?? 1);
      if (timeout is! int ||
          timeout <= 0 ||
          timeout > 300000 ||
          interval is! int ||
          interval <= 0 ||
          confirmations < BigInt.one) {
        throw InvalidTransactionError('Invalid transaction polling limits.');
      }
      if (confirmations > BigInt.one &&
          !h.containsKey(WalletMethod.getBlockNumber)) {
        throw UnsupportedMethodError(
          'Confirmation counting needs block number RPC.',
        );
      }
      final deadline = DateTime.now().add(Duration(milliseconds: timeout));
      while (DateTime.now().isBefore(deadline)) {
        if (disposed()) {
          throw ProviderDisconnectedError('Provider disposed while waiting.');
        }
        final receipt = await h[WalletMethod.getTransactionReceipt]!(
          r['hash'],
          options,
        );
        if (receipt != null) {
          final result = providerObject(receipt);
          if (result['status'] != null &&
              providerQuantity(result['status']) == BigInt.zero) {
            throw TransactionFailedError(
              'Transaction reverted.',
              cause: receipt,
            );
          }
          if (confirmations == BigInt.one ||
              (result['blockNumber'] != null &&
                  providerQuantity(
                            await h[WalletMethod.getBlockNumber]!(
                              null,
                              options,
                            ),
                          ) -
                          providerQuantity(result['blockNumber']) +
                          BigInt.one >=
                      confirmations)) {
            return receipt;
          }
        }
        final remaining = deadline.difference(DateTime.now()).inMilliseconds;
        await Future<void>.delayed(
          Duration(
            milliseconds: remaining < interval
                ? (remaining > 0 ? remaining : 1)
                : interval,
          ),
        );
      }
      throw TransactionFailedError('Transaction confirmation timed out.');
    };
  }
  FutureOr<Object?> readToken(
    Map<String, Object?> r,
    WalletCallOptions options,
    String name,
    List<String> inputs,
    List<Object?> args,
    List<String> outputs,
  ) => h[WalletMethod.readContract]!({
    'address': providerAddress(r['token'] ?? r['address'], blockchain),
    'abi': _tokenAbi(name, inputs, outputs),
    'functionName': name,
    'args': args,
  }, options);
  if (h.containsKey(WalletMethod.readContract)) {
    h[WalletMethod.getTokenBalance] = (input, options) {
      final r = providerObject(input);
      return readToken(
        r,
        options,
        'balanceOf',
        ['address'],
        [
          providerAddress(
            r['owner'] ?? options.address ?? options.account,
            blockchain,
          ),
        ],
        ['uint256'],
      );
    };
    h[WalletMethod.getTokenAllowance] = (input, options) {
      final r = providerObject(input);
      return readToken(
        r,
        options,
        'allowance',
        ['address', 'address'],
        [
          providerAddress(r['owner'] ?? options.account, blockchain),
          providerAddress(r['spender'], blockchain),
        ],
        ['uint256'],
      );
    };
    h[WalletMethod.getTokenMetadata] = (input, options) async {
      final r = providerObject(input);
      return {
        'address': providerAddress(r['token'] ?? r['address'], blockchain),
        'name': await readToken(r, options, 'name', [], [], ['string']),
        'symbol': await readToken(r, options, 'symbol', [], [], ['string']),
        'decimals': providerQuantity(
          await readToken(r, options, 'decimals', [], [], ['uint8']),
        ).toInt(),
      };
    };
    h[WalletMethod.getTokenBalances] = (_, options) async {
      if (options.tokens == null || options.tokens!.isEmpty) {
        throw InvalidTransactionError('Supply tokens in call options.');
      }
      return Future.wait(
        options.tokens!.map(
          (token) async => {
            'token': token,
            'balance': await h[WalletMethod.getTokenBalance]!({
              'token': token,
            }, options),
          },
        ),
      );
    };
  }
  if (h.containsKey(WalletMethod.sendContractTransaction)) {
    FutureOr<Object?> sendToken(
      Map<String, Object?> r,
      WalletCallOptions options,
      String name,
      List<String> inputs,
      List<Object?> args,
    ) => h[WalletMethod.sendContractTransaction]!({
      'address': providerAddress(r['token'], blockchain),
      'abi': _tokenAbi(name, inputs, ['bool']),
      'functionName': name,
      'args': args,
    }, options);
    h[WalletMethod.approveToken] = (input, options) {
      final r = providerObject(input);
      return sendToken(
        r,
        options,
        'approve',
        ['address', 'uint256'],
        [
          providerAddress(r['spender'], blockchain),
          providerQuantity(r['amount']),
        ],
      );
    };
    h[WalletMethod.transferToken] = (input, options) {
      final r = providerObject(input);
      return sendToken(
        r,
        options,
        'transfer',
        ['address', 'uint256'],
        [providerAddress(r['to'], blockchain), providerQuantity(r['amount'])],
      );
    };
    h[WalletMethod.transferNFT] = (input, options) {
      final r = providerObject(input);
      final from = providerAddress(r['from'] ?? options.account, blockchain),
          to = providerAddress(
            r['to'],
            blockchain,
            core ? options.network ?? r['networkId'] : null,
          );
      if (r['standard'] == 'erc1155') {
        return sendToken(
          r,
          options,
          'safeTransferFrom',
          ['address', 'address', 'uint256', 'uint256', 'bytes'],
          [
            from,
            to,
            providerQuantity(r['tokenId']),
            providerQuantity(r['amount']),
            r['data'] ?? '0x',
          ],
        );
      }
      if (r['standard'] != null && r['standard'] != 'erc721') {
        throw UnsupportedMethodError(
          'Only ERC-721/ERC-1155 compatible contracts are mapped.',
        );
      }
      return sendToken(
        r,
        options,
        'safeTransferFrom',
        ['address', 'address', 'uint256'],
        [from, to, providerQuantity(r['tokenId'])],
      );
    };
  }
  if (!core) {
    h[WalletMethod.verifyMessage] = (input, _) =>
        verifyEthereumWalletMessage(input);
  }
  return h;
}
