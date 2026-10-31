import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';
import 'package:flutter_connect/src/provider_abi.dart';

final vectors =
    jsonDecode(File('test/fixtures/provider-actions.json').readAsStringSync())
        as Map<String, dynamic>;
final evm = (vectors['ethereumSignature'] as Map)['address'] as String;
final core = (vectors['coreSignature'] as Map)['address'] as String;

class FixtureWallet {
  final Blockchain blockchain;
  final List<Map<String, Object?>> calls = [];
  late final UniversalWalletProvider api;
  String get address => blockchain == Blockchain.core ? core : evm;
  String get prefix => blockchain == Blockchain.core ? 'xcb' : 'eth';
  FixtureWallet(
    this.blockchain, [
    Map<String, FutureOr<Object?> Function(Object?)> extra = const {},
  ]) {
    final native = NativeWalletApi(
      methods: {},
      request: (method, params) async {
        calls.add({'method': method, 'params': params});
        if (extra.containsKey(method)) return extra[method]!(params);
        if (method.endsWith('_requestAccounts') ||
            method.endsWith('_accounts')) {
          return [address];
        }
        if (method == 'eth_chainId') return '0x1';
        if (method == 'xcb_networkId') return '1';
        if (method.endsWith('_estimateGas') ||
            method.endsWith('_estimateEnergy')) {
          return '0x5208';
        }
        if (method.endsWith('_gasPrice') || method.endsWith('_energyPrice')) {
          return '0x2';
        }
        if (method.endsWith('_getBalance')) return '0x7b';
        if (method.endsWith('_getTransactionCount')) return '0x3';
        if (method.endsWith('_blockNumber')) return '0xb';
        if (method.endsWith('_getTransactionReceipt')) {
          return {'status': '0x1', 'blockNumber': '0xa'};
        }
        if (method.endsWith('_signTransaction')) return '0xsigned';
        if (method == 'personal_sign' || method.endsWith('_signTypedData_v4')) {
          return (vectors[blockchain == Blockchain.core
                  ? 'coreSignature'
                  : 'ethereumSignature']
              as Map)['signature'];
        }
        if (method.endsWith('_getLogs')) return [];
        return '0xhash';
      },
    );
    api = UniversalWalletProvider([
      NativeWalletAdapter(
        id: blockchain.name,
        blockchain: blockchain,
        nativeProvider: native,
        rpcMethods: blockchain == Blockchain.core
            ? coreRpcMethods
            : ethereumRpcMethods,
      ),
    ]);
  }
}

Object? normalized(Object? value) {
  if (value is BigInt) return value.toString();
  if (value is List) return value.map(normalized).toList();
  if (value is Map) return value.map((k, v) => MapEntry(k, normalized(v)));
  return value;
}

void main() {
  test(
    'Core private networks start at 10 and reject zero/reserved IDs',
    () async {
      final body = core.substring(4),
          decimal = '${core.substring(4)}ce00'
              .split('')
              .map((c) => int.parse(c, radix: 16).toString())
              .join();
      final address =
          'ce${(BigInt.from(98) - BigInt.parse(decimal) % BigInt.from(97)).toString().padLeft(2, '0')}$body';
      var network = 10, signed = 0;
      final f = FixtureWallet(Blockchain.core, {
        'xcb_requestAccounts': (_) => [address],
        'xcb_accounts': (_) => [address],
        'xcb_networkId': (_) => network.toString(),
        'xcb_signTransaction': (_) {
          signed++;
          return '0xsigned';
        },
      });
      await f.api.connect();
      for (final id in [10, 11, 100]) {
        network = id;
        expect(
          await f.api.signTransaction({
            'to': address,
            'networkId': id,
          }, options: WalletCallOptions(network: id)),
          '0xsigned',
        );
      }
      expect(signed, 3);
      for (final id in [0, 2, 5, 9]) {
        network = id;
        await expectLater(
          f.api.signTransaction({
            'to': address,
            'networkId': id,
          }, options: WalletCallOptions(network: id)),
          throwsA(isA<InvalidTransactionError>()),
        );
      }
      expect(signed, 3);
      final system = '0' * 44;
      expect(providerAddress(system, Blockchain.core, 10), system);
      expect(
        () => providerAddress(system, Blockchain.core, 0),
        throwsA(isA<InvalidTransactionError>()),
      );
      f.api.dispose();
    },
  );

  test(
    'CoreBC native bytecode/storage methods retain positional arguments',
    () async {
      final calls = <List<Object?>>[];
      final api = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'corebc',
          blockchain: Blockchain.core,
          nativeProvider: NativeWalletApi(
            methods: {
              'getCode': (args) async {
                calls.add(args);
                return '0x6000';
              },
              'getStorage': (args) async {
                calls.add(args);
                return '0x01';
              },
            },
          ),
        ),
      ]);
      expect(
        await api.getCode(
          core,
          options: const WalletCallOptions(blockTag: 'pending'),
        ),
        '0x6000',
      );
      expect(await api.getStorage({'address': core, 'position': 15}), '0x01');
      expect(calls, [
        [core, 'pending'],
        [core, BigInt.from(15), 'latest'],
      ]);
      api.dispose();
    },
  );

  for (final chain in [Blockchain.core, Blockchain.ethereum]) {
    test(
      '${chain.name}: bytecode and storage RPC parameters match CoreBC',
      () async {
        final prefix = chain == Blockchain.core ? 'xcb' : 'eth';
        final f = FixtureWallet(chain, {
          '${prefix}_getCode': (_) => '0x6000',
          '${prefix}_getStorageAt': (_) => '0x01',
        });
        expect(
          await f.api.getCode({
            'address': f.address,
          }, options: const WalletCallOptions(blockTag: 'pending')),
          '0x6000',
        );
        expect(
          await f.api.getStorage({
            'address': f.address,
            'position': BigInt.from(15),
          }),
          '0x01',
        );
        expect(f.calls.last['params'], [f.address, '0xf', 'latest']);
        final before = f.calls.length;
        await expectLater(
          f.api.getStorage({
            'address': f.address,
            'position': BigInt.one << 256,
          }),
          throwsA(isA<InvalidTransactionError>()),
        );
        expect(f.calls.length, before);
        f.api.dispose();
      },
    );
  }

  test(
    'Core ICAN network context rejects cross-network destinations and domains',
    () async {
      final body = core.substring(4),
          decimal = '${core.substring(4)}ab00'
              .split('')
              .map((c) => int.parse(c, radix: 16).toString())
              .join();
      final devin =
          'ab${(BigInt.from(98) - BigInt.parse(decimal) % BigInt.from(97)).toString().padLeft(2, '0')}$body';
      final wallet = FixtureWallet(Blockchain.core);
      await wallet.api.connect();
      await expectLater(
        wallet.api.sendTransaction({'to': devin, 'networkId': 1}),
        throwsA(isA<NetworkMismatchError>()),
      );
      await expectLater(
        wallet.api.signTypedData({
          'domain': {'networkId': 1, 'verifyingContract': devin},
          'types': {},
          'message': {},
        }),
        throwsA(isA<NetworkMismatchError>()),
      );
      expect(
        wallet.calls.any(
          (r) =>
              r['method'] == 'xcb_sendTransaction' ||
              r['method'] == 'xcb_signTypedData_v4',
        ),
        false,
      );
      wallet.api.dispose();
    },
  );
  test('disposal stops subsequent native SDK batch signing', () async {
    final pending = Completer<Object?>(), started = Completer<void>();
    var signed = 0;
    final api = UniversalWalletProvider([
      NativeWalletAdapter(
        id: 'sdk',
        blockchain: Blockchain.core,
        nativeProvider: NativeWalletApi(
          methods: {
            'connect': (_) async => [core],
            'getAccounts': (_) async => [core],
            'signTransaction': (args) async {
              signed++;
              started.complete();
              await pending.future;
              return args.single;
            },
          },
        ),
      ),
    ]);
    await api.connect();
    final batch = api.signTransactions([
      {'to': core},
      {'to': core},
    ]);
    await started.future;
    api.dispose();
    pending.complete();
    await expectLater(batch, throwsA(isA<ProviderDisconnectedError>()));
    expect(signed, 1);
  });

  test(
    'resource aliases and prefixed Core accounts remain compatible',
    () async {
      final wallet = FixtureWallet(Blockchain.core, {
        'xcb_accounts': (_) => ['0x${core.toUpperCase()}'],
        'xcb_requestAccounts': (_) => ['0x${core.toUpperCase()}'],
      });
      final api = wallet.api;
      await api.connect();
      await api.signTransaction({
        'to': '0x$core',
        'from': '0x$core',
        'energyLimit': BigInt.from(30000),
        'type': 0,
      }, options: WalletCallOptions(account: core));
      final tx = (wallet.calls.last['params'] as List).single as Map;
      expect(tx['energy'], '0x7530');
      expect(tx['energyLimit'], null);
      expect(tx['type'], '0x0');
      expect(tx['from'], core);
      await expectLater(
        api.signTransaction({'to': core, 'energy': '0x1', 'energyLimit': 2}),
        throwsA(isA<InvalidTransactionError>()),
      );
      api.dispose();
      final eth = FixtureWallet(Blockchain.ethereum);
      await eth.api.connect();
      await eth.api.signTransaction({
        'to': evm,
        'gasLimit': BigInt.from(21000),
        'type': 2,
      });
      final evmTx = (eth.calls.last['params'] as List).single as Map;
      expect(evmTx['gas'], '0x5208');
      expect(evmTx['type'], '0x2');
      eth.api.dispose();
      final sdk = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'sdk',
          blockchain: Blockchain.ethereum,
          nativeProvider: NativeWalletApi(
            methods: {
              'connect': (_) async => [evm],
              'getAccounts': (_) async => [evm],
              'signTransaction': (args) async => args.single,
            },
          ),
        ),
      ]);
      await sdk.connect();
      final native = {'to': evm, 'value': BigInt.two};
      expect(identical(await sdk.signTransaction(native), native), true);
      expect((await sdk.signTransactions([native, native]) as List).length, 2);
      sdk.dispose();
    },
  );

  test('EIP-1559 fee bounds preserve caps and reject mixed models', () async {
    final wallet = FixtureWallet(Blockchain.ethereum);
    final client = wallet.api;
    await client.connect();
    final tx = {
      'to': evm,
      'maxFeePerGas': '0x5',
      'maxPriorityFeePerGas': '0x2',
    };
    final fee = await client.estimateFee(tx) as Map;
    expect(fee['isUpperBound'], true);
    expect(fee['total'], '0x19a28');
    final prepared = await client.prepareTransaction(tx) as Map;
    expect(prepared['maxFeePerGas'], '0x5');
    expect(prepared['gasPrice'], null);
    await expectLater(
      client.sendTransaction({...tx, 'gasPrice': '0x1'}),
      throwsA(isA<InvalidTransactionError>()),
    );
    await expectLater(
      client.sendTransaction({...tx, 'maxPriorityFeePerGas': '0x6'}),
      throwsA(isA<InvalidTransactionError>()),
    );
    client.dispose();
  });

  test(
    'Cardano batch signing returns witnesses without implicit submission',
    () async {
      var submissions = 0;
      final authorized = NativeWalletApi(
        methods: {
          'getUsedAddresses': (_) async => ['abcd'],
          'signTx': (args) async => 'witness:${args.first}',
          'getCollateral': (_) async => ['cborUtxo'],
          'submitTx': (_) async {
            submissions++;
            return 'txid';
          },
        },
      );
      final api = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'cardano',
          blockchain: Blockchain.cardano,
          nativeProvider: NativeWalletApi(
            methods: {'enable': (_) async => authorized},
          ),
        ),
      ]);
      await api.connect();
      expect(await api.signTransactions(['abcd', 'aabb']), [
        'witness:abcd',
        'witness:aabb',
      ]);
      expect(submissions, 0);
      expect(await api.request(method: 'getCollateral'), ['cborUtxo']);
      await expectLater(
        api.sendTransaction('abcd'),
        throwsA(isA<UnsupportedMethodError>()),
      );
      api.dispose();
    },
  );

  test('broadcast guards span aliases and provider-wide request IDs', () async {
    final pending = Completer<Object?>();
    final wallet = FixtureWallet(Blockchain.ethereum, {
      'eth_sendTransaction': (_) => pending.future,
    });
    final api = wallet.api;
    await api.connect();
    final first = api.sendTransaction({'to': evm, 'value': '0x1'});
    await expectLater(
      api
          .signAndSendTransaction({'value': '0x1', 'to': evm})
          .timeout(const Duration(milliseconds: 100)),
      throwsA(isA<InvalidTransactionError>()),
    );
    pending.complete('0xhash');
    await first;
    await api.sendTransaction({
      'to': evm,
      'value': '0x2',
    }, options: const WalletCallOptions(requestId: 'once'));
    await expectLater(
      api.request(
        method: 'eth_sendTransaction',
        params: [
          {'to': evm, 'value': '0x2'},
        ],
        options: const WalletCallOptions(requestId: 'once'),
      ),
      throwsA(isA<InvalidTransactionError>()),
    );
    api.dispose();
  });

  test('TON SDK remains pending until status confirmation', () async {
    Object? account;
    final events = StreamController<ProviderEvent>.broadcast(sync: true);
    final native = NativeWalletApi(
      methods: {
        'connect': (_) async => 'ton://connect?request=example',
        'sendTransaction': (args) async => args.single,
        'disconnect': (_) async {
          account = null;
          return null;
        },
      },
      property: (name) => name == 'account' ? account : null,
      events: events.stream,
      asynchronousConnection: true,
    );
    final api = UniversalWalletProvider([
      NativeWalletAdapter(
        id: 'ton',
        blockchain: Blockchain.ton,
        nativeProvider: native,
      ),
    ]);
    expect(
      await api.connect(options: const WalletCallOptions(network: '-239')),
      'ton://connect?request=example',
    );
    expect(api.getConnectedProvider(), null);
    expect(api.isConnected(), false);
    await expectLater(
      api.sendTransaction({'messages': []}),
      throwsA(isA<WalletNotConnectedError>()),
    );
    account = {'address': 'tonAddress', 'chain': '-239'};
    events.add(
      ProviderEvent('connect', [
        {'account': account},
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    expect(api.getConnectedBlockchain(), Blockchain.ton);
    expect(await api.sendTransaction({'messages': []}), {'messages': []});
    await api.disconnect();
    expect(api.getConnectedProvider(), null);
    api.dispose();
    await events.close();
  });
  test('Core ABI handles real zero system address', () async {
    final wallet = FixtureWallet(Blockchain.core);
    final abi = [
      {
        'type': 'function',
        'name': 'system',
        'inputs': [
          {'type': 'address'},
        ],
        'outputs': [
          {'type': 'address'},
        ],
      },
    ];
    final zero = List.filled(44, '0').join();
    final encoded =
        await wallet.api.encodeContractCall({
              'abi': abi,
              'functionName': 'system',
              'args': [zero],
            })
            as String;
    expect(encoded.substring(10), List.filled(64, '0').join());
    expect(
      await wallet.api.decodeContractResult({
        'abi': abi,
        'functionName': 'system',
        'data': '0x${List.filled(64, '0').join()}',
      }),
      zero,
    );
    wallet.api.dispose();
  });

  for (final raw in vectors['cases'] as List) {
    final vector = Map<String, Object?>.from(raw as Map);
    final blockchain = Blockchain.values.byName(vector['blockchain'] as String);
    test(
      'independent ABI vector: ${blockchain.name} ${vector['functionName']}',
      () async {
        final wallet = FixtureWallet(blockchain);
        final api = wallet.api;
        expect(await api.encodeContractCall(vector), vector['encoded']);
        final output = await api.decodeContractResult(vector);
        final count =
            (((vector['abi'] as List).first as Map)['outputs'] as List).length;
        expect(normalized(count == 1 ? [output] : output), vector['decoded']);
        api.dispose();
      },
    );
  }
  for (final blockchain in [Blockchain.ethereum, Blockchain.core]) {
    test(
      '${blockchain.name}: native signing, transactions, fees, contracts, receipts and network validation',
      () async {
        final wallet = FixtureWallet(blockchain);
        final client = wallet.api;
        await client.connect();
        expect(
          await client.getChainId(),
          blockchain == Blockchain.core ? '1' : '0x1',
        );
        expect(await client.getBalance(), '0x7b');
        final tx = {
          'to': wallet.address,
          'value': BigInt.two,
          blockchain == Blockchain.core ? 'networkId' : 'chainId': '0x1',
        };
        expect(await client.signTransaction(tx), '0xsigned');
        expect(await client.signTransactions([tx, tx]), [
          '0xsigned',
          '0xsigned',
        ]);
        expect(await client.signAndSendTransaction(tx), '0xhash');
        expect(wallet.calls.last['method'], '${wallet.prefix}_sendTransaction');
        final sent = ((wallet.calls.last['params'] as List).single as Map);
        expect(sent['value'], '0x2');
        expect(sent['from'], wallet.address);
        expect(await client.sendRawTransaction('0xaabb'), '0xhash');
        final prepared = await client.prepareTransaction(tx) as Map;
        expect(prepared['nonce'], '0x3');
        expect(
          prepared[blockchain == Blockchain.core ? 'energy' : 'gas'],
          '0x5208',
        );
        expect(await client.estimateFee(tx), {
          'units': '0x5208',
          'price': '0x2',
          'total': '0xa410',
          'unit': 'native-base-units',
          'isUpperBound': false,
        });
        expect(
          (await client.estimateTransactionFee(tx) as Map)['total'],
          '0xa410',
        );
        await client.transfer({
          'to': wallet.address,
          'amount': BigInt.from(123),
        });
        expect(
          ((wallet.calls.last['params'] as List).single as Map)['value'],
          '0x7b',
        );
        await client.deployContract({
          'bytecode': '0x6000',
          'abi': [
            {
              'type': 'constructor',
              'inputs': [
                {'name': 'n', 'type': 'uint256'},
              ],
            },
          ],
          'args': [BigInt.from(42)],
        });
        final deploy = (wallet.calls.last['params'] as List).single as Map;
        expect(deploy['to'], null);
        expect(
          deploy['data'],
          '0x6000${BigInt.from(42).toRadixString(16).padLeft(64, '0')}',
        );
        await client.getBlock({
          'hash': '0x${List.filled(64, '1').join()}',
          'includeTransactions': true,
        });
        expect(wallet.calls.last['method'], '${wallet.prefix}_getBlockByHash');
        expect(
          (await client.getTransactionStatus('hash') as Map)['status'],
          'confirmed',
        );
        expect(
          (await client.waitForTransaction({
                'hash': 'hash',
                'confirmations': 2,
                'timeoutMs': 50,
                'pollIntervalMs': 1,
              })
              as Map)['blockNumber'],
          '0xa',
        );
        final typed = {
          'domain': {
            blockchain == Blockchain.core ? 'networkId' : 'chainId': 1,
            'verifyingContract': wallet.address,
          },
          'types': {},
          'primaryType': 'Message',
          'message': {},
        };
        await client.signTypedData(typed);
        expect(
          wallet.calls.last['method'],
          '${wallet.prefix}_signTypedData_v4',
        );
        final count = wallet.calls.length;
        final bad = {
          ...tx,
          blockchain == Blockchain.core ? 'networkId' : 'chainId': '0x2',
        };
        await expectLater(
          client.sendTransaction(
            bad,
            options: const WalletCallOptions(network: 1),
          ),
          throwsA(isA<NetworkMismatchError>()),
        );
        await expectLater(
          client.request(
            method: '${wallet.prefix}_sendTransaction',
            params: [bad],
            options: const WalletCallOptions(network: 1),
          ),
          throwsA(isA<NetworkMismatchError>()),
        );
        expect(wallet.calls.length, count);
        await expectLater(
          client.signMessage({'not': 'message'}),
          throwsA(isA<InvalidTransactionError>()),
        );
        await expectLater(
          client.signTypedData({
            ...typed,
            'domain': {
              blockchain == Blockchain.core ? 'networkId' : 'chainId': 2,
            },
          }),
          throwsA(isA<NetworkMismatchError>()),
        );
        if (blockchain == Blockchain.core) {
          await expectLater(
            client.signTypedData({
              ...typed,
              'domain': {'chainId': 1},
            }),
            throwsA(isA<InvalidTransactionError>()),
          );
          await expectLater(
            client.sendTransaction({'to': wallet.address, 'gas': '0x1'}),
            throwsA(isA<InvalidTransactionError>()),
          );
        } else {
          expect(
            await client.verifyMessage(vectors['ethereumSignature']),
            true,
          );
          expect(
            await client.verifyMessage({
              ...vectors['ethereumSignature'] as Map,
              'message': 'tampered',
            }),
            false,
          );
          await client.addNetwork({
            'chainId': '0x2',
            'rpcUrls': ['https://rpc.example'],
          });
          expect(wallet.calls.last['method'], 'wallet_addEthereumChain');
          await client.switchNetwork(2);
          expect(wallet.calls.last['params'], [
            {'chainId': '0x2'},
          ]);
        }
        client.dispose();
      },
    );
    test(
      '${blockchain.name}: token reads, approvals, transfers and NFT calldata',
      () async {
        final prefix = blockchain == Blockchain.core ? 'xcb' : 'eth';
        String selector(String signature) => providerHex(
          providerHash(utf8.encode(signature), blockchain).sublist(0, 4),
        );
        String stringData(String text) {
          final bytes = utf8.encode(text);
          return '0x${32.toRadixString(16).padLeft(64, '0')}${bytes.length.toRadixString(16).padLeft(64, '0')}${providerHex(bytes).substring(2).padRight(((bytes.length + 31) ~/ 32) * 64, '0')}';
        }

        final wallet = FixtureWallet(blockchain, {
          '${prefix}_call': (params) {
            final data = ((params as List).first as Map)['data'] as String;
            if (data.startsWith(selector('name()'))) {
              return stringData('Example Token');
            }
            if (data.startsWith(selector('symbol()'))) return stringData('EXT');
            return '0x${(data.startsWith(selector('decimals()')) ? 18 : 42).toRadixString(16).padLeft(64, '0')}';
          },
        });
        final api = wallet.api;
        await api.connect();
        expect(
          await api.getTokenBalance({'token': wallet.address}),
          BigInt.from(42),
        );
        expect(
          await api.getTokenAllowance({
            'token': wallet.address,
            'spender': wallet.address,
          }),
          BigInt.from(42),
        );
        expect(
          await api.getTokenBalances(
            options: WalletCallOptions(tokens: [wallet.address]),
          ),
          [
            {'token': wallet.address, 'balance': BigInt.from(42)},
          ],
        );
        expect(await api.getTokenMetadata({'token': wallet.address}), {
          'address': wallet.address,
          'name': 'Example Token',
          'symbol': 'EXT',
          'decimals': 18,
        });
        await api.approveToken({
          'token': wallet.address,
          'spender': wallet.address,
          'amount': BigInt.from(10),
        });
        expect(
          (((wallet.calls.last['params'] as List).single as Map)['data']
                  as String)
              .startsWith(selector('approve(address,uint256)')),
          true,
        );
        await api.transferToken({
          'token': wallet.address,
          'to': wallet.address,
          'amount': BigInt.from(5),
        });
        await api.transferNFT({
          'token': wallet.address,
          'to': wallet.address,
          'tokenId': BigInt.from(7),
        });
        expect(
          (((wallet.calls.last['params'] as List).single as Map)['data']
                  as String)
              .startsWith(
                selector('safeTransferFrom(address,address,uint256)'),
              ),
          true,
        );
        expect(
          await api.getBalances(
            options: WalletCallOptions(addresses: [wallet.address]),
          ),
          [
            {'address': wallet.address, 'balance': '0x7b'},
          ],
        );
        api.dispose();
      },
    );
  }
  test(
    'Core native networkId responses normalize; request-only Core providers connect',
    () async {
      final api = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'sdk',
          blockchain: Blockchain.core,
          nativeProvider: NativeWalletApi(
            methods: {
              'connect': (_) async => [core],
              'getNetwork': (_) async => {'networkId': 1},
              'getBalance': (_) async => '123',
            },
          ),
        ),
      ]);
      await api.connect();
      expect(
        await api.getBalance(options: const WalletCallOptions(network: 1)),
        '123',
      );
      api.dispose();
      final client = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'rpc',
          blockchain: Blockchain.core,
          nativeProvider: NativeWalletApi(
            methods: {},
            request: (method, _) async =>
                method == 'xcb_networkId' ? '1' : [core],
          ),
        ),
      ]);
      await client.connect(options: const WalletCallOptions(network: 1));
      expect(await client.getAccounts(), [core]);
      client.dispose();
    },
  );
  test('receipt polling stops on reversion, timeout and disposal', () async {
    var count = 0;
    final wallet = FixtureWallet(Blockchain.ethereum, {
      'eth_getTransactionReceipt': (_) =>
          ++count < 2 ? null : {'status': '0x1', 'blockNumber': '0xa'},
    });
    expect(
      (await wallet.api.waitForTransaction({
            'hash': 'hash',
            'pollIntervalMs': 1,
            'timeoutMs': 100,
          })
          as Map)['status'],
      '0x1',
    );
    wallet.api.dispose();
    final reverted = FixtureWallet(Blockchain.ethereum, {
      'eth_getTransactionReceipt': (_) => {'status': '0x0'},
    });
    await expectLater(
      reverted.api.waitForTransaction('hash'),
      throwsA(isA<TransactionFailedError>()),
    );
    reverted.api.dispose();
    final timed = FixtureWallet(Blockchain.ethereum, {
      'eth_getTransactionReceipt': (_) => null,
    });
    await expectLater(
      timed.api.waitForTransaction({
        'hash': 'hash',
        'timeoutMs': 5,
        'pollIntervalMs': 1,
      }),
      throwsA(isA<TransactionFailedError>()),
    );
    timed.api.dispose();
  });
  test(
    'UTXO, Monero, Aptos, NEAR and Zcash native methods remain chain-specific',
    () async {
      for (final blockchain in [Blockchain.bitcoin, Blockchain.litecoin]) {
        final native = NativeWalletApi(
          methods: {
            'requestAccounts': (_) async => ['address'],
            'getAccounts': (_) async => ['address'],
            'signPsbt': (args) async => args,
            'signPsbts': (args) async => args,
            'signMessage': (args) async => args,
            blockchain == Blockchain.bitcoin
                ? 'sendBitcoin'
                : 'sendLitecoin': (args) async =>
                args,
          },
        );
        final api = UniversalWalletProvider([
          NativeWalletAdapter(
            id: blockchain.name,
            blockchain: blockchain,
            nativeProvider: native,
          ),
        ]);
        await api.connect();
        expect(
          await api.signPSBT({
            'psbt': 'native',
            'options': {'autoFinalized': false},
          }),
          [
            'native',
            {'autoFinalized': false},
          ],
        );
        expect(
          await api.signPSBTs({
            'psbts': ['a', 'b'],
            'options': [{}],
          }),
          [
            ['a', 'b'],
            [{}],
          ],
        );
        expect(
          await api.signMessage({'message': 'hello', 'type': 'bip322-simple'}),
          ['hello', 'bip322-simple'],
        );
        expect(
          await api.transfer({
            'to': 'address',
            'amount': 123,
            'options': {'feeRate': 2},
          }),
          [
            'address',
            123,
            {'feeRate': 2},
          ],
        );
        api.dispose();
      }
      final monero = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'monero',
          blockchain: Blockchain.monero,
          nativeProvider: NativeWalletApi(
            methods: {
              'connect': (_) async => [],
              'getPrimaryAddress': (_) async => 'monero',
              'getPublicSpendKey': (_) async => 'public',
              'relayTx': (args) async => args.single,
            },
          ),
        ),
      ]);
      await monero.connect();
      expect(await monero.getAddress(), 'monero');
      expect(await monero.getPublicKey(), 'public');
      expect(await monero.sendRawTransaction('metadata'), 'metadata');
      monero.dispose();
      final aptos = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'aptos',
          blockchain: Blockchain.aptos,
          nativeProvider: NativeWalletApi(
            methods: {
              'connect': (_) async => [],
              'account': (_) async => {
                'address': 'aptos',
                'publicKey': 'public',
              },
              'network': (_) async => {'name': 'testnet', 'chainId': 2},
              'signAndSubmitTransaction': (args) async => args.single,
            },
          ),
        ),
      ]);
      await aptos.connect();
      expect(await aptos.getPublicKey(), 'public');
      expect(
        await aptos.sendTransaction({
          'native': true,
        }, options: const WalletCallOptions(network: 'testnet')),
        {'native': true},
      );
      aptos.dispose();
      final near = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'near',
          blockchain: Blockchain.near,
          nativeProvider: NativeWalletApi(
            methods: {
              'signIn': (_) async => [],
              'signAndSendTransaction': (args) async => args.single,
            },
          ),
        ),
      ]);
      await near.connect();
      expect(
        await near.sendTransaction({'receiverId': 'contract', 'actions': []}),
        {'receiverId': 'contract', 'actions': []},
      );
      await expectLater(
        near.signTransactions([{}]),
        throwsA(isA<UnsupportedMethodError>()),
      );
      near.dispose();
      final zcash = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'zcash',
          blockchain: Blockchain.zcash,
          nativeProvider: NativeWalletApi(
            methods: {
              'connect': (_) async => [],
              'signTransaction': (args) async => args.single,
            },
          ),
        ),
      ]);
      await zcash.connect();
      final shielded = Object();
      expect(
        identical(
          (await zcash.signTransactions([shielded]) as List).single,
          shielded,
        ),
        true,
      );
      await expectLater(
        zcash.signPSBT('bitcoin'),
        throwsA(isA<UnsupportedMethodError>()),
      );
      zcash.dispose();
    },
  );
}
