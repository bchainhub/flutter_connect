@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';

@JS('window')
external JSObject get window;
@JS('Event')
extension type BrowserEvent._(JSObject _) implements JSObject {
  external BrowserEvent(String type);
}

class Echo implements OperationTransport {
  @override
  Future<String> exchange(String input) async {
    final request = ConnectOperation.fromJson(input);
    return OperationResponse.success(
      request.requestId,
      request.chain.namespace,
    ).serialize();
  }
}

void main() {
  test('incumbent globals and provider event subscriptions', () async {
    final incumbent = JSObject();
    window.setProperty('core'.toJS, incumbent);
    window.setProperty('connect'.toJS, incumbent);
    final events = StreamController<ProviderEvent>(sync: true);
    JSObject? announced;
    final observer = ((JSObject event) {
      announced = event
          .getProperty<JSObject>('detail'.toJS)
          .getProperty<JSObject>('provider'.toJS);
    }).toJS;
    window.callMethod<JSAny?>(
      'addEventListener'.toJS,
      'cip6963:announceProvider'.toJS,
      observer,
    );
    final dispose = injectProviders(
      providers: {
        Blockchain.core: InjectedProvider(
          request: (_, _) async => null,
          events: events.stream,
        ),
      },
      connect: UniversalProvider(routes: {}),
    );
    expect(window.getProperty<JSAny?>('core'.toJS), incumbent);
    expect(window.getProperty<JSAny?>('connect'.toJS), incumbent);
    var received = 0;
    final listener = ((JSAny? value) {
      received++;
    }).toJS;
    announced!.callMethod<JSAny?>('on'.toJS, 'accountsChanged'.toJS, listener);
    events.add(
      ProviderEvent('accountsChanged', [
        ['account'],
      ]),
    );
    expect(received, 1);
    announced!.callMethod<JSAny?>(
      'removeListener'.toJS,
      'accountsChanged'.toJS,
      listener,
    );
    events.add(ProviderEvent('accountsChanged', [[]]));
    expect(received, 1);
    dispose();
    expect(window.getProperty<JSAny?>('core'.toJS), incumbent);
    expect(window.getProperty<JSAny?>('connect'.toJS), incumbent);
    window.delete('core'.toJS);
    window.delete('connect'.toJS);
    window.callMethod<JSAny?>(
      'removeEventListener'.toJS,
      'cip6963:announceProvider'.toJS,
      observer,
    );
    await events.close();
  });
  test(
    'browser injection, rediscovery, routing override and cleanup',
    () async {
      final announcements = <JSObject>[];
      final listener = ((JSObject event) {
        announcements.add(event.getProperty<JSObject>('detail'.toJS));
      }).toJS;
      window.callMethod<JSAny?>(
        'addEventListener'.toJS,
        'cip6963:announceProvider'.toJS,
        listener,
      );
      final connect = UniversalProvider(
        routes: {
          Blockchain.core: BlockchainRoute(
            chain: OperationChain('core', '1'),
            transport: Echo(),
          ),
          Blockchain.ethereum: BlockchainRoute(
            chain: OperationChain('eip155', '1'),
            transport: Echo(),
          ),
        },
      );
      var calls = 0;
      final dispose = injectProviders(
        providers: {
          for (final chain in Blockchain.values)
            chain: InjectedProvider(
              request: (method, params) async {
                calls++;
                return [chain.name];
              },
            ),
        },
        connect: connect,
      );
      expect(announcements.length, 1);
      expect(calls, 0);
      final uuid = announcements.first
          .getProperty<JSObject>('info'.toJS)
          .getProperty<JSString>('uuid'.toJS)
          .toDart;
      window.callMethod<JSAny?>(
        'dispatchEvent'.toJS,
        BrowserEvent('cip6963:requestProvider'),
      );
      expect(announcements.length, 2);
      expect(
        announcements.last
            .getProperty<JSObject>('info'.toJS)
            .getProperty<JSString>('uuid'.toJS)
            .toDart,
        uuid,
      );
      for (final chain in Blockchain.values) {
        final provider = window.getProperty<JSObject>(chain.name.toJS);
        expect(provider.getProperty<JSAny?>('on'.toJS), isNotNull);
        final result = await provider
            .callMethod<JSPromise<JSAny?>>(
              'request'.toJS,
              {'method': 'accounts'}.jsify(),
            )
            .toDart;
        expect(result.dartify(), [chain.name]);
      }
      final universal = window.getProperty<JSObject>('connect'.toJS);
      final result = await universal
          .callMethod<JSPromise<JSAny?>>(
            'request'.toJS,
            {
              'method': OperationMethods.getBlock,
              'blockchain': 'ethereum',
            }.jsify(),
          )
          .toDart;
      expect(result.dartify(), 'eip155');
      dispose();
      dispose();
      expect(window.getProperty<JSAny?>('core'.toJS), isNull);
      expect(window.getProperty<JSAny?>('connect'.toJS), isNull);
      window.callMethod<JSAny?>(
        'dispatchEvent'.toJS,
        BrowserEvent('cip6963:requestProvider'),
      );
      expect(announcements.length, 2);
      window.callMethod<JSAny?>(
        'removeEventListener'.toJS,
        'cip6963:announceProvider'.toJS,
        listener,
      );
    },
  );
}
