import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'providers.dart';
import 'wallet_provider.dart';
import 'wallet_discovery.dart';

@JS('window')
external JSObject get _window;
@JS('Event')
extension type _Event._(JSObject _) implements JSObject {
  external _Event(String type);
}

@JS('BigInt')
external JSBigInt _jsBigInt(JSString value);
@JS('String')
external JSString _jsString(JSAny? value);
JSAny? _js(Object? value) {
  if (value is BigInt) return _jsBigInt(value.toString().toJS);
  if (value is Map) {
    final object = JSObject();
    for (final entry in value.entries) {
      object.setProperty(entry.key.toString().toJS, _js(entry.value));
    }
    return object;
  }
  if (value is Iterable && value is! Uint8List) {
    return value.map(_js).toList().toJS;
  }
  return value.jsify();
}

Future<JSAny?> _call(
  JSObject object,
  String method,
  List<Object?> arguments,
) async {
  try {
    final fn = object.getProperty<JSFunction>(method.toJS);
    final result = fn.callMethod<JSAny?>(
      'apply'.toJS,
      object,
      arguments.map(_js).toList().toJS,
    );
    if (result != null && result.isA<JSPromise>()) {
      return await (result as JSPromise<JSAny?>).toDart;
    }
    return result;
  } catch (error) {
    Object? code;
    try {
      code = (error as JSObject).getProperty<JSAny?>('code'.toJS)?.dartify();
    } catch (_) {
      /* Dart-side failure. */
    }
    if (code == 4001) {
      throw UserRejectedRequestError(
        'Wallet request rejected.',
        cause: error,
        providerCode: code,
      );
    }
    if (code == 4200 || code == -32601) {
      throw UnsupportedMethodError(
        'Wallet method unavailable.',
        cause: error,
        providerCode: code,
      );
    }
    if (code == 4100) {
      throw WalletNotConnectedError(
        'Wallet authorization required.',
        cause: error,
        providerCode: code,
      );
    }
    if (code == -32602) {
      throw InvalidTransactionError(
        'Invalid wallet request parameters.',
        cause: error,
        providerCode: code,
      );
    }
    if (code == 4901) {
      throw NetworkMismatchError(
        'Wallet is not connected to this network.',
        cause: error,
        providerCode: code,
      );
    }
    if (code == 4900) {
      throw ProviderDisconnectedError(
        'Wallet provider disconnected.',
        cause: error,
        providerCode: code,
      );
    }
    throw WalletProviderException(
      'Wallet request failed.',
      cause: error,
      providerCode: code,
    );
  }
}

bool _has(JSObject object, String method) {
  final value = object.getProperty<JSAny?>(method.toJS);
  return value != null && value.isA<JSFunction>();
}

NativeWalletApi _native(JSObject object) {
  final events = StreamController<ProviderEvent>.broadcast(sync: true);
  final cleanup = <void Function()>[];
  final methods = <String, NativeWalletMethod>{};
  const names = [
    'requestAccounts',
    'pushTx',
    'connect',
    'disconnect',
    'getAccounts',
    'getPublicKey',
    'getChainId',
    'getNetwork',
    'switchNetwork',
    'getBalance',
    'getBalances',
    'getUtxos',
    'signMessage',
    'signTypedData',
    'signTransaction',
    'signAllTransactions',
    'signAndSendTransaction',
    'sendTransaction',
    'signPsbt',
    'signPsbts',
    'sendRawTransaction',
    'account',
    'network',
    'signAndSubmitTransaction',
    'signIn',
    'signOut',
    'enable',
    'isEnabled',
    'getUsedAddresses',
    'getUnusedAddresses',
    'getChangeAddress',
    'getRewardAddresses',
    'getNetworkId',
    'signTx',
    'signData',
    'submitTx',
    'getBlockNumber',
    'getBlock',
    'getTransaction',
    'getTransactionReceipt',
    'getTransactionStatus',
    'getGasPrice',
    'estimateGas',
    'estimateFee',
    'getTokenBalance',
    'getTokenBalances',
    'getAssets',
    'getNFTs',
    'getNonce',
    'verifyMessage',
    'signData',
    'transfer',
    'transferToken',
    'transferNFT',
    'prepareTransaction',
    'simulateTransaction',
    'estimateTransactionFee',
    'waitForTransaction',
    'callContract',
    'readContract',
    'writeContract',
    'sendContractTransaction',
    'deployContract',
    'estimateContractGas',
    'encodeContractCall',
    'decodeContractResult',
    'getContractEvents',
    'getTokenMetadata',
    'getTokenAllowance',
    'approveToken',
    'watchAsset',
    'addToken',
    'getPrimaryAddress',
    'getPublicSpendKey',
    'getNetworkType',
    'relayTx',
    'getNetworkId',
    'getCollateral',
    'getExtensions',
    'call',
    'getLogs',
    'broadcastTransaction',
    'getTransactionCount',
    'getCode',
    'getStorage',
    'getEnergyPrice',
    'estimateEnergy',
    'getChain',
    'switchChain',
    'sendBitcoin',
    'sendLitecoin',
    'changeNetwork',
  ];
  for (final name in names) {
    if (!_has(object, name)) continue;
    methods[name] = (arguments) async {
      final result = await _call(object, name, arguments);
      if (name == 'enable' && result != null) {
        return _native(result as JSObject);
      }
      if (['signTransaction', 'signAllTransactions'].contains(name)) {
        return result;
      }
      return _input(result);
    };
  }
  if (_has(object, 'onStatusChange')) {
    final listener = ((JSAny? wallet) {
      final value = _input(wallet);
      events.add(
        ProviderEvent(
          value is Map && value['account'] != null ? 'connect' : 'disconnect',
          [value],
        ),
      );
    }).toJS;
    final unsubscribe = object.callMethod<JSAny?>(
      'onStatusChange'.toJS,
      listener,
    );
    if (unsubscribe != null && unsubscribe.isA<JSFunction>()) {
      cleanup.add(() => (unsubscribe as JSFunction).callAsFunction(null));
    }
  }
  if (_has(object, 'on') && _has(object, 'removeListener')) {
    for (final name in [
      'accountsChanged',
      'chainChanged',
      'networkChanged',
      'connect',
      'disconnect',
      'providerChanged',
      'transactionStatusChanged',
    ]) {
      final listener = ((JSAny? value) {
        events.add(ProviderEvent(name, [value?.dartify()]));
      }).toJS;
      try {
        object.callMethod<JSAny?>('on'.toJS, name.toJS, listener);
      } catch (_) {
        continue;
      }
      cleanup.add(
        () => object.callMethod<JSAny?>(
          'removeListener'.toJS,
          name.toJS,
          listener,
        ),
      );
    }
  }
  return NativeWalletApi(
    methods: methods,
    property: (name) {
      final value = object.getProperty<JSAny?>(name.toJS);
      if (name == 'publicKey' &&
          value != null &&
          value.isA<JSObject>() &&
          _has(value as JSObject, 'toBase58')) {
        return value.callMethod<JSString>('toBase58'.toJS).toDart;
      }
      return value?.dartify();
    },
    request: _has(object, 'request')
        ? (method, params) async => (await _call(object, 'request', [
            {'method': method, 'params': ?params},
          ]))?.dartify()
        : null,
    events: events.stream,
    asynchronousConnection: _has(object, 'onStatusChange'),
    onDispose: () {
      for (final dispose in cleanup) {
        try {
          dispose();
        } catch (_) {
          /* Isolate native cleanup. */
        }
      }
      events.close();
    },
  );
}

WalletDiscovery discoverWalletProviders({
  Iterable<WalletAdapter> adapters = const [],
  NativeWalletConfiguration Function(Blockchain, String)? configure,
  bool install = false,
}) {
  final api = UniversalWalletProvider(adapters);
  final seen = <Blockchain, List<JSObject>>{};
  final cleanup = <void Function()>[];
  var disposed = false;
  void register(
    Blockchain blockchain,
    String id,
    JSObject object, [
    ProviderInfo? info,
  ]) {
    final known = seen.putIfAbsent(blockchain, () => []);
    if (known.any((p) => p == object)) return;
    final native = _native(object);
    if (native.methods.isEmpty && native.request == null) {
      native.onDispose?.call();
      return;
    }
    final config =
        configure?.call(blockchain, id) ?? const NativeWalletConfiguration();
    final adapter = NativeWalletAdapter(
      id: id,
      blockchain: blockchain,
      nativeProvider: native,
      info: info,
      rpcMethods: config.rpcMethods,
      networks: config.networks,
      handlers: config.handlers,
      validateTransaction: config.validateTransaction,
    );
    if (adapter.getCapabilities().methods.every(
          (m) => m == WalletMethod.disconnect,
        ) &&
        adapter.getCapabilities().nativeMethods.isEmpty &&
        native.request == null) {
      adapter.dispose();
      return;
    }
    api.registerProvider(adapter);
    known.add(object);
  }

  for (final entry in {
    Blockchain.ethereum: 'eip6963',
    Blockchain.core: 'cip6963',
  }.entries) {
    final listener = ((JSObject event) {
      try {
        final detail = event.getProperty<JSObject>('detail'.toJS);
        final raw = Map<String, Object?>.from(
          detail.getProperty<JSAny>('info'.toJS).dartify() as Map,
        );
        final info = ProviderInfo(
          uuid: raw['uuid'] as String,
          name: raw['name'] as String,
          rdns: raw['rdns'] as String,
          icon: raw['icon'] as String,
          iconUrl: raw['iconUrl'] as String?,
          extra: raw,
        );
        if (entry.key == Blockchain.ethereum &&
            !info.icon.startsWith('data:image/')) {
          return;
        }
        register(
          entry.key,
          info.uuid,
          detail.getProperty<JSObject>('provider'.toJS),
          info,
        );
      } catch (_) {
        /* Untrusted announcement. */
      }
    }).toJS;
    _window.callMethod<JSAny?>(
      'addEventListener'.toJS,
      '${entry.value}:announceProvider'.toJS,
      listener,
    );
    cleanup.add(
      () => _window.callMethod<JSAny?>(
        'removeEventListener'.toJS,
        '${entry.value}:announceProvider'.toJS,
        listener,
      ),
    );
  }
  void refresh() {
    if (disposed) throw ProviderNotFoundError('Discovery has been disposed.');
    for (final prefix in ['eip6963', 'cip6963']) {
      _window.callMethod<JSAny?>(
        'dispatchEvent'.toJS,
        _Event('$prefix:requestProvider'),
      );
    }
    for (final blockchain in Blockchain.values) {
      try {
        final value = _window.getProperty<JSAny?>(blockchain.name.toJS);
        if (value == null || !value.isA<JSObject>()) continue;
        final provider = value as JSObject;
        if (blockchain == Blockchain.cardano) {
          if (_has(provider, 'enable')) {
            register(blockchain, 'cardano:legacy', provider);
          }
          final keys = _keys(provider);
          for (final key in keys) {
            final wallet = provider.getProperty<JSAny?>(key.toJS);
            if (wallet != null &&
                wallet.isA<JSObject>() &&
                _has(wallet as JSObject, 'enable')) {
              register(blockchain, 'cardano:$key', wallet);
            }
          }
        } else {
          final installed = provider.getProperty<JSAny?>('providers'.toJS);
          if (installed != null && installed.isA<JSArray>()) {
            final list = (installed as JSArray<JSAny?>).toDart;
            for (var i = 0; i < list.length; i++) {
              final item = list[i];
              if (item != null && item.isA<JSObject>()) {
                register(
                  blockchain,
                  '${blockchain.name}:legacy:$i',
                  item as JSObject,
                );
              }
            }
          } else {
            register(blockchain, '${blockchain.name}:legacy', provider);
          }
        }
      } catch (_) {
        /* Incompatible namespace. */
      }
    }
  }

  refresh();
  final exposed = _expose(api);
  final installed =
      install && _window.getProperty<JSAny?>('connect'.toJS) == null;
  if (installed) _window.setProperty('connect'.toJS, exposed);
  return WalletDiscovery(
    api: api,
    refresh: refresh,
    installed: installed,
    dispose: () {
      if (disposed) return;
      disposed = true;
      if (installed && _window.getProperty<JSAny?>('connect'.toJS) == exposed) {
        _window.delete('connect'.toJS);
      }
      for (final dispose in cleanup) {
        dispose();
      }
      api.dispose();
    },
  );
}

@JS('Object.keys')
external JSArray<JSString> _objectKeys(JSObject object);
List<String> _keys(JSObject object) =>
    _objectKeys(object).toDart.map((s) => s.toDart).toList();
WalletCallOptions _options(Object? value) {
  final input = value is Map ? value : const {};
  return WalletCallOptions(
    blockchain: input['blockchain'] == null
        ? null
        : _blockchain(input['blockchain'] as String),
    providerId: input['providerId'] as String?,
    account: input['account'] as String?,
    requestId: input['requestId'] as String?,
    network: input['network'],
    address: input['address'] as String?,
    blockTag: input['blockTag'] as String?,
    addresses: (input['addresses'] as List?)?.cast<String>(),
    tokens: (input['tokens'] as List?)?.cast<String>(),
    nativeOptions: input['nativeOptions'],
  );
}

JSObject _expose(UniversalWalletProvider api) {
  final object = JSObject();
  const noInput = {
    'getAccounts',
    'getAccount',
    'getPublicKey',
    'getChainId',
    'getNetwork',
    'getBlockNumber',
    'getGasPrice',
    'getBalance',
    'getBalances',
    'getTokenBalances',
    'getAssets',
    'getNFTs',
    'getNonce',
    'getUTXOs',
    'getAddress',
    'getAddresses',
  };
  for (final method in WalletMethod.values) {
    object.setProperty(
      method.name.toJS,
      (([JSAny? first, JSAny? second]) {
        return _promise(
          Future<Object?>.sync(() {
            if (method == WalletMethod.connect) {
              final opts = first?.dartify();
              return api.connect(
                options: _options(opts),
                activate: opts is Map && opts['activate'] == true,
                input: opts is Map ? opts['input'] : null,
              );
            }
            if (method == WalletMethod.disconnect) {
              return api.disconnect(_options(first?.dartify()));
            }
            final input = noInput.contains(method.name) ? null : _input(first);
            return api.execute(
              method,
              input,
              noInput.contains(method.name)
                  ? _options(first?.dartify())
                  : _options(second?.dartify()),
            );
          }),
        );
      }).toJS,
    );
  }
  object.setProperty(
    'request'.toJS,
    ((JSObject input) {
      return _promise(
        Future<Object?>.sync(() {
          final args = _input(input) as Map;
          return api.request(
            method: args['method'] as String,
            params: args['params'],
            options: _options(args),
          );
        }),
      );
    }).toJS,
  );
  object.setProperty(
    'getProviders'.toJS,
    (([JSString? blockchain]) => api
            .getProviders(
              blockchain == null ? null : _blockchain(blockchain.toDart),
            )
            .map(_descriptor)
            .toList()
            .jsify())
        .toJS,
  );
  object.setProperty(
    'getProvider'.toJS,
    (([JSString? blockchain, JSString? id]) => _descriptor(
      WalletProviderDescriptor(
        api.getProvider(
          blockchain == null ? null : _blockchain(blockchain.toDart),
          id?.toDart,
        ),
      ),
    ).jsify()).toJS,
  );
  object.setProperty(
    'getConnectedProvider'.toJS,
    (() {
      final provider = api.getConnectedProvider();
      return provider == null
          ? null
          : _descriptor(WalletProviderDescriptor(provider)).jsify();
    }).toJS,
  );
  object.setProperty(
    'getConnectedBlockchain'.toJS,
    (() => api.getConnectedBlockchain()?.name.toJS).toJS,
  );
  object.setProperty(
    'getAvailableBlockchains'.toJS,
    (() => api.getAvailableBlockchains().map((b) => b.name).toList().jsify())
        .toJS,
  );
  object.setProperty(
    'getCapabilities'.toJS,
    (([JSAny? options]) => _capabilities(
      api.getCapabilities(_options(options?.dartify())),
    ).jsify()).toJS,
  );
  object.setProperty(
    'isConnected'.toJS,
    (([JSAny? options]) => api.isConnected(_options(options?.dartify()))).toJS,
  );
  object.setProperty(
    'selectProvider'.toJS,
    ((JSString blockchain, JSString id) {
      api.selectProvider(_blockchain(blockchain.toDart), id.toDart);
    }).toJS,
  );
  object.setProperty(
    'switchBlockchain'.toJS,
    ((JSString blockchain) => api
            .switchBlockchain(_blockchain(blockchain.toDart))
            .then<JSAny?>((_) => null)
            .toJS)
        .toJS,
  );
  final listeners = <String, List<JSFunction>>{};
  api.events.listen((event) {
    final payload = {
      'blockchain': event.arguments.isNotEmpty ? event.arguments[0] : null,
      'providerId': event.arguments.length > 1 ? event.arguments[1] : null,
      'value': event.arguments.length > 2 ? event.arguments[2] : null,
    };
    for (final listener in List<JSFunction>.of(listeners[event.name] ?? [])) {
      try {
        listener.callMethod<JSAny?>('call'.toJS, object, payload.jsify());
      } catch (_) {
        /* Isolate page listeners. */
      }
    }
  }, onDone: listeners.clear);
  object.setProperty(
    'on'.toJS,
    ((JSString event, JSFunction listener) {
      (listeners[event.toDart] ??= []).add(listener);
      return object;
    }).toJS,
  );
  object.setProperty(
    'removeListener'.toJS,
    ((JSString event, JSFunction listener) {
      listeners[event.toDart]?.remove(listener);
      return object;
    }).toJS,
  );
  return object;
}

Map<String, Object?> _capabilities(WalletCapabilities c) => {
  'methods': c.methods.map((m) => m.name).toList(),
  'nativeMethods': c.nativeMethods.toList(),
  'networks': c.networks.toList(),
};
Map<String, Object?> _descriptor(WalletProviderDescriptor p) => {
  'id': p.id,
  'blockchain': p.blockchain.name,
  'connected': p.connected,
  'info': p.info?.toJson(),
  'capabilities': _capabilities(p.capabilities),
};

@JS('Object.getPrototypeOf')
external JSObject? _prototype(JSObject object);
@JS('Object.prototype')
external JSObject get _plainPrototype;
Object? _input(JSAny? value) {
  if (value == null) return null;
  if (value.isA<JSBigInt>()) return BigInt.parse(_jsString(value).toDart);
  if (value.isA<JSArray>()) {
    return (value as JSArray<JSAny?>).toDart.map(_input).toList();
  }
  if (!value.typeofEquals('object') || value.isA<JSUint8Array>()) {
    return value.dartify();
  }
  final prototype = _prototype(value as JSObject);
  if (prototype == null || prototype == _plainPrototype) {
    return {
      for (final key in _keys(value))
        key: _input(value.getProperty<JSAny?>(key.toJS)),
    };
  }
  return value;
}

@JS('Error')
extension type _JsError._(JSObject _) implements JSObject {
  external _JsError(String message);
}
JSPromise<JSAny?> _promise(Future<Object?> future) => JSPromise<JSAny?>(
  ((JSFunction resolve, JSFunction reject) {
    future.then<void>(
      (value) {
        resolve.callAsFunction(null, _js(value));
      },
      onError: (Object error, StackTrace stack) {
        final normalized = normalizeWalletError(error);
        final exposed = _JsError(normalized.message);
        exposed.setProperty('name'.toJS, normalized.name.toJS);
        if (normalized.providerCode != null) {
          exposed.setProperty('code'.toJS, normalized.providerCode.jsify());
        }
        reject.callAsFunction(null, exposed);
      },
    );
  }).toJS,
);

Blockchain _blockchain(String name) {
  for (final blockchain in Blockchain.values) {
    if (blockchain.name == name) return blockchain;
  }
  throw UnsupportedBlockchainError('Unsupported blockchain: $name');
}
