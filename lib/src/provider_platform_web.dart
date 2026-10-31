import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'providers.dart';
import 'protocol.dart';

@JS('window')
external JSObject get _window;
@JS('Object.freeze')
external JSObject _freeze(JSObject object);
@JS('CustomEvent')
extension type _CustomEvent._(JSObject _) implements JSObject {
  external _CustomEvent(String type, JSObject options);
}

void Function() injectProviders(
  Map<Blockchain, InjectedProvider> providers,
  UniversalProvider connect,
) {
  final cleanup = <void Function()>[];
  void install(String key, JSObject provider) {
    if (_window.getProperty<JSAny?>(key.toJS) == null) {
      _window.setProperty(key.toJS, provider);
      cleanup.add(() {
        if (_window.getProperty<JSAny?>(key.toJS) == provider) {
          _window.delete(key.toJS);
        }
      });
    }
  }

  JSObject wrap(ProviderRequest request) {
    final object = JSObject();
    object.setProperty(
      'request'.toJS,
      ((JSObject args) {
        return Future<Object?>.sync(
          () => request(
            (args.getProperty<JSString>('method'.toJS)).toDart,
            args.getProperty<JSAny?>('params'.toJS)?.dartify(),
          ),
        ).then((value) => value.jsify()).toJS;
      }).toJS,
    );
    return object;
  }

  final universal = JSObject();
  universal.setProperty(
    'request'.toJS,
    ((JSObject args) {
      return Future<Object?>.sync(() {
        final input = Map<String, Object?>.from(args.dartify() as Map);
        return connect.request(
          method: input['method'] as String,
          params: input['params'] == null
              ? const {}
              : Map<String, Object?>.from(input['params'] as Map),
          blockchain: input['blockchain'] == null
              ? null
              : Blockchain.values.byName(input['blockchain'] as String),
          account: input['account'] == null
              ? null
              : WalletIdentity.fromJson(
                  Map<String, Object?>.from(input['account'] as Map),
                ),
        );
      }).then((value) => value.jsify()).toJS;
    }).toJS,
  );
  install('connect', universal);
  for (final entry in providers.entries) {
    final provider = wrap(entry.value.request);
    final listeners = <String, List<JSFunction>>{};
    provider.setProperty(
      'on'.toJS,
      ((JSString event, JSFunction listener) {
        (listeners[event.toDart] ??= []).add(listener);
        return provider;
      }).toJS,
    );
    provider.setProperty(
      'removeListener'.toJS,
      ((JSString event, JSFunction listener) {
        listeners[event.toDart]?.remove(listener);
        return provider;
      }).toJS,
    );
    final subscription = entry.value.events?.listen((event) {
      for (final listener in List<JSFunction>.of(listeners[event.name] ?? [])) {
        try {
          listener.callMethod<JSAny?>(
            'apply'.toJS,
            provider,
            event.arguments.jsify(),
          );
        } catch (_) {
          /* Isolate page listeners. */
        }
      }
    });
    cleanup.add(() {
      subscription?.cancel();
      listeners.clear();
    });
    install(entry.key.name, provider);
    final prefix =
        entry.value.discoveryPrefix ??
        switch (entry.key) {
          Blockchain.core => 'cip6963',
          Blockchain.ethereum => 'eip6963',
          _ => null,
        };
    if (prefix == null) continue;
    final detail = JSObject();
    detail.setProperty(
      'info'.toJS,
      _freeze(entry.value.info.toJson().jsify() as JSObject),
    );
    detail.setProperty('provider'.toJS, provider);
    _freeze(detail);
    void announce() {
      final options = JSObject()..setProperty('detail'.toJS, detail);
      _window.callMethod<JSAny?>(
        'dispatchEvent'.toJS,
        _CustomEvent('$prefix:announceProvider', options),
      );
    }

    final listener = ((JSAny? event) => announce()).toJS;
    _window.callMethod<JSAny?>(
      'addEventListener'.toJS,
      '$prefix:requestProvider'.toJS,
      listener,
    );
    cleanup.add(
      () => _window.callMethod<JSAny?>(
        'removeEventListener'.toJS,
        '$prefix:requestProvider'.toJS,
        listener,
      ),
    );
    announce();
  }
  return () {
    for (final dispose in cleanup.reversed) {
      dispose();
    }
    cleanup.clear();
  };
}
