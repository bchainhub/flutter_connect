@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';

@JS('window')
external JSObject get window;
@JS('BigInt')
external JSBigInt jsBigInt(JSString value);
@JS('String')
external JSString jsString(JSAny? value);
Future<JSAny?> call(
  JSObject object,
  String name, [
  List<JSAny?> args = const [],
]) async {
  final fn = object.getProperty<JSFunction>(name.toJS);
  final result = fn.callMethod<JSAny?>('apply'.toJS, object, args.toJS);
  return result != null && result.isA<JSPromise>()
      ? await (result as JSPromise<JSAny?>).toDart
      : result;
}

void main() {
  test(
    'browser ABI and large-integer token operations work on Ethereum and Core',
    () async {
      const coreAddress = "cb76c302c68a96078b5e298f219601be4efa3960b041";
      const ethereumAddress = "0x1a642f0E3c3aF545E7AcBD38b07251B3990914F1";
      for (final blockchain in ['ethereum', 'core']) {
        final address = blockchain == 'core' ? coreAddress : ethereumAddress;
        final calls = <Map>[];
        final provider = JSObject();
        provider.setProperty(
          'request'.toJS,
          ((JSObject request) {
            final r = request.dartify() as Map;
            calls.add(r);
            Object? result;
            final method = r['method'] as String;
            if (method.endsWith('_requestAccounts') ||
                method.endsWith('_accounts')) {
              result = [address];
            } else if (method == 'eth_chainId') {
              result = '0x1';
            } else if (method == 'xcb_networkId') {
              result = '1';
            } else if (method.endsWith('_call')) {
              result = '0x${42.toRadixString(16).padLeft(64, '0')}';
            } else {
              result = '0xhash';
            }
            return Future<JSAny?>.value(result.jsify()).toJS;
          }).toJS,
        );
        window.setProperty(blockchain.toJS, provider);
        final discovery = installWalletProvider(
          configure: (chain, _) => NativeWalletConfiguration(
            rpcMethods: chain == Blockchain.core
                ? coreRpcMethods
                : ethereumRpcMethods,
          ),
        );
        final api = window.getProperty<JSObject>('connect'.toJS);
        await call(api, 'connect', [
          {'blockchain': blockchain}.jsify(),
        ]);
        final abi = [
          {
            'type': 'function',
            'name': 'balanceOf',
            'inputs': [
              {'name': 'owner', 'type': 'address'},
            ],
            'outputs': [
              {'type': 'uint256'},
            ],
          },
        ];
        final encoded = await call(api, 'encodeContractCall', [
          {
            'abi': abi,
            'functionName': 'balanceOf',
            'args': [address],
          }.jsify(),
        ]);
        if (blockchain == 'core') {
          expect(
            (encoded as JSString).toDart,
            "0x1d7976f300000000000000000000cb76c302c68a96078b5e298f219601be4efa3960b041",
          );
        } else {
          expect((encoded as JSString).toDart.startsWith('0x70a08231'), true);
        }
        final balance = await call(api, 'getTokenBalance', [
          {'token': address}.jsify(),
        ]);
        expect(balance!.isA<JSBigInt>(), true);
        expect(jsString(balance).toDart, '42');
        final transfer = {'token': address, 'to': address}.jsify() as JSObject;
        transfer.setProperty(
          'amount'.toJS,
          jsBigInt('18446744073709551616'.toJS),
        );
        await call(api, 'transferToken', [transfer]);
        final sent = (calls.last['params'] as List).single as Map;
        expect(
          (sent['data'] as String).endsWith(
            BigInt.parse(
              '18446744073709551616',
            ).toRadixString(16).padLeft(64, '0'),
          ),
          true,
        );
        Object? rejected;
        try {
          await call(api, 'sendTransaction', [
            {
              'to': address,
              blockchain == 'core' ? 'networkId' : 'chainId': '0x2',
            }.jsify(),
            {'network': '0x1'}.jsify(),
          ]);
        } catch (error) {
          rejected = (error as JSObject)
              .getProperty<JSString>('name'.toJS)
              .toDart;
        }
        expect(rejected, 'NetworkMismatchError');
        if (blockchain == 'ethereum') {
          final verified = await call(api, 'verifyMessage', [
            {
              "address": "0x1a642f0E3c3aF545E7AcBD38b07251B3990914F1",
              "message": "Connect wallet actions \u2014 audit",
              "signature":
                  "0x418ef09fca13ea3ca5a4cbcf1d1f55d7e6524ab007f114b54676063515f6c4496da91df64d755cba5050c2fa79c26a1349ca77dc97790891003a8ac144ed5f831c",
            }.jsify(),
          ]);
          expect((verified as JSBoolean).toDart, true);
        }
        discovery.dispose();
        window.delete(blockchain.toJS);
      }
    },
  );
  test(
    'TON browser SDK link activates only after an authorized status event',
    () async {
      JSFunction? status;
      final provider = JSObject()..setProperty('account'.toJS, null);
      provider.setProperty(
        'connect'.toJS,
        (() => Future<JSAny?>.value('ton://pending'.toJS).toJS).toJS,
      );
      provider.setProperty(
        'sendTransaction'.toJS,
        ((JSAny? value) => Future<JSAny?>.value(value).toJS).toJS,
      );
      provider.setProperty(
        'onStatusChange'.toJS,
        ((JSFunction listener) {
          status = listener;
          return (() {
            status = null;
          }).toJS;
        }).toJS,
      );
      window.setProperty('ton'.toJS, provider);
      final discovery = installWalletProvider();
      final api = window.getProperty<JSObject>('connect'.toJS);
      expect((await call(api, 'connect') as JSString).toDart, 'ton://pending');
      expect(await call(api, 'getConnectedBlockchain'), null);
      final account = {'address': 'tonAddress', 'chain': '-239'};
      provider.setProperty('account'.toJS, account.jsify());
      status!.callAsFunction(null, {'account': account}.jsify());
      await Future<void>.delayed(Duration.zero);
      expect(
        (await call(api, 'getConnectedBlockchain') as JSString).toDart,
        'ton',
      );
      discovery.dispose();
      window.delete('ton'.toJS);
      expect(status, null);
    },
  );
}
