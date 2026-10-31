@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';

@JS('Promise.reject')
external JSPromise<JSAny?> rejected(JSAny? error);

@JS('Object.create')
external JSObject nativeObject(JSObject prototype);

@JS('window')
external JSObject get window;
Future<Object?> invoke(
  JSObject object,
  String method, [
  List<Object?> args = const [],
]) async {
  final fn = object.getProperty<JSFunction>(method.toJS);
  final value = fn.callMethod<JSAny?>('apply'.toJS, object, args.jsify());
  if (value != null && value.isA<JSPromise>()) {
    return (await (value as JSPromise<JSAny?>).toDart)?.dartify();
  }
  return value?.dartify();
}

void main() {
  test(
    'Monero and Zcash browser globals are discovered and routed independently',
    () async {
      for (final blockchain in ['monero', 'zcash']) {
        final provider = JSObject();
        provider.setProperty(
          'connect'.toJS,
          (() => Future<JSAny?>.value([blockchain].jsify()).toJS).toJS,
        );
        provider.setProperty(
          'getAccounts'.toJS,
          (() => Future<JSAny?>.value([blockchain].jsify()).toJS).toJS,
        );
        provider.setProperty(
          'getBalance'.toJS,
          (() => Future<JSAny?>.value(blockchain.toJS).toJS).toJS,
        );
        provider.setProperty(
          'signMessage'.toJS,
          ((JSString message) => Future<JSAny?>.value(
            '$blockchain:${message.toDart}'.toJS,
          ).toJS).toJS,
        );
        window.setProperty(blockchain.toJS, provider);
      }
      final discovery = installWalletProvider();
      addTearDown(() {
        discovery.dispose();
        window.delete('monero'.toJS);
        window.delete('zcash'.toJS);
      });
      final api = window.getProperty<JSObject>('connect'.toJS);
      expect(await invoke(api, 'getAvailableBlockchains'), ['monero', 'zcash']);
      await invoke(api, 'connect', [
        {'blockchain': 'monero'},
      ]);
      await invoke(api, 'connect', [
        {'blockchain': 'zcash'},
      ]);
      expect(await invoke(api, 'getConnectedBlockchain'), 'monero');
      expect(await invoke(api, 'getAccounts'), ['monero']);
      expect(
        await invoke(api, 'getBalance', [
          {'blockchain': 'zcash'},
        ]),
        'zcash',
      );
      expect(
        await invoke(api, 'signMessage', [
          'hello',
          {'blockchain': 'zcash'},
        ]),
        'zcash:hello',
      );
      expect(await invoke(api, 'getConnectedBlockchain'), 'monero');
    },
  );

  test(
    'Solana browser native transaction instances preserve identity',
    () async {
      final provider = JSObject();
      provider.setProperty(
        'connect'.toJS,
        (() => Future<JSAny?>.value(null).toJS).toJS,
      );
      provider.setProperty('publicKey'.toJS, 'solanaAddress'.toJS);
      JSAny? captured;
      provider.setProperty(
        'signTransaction'.toJS,
        ((JSAny? transaction) {
          captured = transaction;
          return Future<JSAny?>.value(transaction).toJS;
        }).toJS,
      );
      window.setProperty('solana'.toJS, provider);
      final discovery = installWalletProvider();
      final api = window.getProperty<JSObject>('connect'.toJS);
      await invoke(api, 'connect');
      final prototype = JSObject()..setProperty('version'.toJS, 'v0'.toJS);
      final tx = nativeObject(prototype)
        ..setProperty('message'.toJS, 'native'.toJS);
      final promise = api.callMethod<JSPromise<JSAny?>>(
        'signTransaction'.toJS,
        tx,
      );
      final result = await promise.toDart;
      expect(captured, tx);
      expect(result, tx);
      discovery.dispose();
      window.delete('solana'.toJS);
    },
  );

  test(
    'installed JS API discovers, selects, connects, routes and signs',
    () async {
      final evm = JSObject();
      final calls = <String>[];
      evm.setProperty(
        'request'.toJS,
        ((JSObject request) {
          final args = request.dartify() as Map;
          calls.add(args['method'] as String);
          if (args['method'] == 'personal_sign') {
            return rejected(JSObject()..setProperty('code'.toJS, 4001.toJS));
          }
          return Future<JSAny?>.value(
            (args['method'] == 'eth_chainId'
                    ? '0x1'
                    : args['method'] == 'eth_sendTransaction'
                    ? '0xhash'
                    : ['0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'])
                .jsify(),
          ).toJS;
        }).toJS,
      );
      window.setProperty('ethereum'.toJS, evm);
      final installation = installWalletProvider(
        configure: (chain, id) => NativeWalletConfiguration(
          rpcMethods: chain == Blockchain.ethereum ? ethereumRpcMethods : null,
        ),
      );
      expect(installation.installed, true);
      expect(calls, isEmpty);
      final connect = window.getProperty<JSObject>('connect'.toJS);
      expect((await invoke(connect, 'getProviders') as List).length, 1);
      await invoke(connect, 'connect');
      expect(await invoke(connect, 'getConnectedBlockchain'), 'ethereum');
      expect(await invoke(connect, 'getChainId'), '0x1');
      expect(
        await invoke(connect, 'sendTransaction', [
          {'to': '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'value': '0x1'},
        ]),
        '0xhash',
      );
      Object? errorName;
      try {
        await invoke(connect, 'signMessage', ['hello']);
      } catch (error) {
        errorName = (error as JSObject)
            .getProperty<JSString>('name'.toJS)
            .toDart;
      }
      expect(errorName, 'UserRejectedRequestError');
      expect(calls.last, 'personal_sign');
      await expectLater(
        invoke(connect, 'getBalance', [
          {'network': '0x2'},
        ]),
        throwsA(anything),
      );
      await invoke(connect, 'disconnect');
      expect(await invoke(connect, 'isConnected'), false);
      installation.dispose();
      expect(window.getProperty<JSAny?>('connect'.toJS), null);
      window.delete('ethereum'.toJS);
    },
  );
  test(
    'CIP-30 enable remains passive during discovery and preserves native CBOR',
    () async {
      var enabled = 0;
      final authorized = JSObject();
      authorized.setProperty(
        'getUsedAddresses'.toJS,
        (() => Future<JSAny?>.value(['abcd'].jsify()).toJS).toJS,
      );
      authorized.setProperty(
        'getBalance'.toJS,
        (() => Future<JSAny?>.value('cbor'.toJS).toJS).toJS,
      );
      authorized.setProperty(
        'signTx'.toJS,
        ((JSString cbor, JSBoolean partial) => Future<JSAny?>.value(
          cbor,
        ).toJS).toJS,
      );
      final wallet = JSObject();
      wallet.setProperty(
        'enable'.toJS,
        (() {
          enabled++;
          return Future<JSAny?>.value(authorized).toJS;
        }).toJS,
      );
      final cardano = JSObject()..setProperty('testWallet'.toJS, wallet);
      window.setProperty('cardano'.toJS, cardano);
      final discovery = installWalletProvider();
      expect(enabled, 0);
      final api = window.getProperty<JSObject>('connect'.toJS);
      await invoke(api, 'connect', [
        {'blockchain': 'cardano', 'providerId': 'cardano:testWallet'},
      ]);
      expect(enabled, 1);
      expect(await invoke(api, 'getBalance'), 'cbor');
      expect(
        await invoke(api, 'signTransaction', [
          {'cbor': 'abcd', 'partialSign': true},
        ]),
        'abcd',
      );
      discovery.dispose();
      window.delete('cardano'.toJS);
    },
  );
}
