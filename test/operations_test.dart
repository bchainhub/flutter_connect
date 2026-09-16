import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart' hide matches;

final fixture =
    jsonDecode(
          File('test/fixtures/operations/conformance.json').readAsStringSync(),
        )
        as Map<String, dynamic>;
final base =
    (fixture['requests'] as List).first['request'] as Map<String, dynamic>;
const origin = 'https://example.com';
Map<String, dynamic> request([Map<String, dynamic> changes = const {}]) => {
  ...jsonDecode(jsonEncode(base)) as Map<String, dynamic>,
  ...changes,
};

class Account implements WalletAccount {
  @override
  final SigningSelection selection;
  Account(WalletIdentity identity)
    : selection = SigningSelection(
        account: identity,
        profile: 'test',
        alg: null,
      );
  @override
  Future<WalletSignature> sign(Uint8List payload) async =>
      throw StateError('Authentication signer must not run');
}

class Provider implements WalletAccountProvider {
  List<WalletAccount> available;
  Provider(this.available);
  @override
  Future<List<WalletAccount>> getAccounts() async => available;
}

class Transport implements OperationTransport {
  final Future<String> Function(String) send;
  Transport(this.send);
  @override
  Future<String> exchange(String request) => send(request);
}

class Setup {
  int approved = 0, executed = 0, validated = 0;
  late final Provider provider;
  late final OperationDispatcher dispatcher;
  Setup({
    OperationApproval? approval,
    bool noApproval = false,
    FutureOr<void> Function(ConnectOperation)? validate,
    OperationHandler? handler,
    String? Function(Object)? translate,
    FutureOr<Object?> Function(ConnectOperation)? prepare,
    Object? Function(ConnectOperation, Object?)? normalize,
    Duration timeout = const Duration(seconds: 30),
    int maxRequests = 4096,
  }) {
    provider = Provider([Account(WalletIdentity.fromJson(base['account']))]);
    final chain = OperationChain.fromJson(base['chain']);
    final methods = {...OperationMethods.all, 'myapp.customOperation'};
    dispatcher = OperationDispatcher(
      adapters: [
        OperationChainAdapter(
          capabilities: [
            OperationCapability(chain.namespace, chain.reference, methods),
          ],
          handlers: {
            for (final m in methods)
              m:
                  handler ??
                  (r, c) {
                    executed++;
                    return {'ok': true};
                  },
          },
          validateAccount: (a) => a.address == base['account']['address'],
          validateOperation:
              validate ??
              (r) {
                validated++;
                if (r.params['invalid'] == true) {
                  throw OperationException('INVALID_TRANSACTION');
                }
              },
          translateError: translate,
          prepareMessage: prepare,
          normalizeResult: normalize,
        ),
      ],
      accounts: provider,
      approve: noApproval
          ? null
          : approval ??
                (r, c, p) {
                  approved++;
                  return true;
                },
      timeout: timeout,
      maxRequests: maxRequests,
    );
  }
}

void main() {
  for (final f in fixture['requests'] as List) {
    test('shared operation fixture: ${f['name']}', () {
      expect(
        jsonDecode(ConnectOperation.fromJson(f['request']).serialize()),
        f['request'],
      );
    });
  }
  test('responses, capabilities and correlation', () {
    for (final r in fixture['responses'] as List) {
      expect(
        jsonDecode(
          OperationResponse.fromJson(
            r,
            expectedRequestId: r['requestId'],
          ).serialize(),
        ),
        r,
      );
    }
    final caps = parseCapabilities(fixture['capabilities']);
    expect(caps.map((c) => c.toJson()).toList(), fixture['capabilities']);
    expect(
      supportsOperation(
        caps,
        OperationChain.fromJson(base['chain']),
        OperationMethods.signPsbt,
      ),
      isTrue,
    );
    expect(
      () => OperationResponse.fromJson(
        (fixture['responses'] as List).first,
        expectedRequestId: 'f' * 64,
      ),
      throwsA(isA<OperationException>()),
    );
    expect(
      () => parseCapabilities([
        ...(fixture['capabilities'] as List),
        ...(fixture['capabilities'] as List),
      ]),
      throwsA(isA<OperationException>()),
    );
    expect(
      () => OperationCapability('core', '1', ['wallet.unknown']),
      throwsA(isA<OperationException>()),
    );
    expect(
      ConnectOperation(
        operation: OperationMethods.getBalance,
        chain: OperationChain('core', '1'),
        params: {},
      ).requestId,
      matches(RegExp(r'^[a-f0-9]{64}$')),
    );
  });
  for (final method in {...OperationMethods.all, 'myapp.customOperation'}) {
    test('dispatch $method approval and replay', () async {
      final s = Setup();
      final response = await s.dispatcher.dispatch(
        request({'operation': method}),
        origin: origin,
      );
      expect(response.toJson(), {
        'version': 1,
        'requestId': base['requestId'],
        'result': {'ok': true},
      });
      expect(s.executed, 1);
      expect(s.approved, method.startsWith('chain.') ? 0 : 1);
      expect(
        (await s.dispatcher.dispatch(
          request({'operation': method}),
          origin: origin,
        )).error!.code,
        'UNAUTHORIZED',
      );
    });
  }
  test('multiple namespaces, references and accounts', () async {
    final entries = (fixture['requests'] as List).take(16);
    final caps = <String, OperationCapability>{};
    final accounts = <WalletAccount>[];
    for (final f in entries) {
      final r = ConnectOperation.fromJson(f['request']);
      final previous = caps[r.chain.key];
      caps[r.chain.key] = OperationCapability(
        r.chain.namespace,
        r.chain.reference,
        {...?previous?.methods, r.operation},
      );
      accounts.add(Account(r.account!));
    }
    final dispatcher = OperationDispatcher(
      adapters: [
        OperationChainAdapter(
          capabilities: caps.values,
          handlers: {
            for (final m in OperationMethods.all)
              m: (r, c) => r.account!.address,
          },
          validateAccount: (_) => true,
          validateOperation: (_) {},
        ),
      ],
      accounts: Provider(accounts),
      approve: (r, c, p) => true,
    );
    for (final f in entries) {
      expect(
        (await dispatcher.dispatch(f['request'], origin: origin)).result,
        f['request']['account']['address'],
      );
    }
    expect(
      dispatcher.supports(
        OperationChain.fromJson(base['chain']),
        OperationMethods.signTypedData,
      ),
      isFalse,
    );
  });
  final cases = <String, (Map<String, dynamic>, String)>{
    'unknown chain': (
      {
        'chain': {'namespace': 'unknown', 'reference': '1'},
        'account': null,
      },
      'UNSUPPORTED_CHAIN',
    ),
    'unknown operation': (
      {'operation': 'wallet.unknown'},
      'UNSUPPORTED_OPERATION',
    ),
    'unregistered custom': (
      {'operation': 'myapp.unknown'},
      'UNSUPPORTED_OPERATION',
    ),
    'missing account': ({'account': null}, 'UNSUPPORTED_ACCOUNT'),
    'invalid account': (
      {
        'account': {...base['account'] as Map, 'address': 'bad'},
      },
      'UNSUPPORTED_ACCOUNT',
    ),
    'mismatched account': (
      {
        'account': {...base['account'] as Map, 'reference': '2'},
      },
      'UNSUPPORTED_ACCOUNT',
    ),
    'invalid transaction': (
      {
        'params': {'invalid': true},
      },
      'INVALID_TRANSACTION',
    ),
  };
  for (final entry in cases.entries) {
    test(entry.key, () async {
      final s = Setup();
      final value = request(entry.value.$1);
      if (value['account'] == null) value.remove('account');
      expect(
        (await s.dispatcher.dispatch(value, origin: origin)).error!.code,
        entry.value.$2,
      );
      expect(s.executed, 0);
      expect(s.approved, 0);
    });
  }
  test('malformed and hostile payloads fail safely', () async {
    final malformed = <Object?>[
      null,
      [],
      '{',
      request({'version': 2}),
      request({'requestId': 'bad'}),
      request({'params': []}),
      request({
        'params': {'private_key': 'secret'},
      }),
      request({'extra': true}),
      request({'operation': 'wallet.signMessage\n'}),
      request({
        'params': {'value': double.infinity},
      }),
      request({
        'params': {'value': 9007199254740992},
      }),
      request({
        'params': {'value': 'x' * 17000},
      }),
      request({
        'params': {'__proto__': {}},
      }),
    ];
    Object deep = {};
    for (var i = 0; i < 35; i++) {
      deep = {'next': deep};
    }
    malformed.add(request({'params': deep}));
    for (final value in malformed) {
      expect(
        () => ConnectOperation.fromJson(value),
        throwsA(isA<OperationException>()),
      );
      final r = await Setup().dispatcher.dispatch(value, origin: origin);
      expect(r.error!.code, 'INVALID_PARAMS');
      expect(r.serialize().contains('secret'), isFalse);
    }
    expect(
      (await Setup().dispatcher.dispatch('{', origin: origin)).requestId,
      isNull,
    );
    expect(
      (await Setup().dispatcher.dispatch(
        request({'version': 2}),
        origin: origin,
      )).requestId,
      base['requestId'],
    );
    expect(
      () => OperationResponse.fromJson({
        ...fixture['responses'][0] as Map,
        'error': {'code': 'TIMEOUT', 'message': 'Timeout'},
      }),
      throwsA(isA<OperationException>()),
    );
  });
  test('deep snapshot resists caller mutation', () async {
    final gate = Completer<bool>();
    ConnectOperation? observed;
    final s = Setup(
      approval: (r, c, p) {
        observed = r;
        return gate.future;
      },
    );
    final value = request();
    final pending = s.dispatcher.dispatch(value, origin: origin);
    await Future<void>.delayed(Duration.zero);
    value['params']['transaction']['value'] = '999';
    expect((observed!.params['transaction'] as Map)['value'], isNot('999'));
    expect(
      () => (observed!.params['transaction'] as Map)['value'] = '999',
      throwsUnsupportedError,
    );
    gate.complete(true);
    expect((await pending).isSuccess, isTrue);
  });
  test(
    'no implicit approval, rejection, failure and account revocation',
    () async {
      final missing = Setup(noApproval: true);
      expect(
        (await missing.dispatcher.dispatch(base, origin: origin)).error!.code,
        'UNAUTHORIZED',
      );
      expect(missing.executed, 0);
      final rejected = Setup(approval: (r, c, p) => false);
      expect(
        (await rejected.dispatcher.dispatch(base, origin: origin)).error!.code,
        'USER_REJECTED',
      );
      expect(rejected.executed, 0);
      final thrown = Setup(
        approval: (r, c, p) => throw StateError('private secret'),
      );
      final r = await thrown.dispatcher.dispatch(base, origin: origin);
      expect(r.error!.code, 'UNAUTHORIZED');
      expect(r.serialize().contains('secret'), isFalse);
      late Setup revoked;
      revoked = Setup(
        approval: (r, c, p) {
          revoked.provider.available = [];
          return true;
        },
      );
      expect(
        (await revoked.dispatcher.dispatch(base, origin: origin)).error!.code,
        'UNSUPPORTED_ACCOUNT',
      );
      expect(revoked.executed, 0);
      expect(
        (await Setup().dispatcher.dispatch(
          base,
          origin: 'http://example.com',
        )).error!.code,
        'UNAUTHORIZED',
      );
    },
  );
  for (final item in {
    'wallet.signTransaction': 'SIGNING_FAILED',
    'wallet.sendTransaction': 'BROADCAST_FAILED',
    'chain.call': 'CHAIN_UNAVAILABLE',
  }.entries) {
    test('safe ${item.value}', () async {
      final s = Setup(
        handler: (r, c) => throw StateError('secret-internal-material'),
      );
      final response = await s.dispatcher.dispatch(
        request({'operation': item.key}),
        origin: origin,
      );
      expect(response.error!.code, item.value);
      expect(response.error!.message, operationErrorMessages[item.value]);
      expect(response.serialize().contains('secret'), isFalse);
    });
  }
  test('error codes, translation, preparation and normalization', () async {
    for (final code in operationErrorMessages.keys) {
      final s = Setup(validate: (_) => throw OperationException(code));
      expect(
        (await s.dispatcher.dispatch(base, origin: origin)).error!.code,
        code,
      );
    }
    final translated = Setup(
      validate: (_) => throw StateError('opaque'),
      translate: (_) => 'CHAIN_UNAVAILABLE',
    );
    expect(
      (await translated.dispatcher.dispatch(base, origin: origin)).error!.code,
      'CHAIN_UNAVAILABLE',
    );
    Object? prepared;
    final s = Setup(
      prepare: (_) => {'bytes': '0102'},
      normalize: (r, v) => 'normalized',
      approval: (r, c, p) {
        prepared = p;
        return true;
      },
    );
    expect(
      (await s.dispatcher.dispatch(
        request({'operation': OperationMethods.signMessage}),
        origin: origin,
      )).result,
      'normalized',
    );
    expect(prepared, {'bytes': '0102'});
  });
  test('timeout prevents late approval from signing', () async {
    final gate = Completer<bool>();
    final s = Setup(
      timeout: const Duration(milliseconds: 5),
      approval: (r, c, p) => gate.future,
    );
    expect(
      (await s.dispatcher.dispatch(base, origin: origin)).error!.code,
      'TIMEOUT',
    );
    gate.complete(true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(s.executed, 0);
    expect(
      (await s.dispatcher.dispatch(base, origin: origin)).error!.code,
      'UNAUTHORIZED',
    );
  });
  test('transport correlation, identities and bounded session', () async {
    final s = Setup();
    final d = OperationDispatcher(
      accounts: s.provider,
      adapters: [
        OperationChainAdapter(
          capabilities: [
            OperationCapability('core', '1', [OperationMethods.getAccounts]),
          ],
          handlers: {
            OperationMethods.getAccounts: operationAccounts(
              s.provider,
              OperationChain('core', '1'),
            ),
          },
          validateAccount: (_) => true,
          validateOperation: (_) {},
        ),
      ],
      approve: (r, c, p) => true,
    );
    expect(
      (await d.dispatch(
        request({'operation': OperationMethods.getAccounts}),
        origin: origin,
      )).result,
      [base['account']],
    );
    expect(
      (await requestOperation(
        Transport((v) => s.dispatcher.dispatchJson(v, origin: origin)),
        ConnectOperation.fromJson(base),
      )).isSuccess,
      isTrue,
    );
    await expectLater(
      requestOperation(
        Transport(
          (_) async => jsonEncode({
            ...fixture['responses'][0] as Map,
            'requestId': 'f' * 64,
          }),
        ),
        ConnectOperation.fromJson(base),
      ),
      throwsA(isA<OperationException>()),
    );
    final bounded = Setup(maxRequests: 1).dispatcher;
    await bounded.dispatch(base, origin: origin);
    expect(
      (await bounded.dispatch(
        request({'requestId': 'f' * 64}),
        origin: origin,
      )).error!.code,
      'UNAUTHORIZED',
    );
  });
  test(
    'registration, unadvertised capabilities, duplicate pending IDs and unsafe results',
    () async {
      final chain = OperationChain.fromJson(base['chain']);
      final adapter = OperationChainAdapter(
        capabilities: [
          OperationCapability(chain.namespace, chain.reference, [
            OperationMethods.getBalance,
          ]),
        ],
        handlers: {OperationMethods.getBalance: (r, c) => null},
        validateAccount: (_) => true,
        validateOperation: (_) {},
      );
      expect(
        () => OperationDispatcher(adapters: [adapter, adapter]),
        throwsA(isA<OperationException>()),
      );
      expect(
        () => OperationDispatcher(
          adapters: [
            OperationChainAdapter(
              capabilities: adapter.capabilities,
              handlers: {},
              validateAccount: (_) => true,
              validateOperation: (_) {},
            ),
          ],
        ),
        throwsA(isA<OperationException>()),
      );
      expect(
        (await OperationDispatcher(
          adapters: [adapter],
        ).dispatch(base, origin: origin)).error!.code,
        'UNSUPPORTED_OPERATION',
      );
      final gate = Completer<bool>();
      final pending = Setup(approval: (r, c, p) => gate.future);
      final first = pending.dispatcher.dispatch(base, origin: origin);
      expect(
        (await pending.dispatcher.dispatch(base, origin: origin)).error!.code,
        'UNAUTHORIZED',
      );
      gate.complete(true);
      expect((await first).isSuccess, isTrue);
      expect(pending.executed, 1);
      for (final result in [
        {'privateKey': 'secret'},
        BigInt.one,
      ]) {
        final response = await Setup(
          handler: (r, c) => result,
        ).dispatcher.dispatch(base, origin: origin);
        expect(response.error, isNotNull);
        expect(response.serialize().contains('secret'), isFalse);
      }
    },
  );
  test('shared encrypted fixture, roundtrips and tampering', () async {
    final f = fixture['encrypted'];
    final key = List<int>.filled(32, 1);
    final cipher = OperationCipher(f['origin'], f['request']['requestId'], key);
    final r = ConnectOperation.fromJson(f['request']);
    expect(
      (await cipher.openRequest(jsonEncode(f['packet']))).toJson(),
      r.toJson(),
    );
    final req = await cipher.sealRequest(r);
    expect((await cipher.openRequest(req)).toJson(), r.toJson());
    final response = OperationResponse.fromJson(fixture['responses'][0]);
    final res = await cipher.sealResponse(response);
    expect((await cipher.openResponse(res)).toJson(), response.toJson());
    await expectLater(
      cipher.openRequest(res),
      throwsA(isA<OperationException>()),
    );
    await expectLater(
      OperationCipher(
        'https://evil.example',
        r.requestId,
        key,
      ).openRequest(jsonEncode(f['packet'])),
      throwsA(isA<OperationException>()),
    );
    await expectLater(
      cipher.openRequest(
        jsonEncode({...f['packet'] as Map, 'ciphertext': 'AAAA'}),
      ),
      throwsA(isA<OperationException>()),
    );
    final input = Platform.environment['CONNECT_OPERATION_PACKETS'];
    if (input != null) {
      final p = jsonDecode(File(input).readAsStringSync());
      expect((await cipher.openRequest(p['request'])).toJson(), r.toJson());
      expect(
        (await cipher.openResponse(p['response'])).toJson(),
        response.toJson(),
      );
    }
    final output = Platform.environment['DART_OPERATION_PACKETS'];
    if (output != null) {
      File(
        output,
      ).writeAsStringSync(jsonEncode({'request': req, 'response': res}));
    }
  });
}
