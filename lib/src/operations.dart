import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'protocol.dart';
import 'wallet.dart';
import 'chains.dart';

const maxOperationBytes = 16384;

abstract final class OperationMethods {
  static const getAccounts = 'wallet.getAccounts';
  static const signMessage = 'wallet.signMessage';
  static const signTransaction = 'wallet.signTransaction';
  static const sendTransaction = 'wallet.sendTransaction';
  static const switchChain = 'wallet.switchChain';
  static const addChain = 'wallet.addChain';
  static const signTypedData = 'wallet.signTypedData';
  static const signPsbt = 'wallet.signPsbt';
  static const signAllTransactions = 'wallet.signAllTransactions';
  static const getBalance = 'chain.getBalance';
  static const getTransaction = 'chain.getTransaction';
  static const getBlock = 'chain.getBlock';
  static const estimateFee = 'chain.estimateFee';
  static const call = 'chain.call';
  static const all = {
    getAccounts,
    signMessage,
    signTransaction,
    sendTransaction,
    switchChain,
    addChain,
    signTypedData,
    signPsbt,
    signAllTransactions,
    getBalance,
    getTransaction,
    getBlock,
    estimateFee,
    call,
  };
}

const operationErrorMessages = <String, String>{
  'UNSUPPORTED_OPERATION': 'Operation is not supported.',
  'UNSUPPORTED_CHAIN': 'Chain is not supported.',
  'UNSUPPORTED_ACCOUNT': 'Account is not available.',
  'INVALID_PARAMS': 'Invalid operation parameters.',
  'INVALID_TRANSACTION': 'Invalid transaction.',
  'USER_REJECTED': 'User rejected the operation.',
  'UNAUTHORIZED': 'Operation is not authorized.',
  'SIGNING_FAILED': 'Wallet signing failed.',
  'BROADCAST_FAILED': 'Transaction broadcast failed.',
  'CHAIN_UNAVAILABLE': 'Chain is unavailable.',
  'TIMEOUT': 'Operation timed out.',
  'INTERNAL_ERROR': 'Operation failed.',
};

class OperationException implements Exception {
  final String code;
  OperationException(String code)
    : code = operationErrorMessages.containsKey(code) ? code : 'INTERNAL_ERROR';
  String get message => operationErrorMessages[code]!;
  @override
  String toString() => 'OperationException($code)';
}

Never _fail([String code = 'INVALID_PARAMS']) => throw OperationException(code);
Object? _snapshot(Object? value, [int depth = 0]) {
  if (depth > 32) _fail();
  if (value == null || value is String || value is bool) return value;
  if (value is num &&
      value.isFinite &&
      (value % 1 != 0 || value.abs() <= 9007199254740991)) {
    return value;
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map((v) => _snapshot(v, depth + 1)),
    );
  }
  if (value is! Map) _fail();
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) _fail();
    final key = entry.key as String;
    if (RegExp(
      r'^(?:proto|prototype|constructor|privatekey|secretkey|mnemonic|seedphrase)$',
      caseSensitive: false,
    ).hasMatch(key.replaceAll(RegExp('[_-]'), ''))) {
      _fail();
    }
    result[key] = _snapshot(entry.value, depth + 1);
  }
  return Map<String, Object?>.unmodifiable(result);
}

Object? _input(Object? input) {
  try {
    if (input is String) {
      if (utf8.encode(input).length > maxOperationBytes) _fail();
      input = jsonDecode(input);
    }
    final result = _snapshot(input);
    if (utf8.encode(jsonEncode(result)).length > maxOperationBytes) _fail();
    return result;
  } catch (_) {
    _fail();
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) _fail();
  return value;
}

void _keys(
  Map<String, Object?> j,
  List<String> required, [
  List<String> optional = const [],
]) {
  if (!required.every(j.containsKey) ||
      j.keys.any((k) => !required.contains(k) && !optional.contains(k))) {
    _fail();
  }
}

String _atom(Object? value) {
  try {
    return atom(value);
  } catch (_) {
    _fail();
  }
}

String _id(Object? value) {
  try {
    return identifier(value);
  } catch (_) {
    _fail();
  }
}

String _method(Object? value, {bool registration = false}) {
  if (value is! String ||
      value.length > 128 ||
      !matches(r'[a-z][a-z0-9]*\.[a-zA-Z][a-zA-Z0-9]*', value)) {
    _fail();
  }
  if (registration &&
      (value.startsWith('wallet.') || value.startsWith('chain.')) &&
      !OperationMethods.all.contains(value)) {
    _fail('UNSUPPORTED_OPERATION');
  }
  return value;
}

class OperationChain {
  final String namespace, reference;
  OperationChain(String namespace, String reference)
    : namespace = _atom(namespace),
      reference = _atom(reference);
  factory OperationChain.fromChain(ConnectChain chain) =>
      OperationChain(chain.namespace, chain.reference);
  factory OperationChain.fromJson(Object? value) {
    final j = _map(value);
    _keys(j, ['namespace', 'reference']);
    return OperationChain(_atom(j['namespace']), _atom(j['reference']));
  }
  Map<String, Object?> toJson() => {
    'namespace': namespace,
    'reference': reference,
  };
  String get key => '$namespace:$reference';
}

class ConnectOperation {
  final String requestId, operation;
  final OperationChain chain;
  final WalletIdentity? account;
  final Map<String, Object?> params;
  final Map<String, Object?>? metadata;
  int get version => 1;
  ConnectOperation._(
    this.requestId,
    this.operation,
    this.chain,
    this.account,
    this.params,
    this.metadata,
  );
  factory ConnectOperation({
    String? requestId,
    required String operation,
    required OperationChain chain,
    WalletIdentity? account,
    required Map<String, Object?> params,
    Map<String, Object?>? metadata,
  }) {
    final random = Random.secure();
    return ConnectOperation.fromJson({
      'version': 1,
      'requestId':
          requestId ??
          List.generate(
            32,
            (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
          ).join(),
      'operation': operation,
      'chain': chain.toJson(),
      if (account != null) 'account': account.toJson(),
      'params': params,
      'metadata': ?metadata,
    });
  }
  factory ConnectOperation.fromJson(Object? input) {
    try {
      final j = _map(_input(input));
      _keys(
        j,
        ['version', 'requestId', 'operation', 'chain', 'params'],
        ['account', 'metadata'],
      );
      if (j['version'] != 1) _fail();
      final chain = OperationChain.fromJson(j['chain']);
      final account = j.containsKey('account')
          ? WalletIdentity.fromJson(j['account'])
          : null;
      if (account != null &&
          (account.namespace != chain.namespace ||
              account.reference != chain.reference)) {
        _fail('UNSUPPORTED_ACCOUNT');
      }
      return ConnectOperation._(
        _id(j['requestId']),
        _method(j['operation']),
        chain,
        account,
        _map(j['params']),
        j.containsKey('metadata') ? _map(j['metadata']) : null,
      );
    } on OperationException {
      rethrow;
    } catch (_) {
      _fail();
    }
  }
  Map<String, Object?> toJson() => {
    'version': 1,
    'requestId': requestId,
    'operation': operation,
    'chain': chain.toJson(),
    if (account != null) 'account': account!.toJson(),
    'params': params,
    if (metadata != null) 'metadata': metadata,
  };
  String serialize() => jsonEncode(toJson());
}

class OperationFailure {
  final String code, message;
  final Map<String, Object?>? details;
  OperationFailure._(this.code, this.message, this.details);
  factory OperationFailure.fromJson(Object? value) {
    final j = _map(value);
    _keys(j, ['code', 'message'], ['details']);
    if (!operationErrorMessages.containsKey(j['code']) ||
        j['message'] is! String ||
        (j['message'] as String).isEmpty ||
        (j['message'] as String).length > 256) {
      _fail();
    }
    return OperationFailure._(
      j['code'] as String,
      j['message'] as String,
      j.containsKey('details') ? _map(_snapshot(j['details'])) : null,
    );
  }
  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    if (details != null) 'details': details,
  };
}

class OperationResponse {
  final String? requestId;
  final Object? result;
  final OperationFailure? error;
  bool get isSuccess => error == null;
  OperationResponse._(this.requestId, this.result, this.error);
  factory OperationResponse.success(String requestId, Object? result) =>
      OperationResponse.fromJson({
        'version': 1,
        'requestId': requestId,
        'result': result,
      });
  factory OperationResponse.failure(String? requestId, String code) =>
      OperationResponse.fromJson({
        'version': 1,
        'requestId': requestId,
        'error': {'code': code, 'message': operationErrorMessages[code]},
      });
  factory OperationResponse.fromJson(
    Object? input, {
    String? expectedRequestId,
  }) {
    final j = _map(_input(input));
    final failure = j.containsKey('error');
    _keys(j, ['version', 'requestId', failure ? 'error' : 'result']);
    if (j['version'] != 1) _fail();
    final id = failure && j['requestId'] == null ? null : _id(j['requestId']);
    if (expectedRequestId != null && id != _id(expectedRequestId)) _fail();
    return OperationResponse._(
      id,
      failure ? null : j['result'],
      failure ? OperationFailure.fromJson(j['error']) : null,
    );
  }
  Map<String, Object?> toJson() => {
    'version': 1,
    'requestId': requestId,
    if (error != null) 'error': error!.toJson() else 'result': result,
  };
  String serialize() => jsonEncode(toJson());
}

class OperationCapability extends OperationChain {
  final List<String> methods;
  OperationCapability(
    super.namespace,
    super.reference,
    Iterable<String> methods,
  ) : methods = List.unmodifiable(
        methods.map((m) => _method(m, registration: true)),
      ) {
    if (this.methods.length > 128 ||
        this.methods.toSet().length != this.methods.length) {
      _fail();
    }
  }
  factory OperationCapability.fromJson(Object? value) {
    final j = _map(value);
    _keys(j, ['namespace', 'reference', 'methods']);
    if (j['methods'] is! List) _fail();
    return OperationCapability(
      _atom(j['namespace']),
      _atom(j['reference']),
      (j['methods'] as List).map((m) => _method(m, registration: true)),
    );
  }
  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'methods': methods};
}

List<OperationCapability> parseCapabilities(Object? input) {
  final value = _input(input);
  if (value is! List || value.length > 128) _fail();
  final result = value.map(OperationCapability.fromJson).toList();
  if (result.map((c) => c.key).toSet().length != result.length) _fail();
  return List.unmodifiable(result);
}

bool supportsOperation(
  Iterable<OperationCapability> capabilities,
  OperationChain chain,
  String method,
) => capabilities.any((c) => c.key == chain.key && c.methods.contains(method));

class OperationContext {
  /// Trusted transport origin, never request metadata.
  final String origin;
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  OperationContext._(this.origin);
}

typedef OperationHandler =
    FutureOr<Object?> Function(
      ConnectOperation request,
      OperationContext context,
    );
typedef OperationApproval =
    FutureOr<bool> Function(
      ConnectOperation request,
      OperationContext context,
      Object? preparedMessage,
    );

/// A host-owned adapter; validators must inspect the complete chain-specific payload.
class OperationChainAdapter {
  final List<OperationCapability> capabilities;
  final Map<String, OperationHandler> handlers;
  final FutureOr<bool> Function(WalletIdentity) validateAccount;
  final FutureOr<void> Function(ConnectOperation) validateOperation;
  final FutureOr<Object?> Function(ConnectOperation)? prepareMessage;
  final Object? Function(ConnectOperation, Object?)? normalizeResult;
  final String? Function(Object)? translateError;
  OperationChainAdapter({
    required Iterable<OperationCapability> capabilities,
    required Map<String, OperationHandler> handlers,
    required this.validateAccount,
    required this.validateOperation,
    this.prepareMessage,
    this.normalizeResult,
    this.translateError,
  }) : capabilities = parseCapabilities(
         capabilities.map((c) => c.toJson()).toList(),
       ),
       handlers = Map.unmodifiable(handlers);
}

class OperationDispatcher {
  final Map<String, OperationChainAdapter> _adapters = {};
  final Set<String> _handled = {};
  final OperationApproval? approve;
  final WalletAccountProvider? accounts;
  final Duration timeout;
  final int maxRequests;
  late final List<OperationCapability> capabilities;
  OperationDispatcher({
    required Iterable<OperationChainAdapter> adapters,
    this.approve,
    this.accounts,
    this.timeout = const Duration(seconds: 30),
    this.maxRequests = 4096,
  }) {
    if (timeout.inMilliseconds <= 0 || maxRequests <= 0) _fail();
    final caps = <OperationCapability>[];
    for (final adapter in adapters) {
      for (final c in adapter.capabilities) {
        if (_adapters.containsKey(c.key)) _fail();
        if (c.methods.any((m) => !adapter.handlers.containsKey(m))) {
          _fail('UNSUPPORTED_OPERATION');
        }
        _adapters[c.key] = adapter;
        caps.add(c);
      }
    }
    capabilities = parseCapabilities(caps.map((c) => c.toJson()).toList());
  }
  bool supports(OperationChain chain, String method) =>
      supportsOperation(capabilities, chain, method);
  Future<OperationResponse> dispatch(
    Object? input, {
    required String origin,
  }) async {
    ConnectOperation request;
    try {
      request = ConnectOperation.fromJson(
        input is ConnectOperation ? input.toJson() : input,
      );
    } catch (e) {
      String? id;
      try {
        id = _id(_map(_input(input))['requestId']);
      } catch (_) {
        /* Missing identifier. */
      }
      return OperationResponse.failure(
        id,
        e is OperationException ? e.code : 'INVALID_PARAMS',
      );
    }
    final context = OperationContext._(origin);
    try {
      return await _execute(request, context).timeout(
        timeout,
        onTimeout: () {
          context._cancelled = true;
          return OperationResponse.failure(request.requestId, 'TIMEOUT');
        },
      );
    } finally {
      context._cancelled = true;
    }
  }

  Future<String> dispatchJson(String input, {required String origin}) async =>
      (await dispatch(input, origin: origin)).serialize();
  Future<OperationResponse> _execute(
    ConnectOperation request,
    OperationContext context,
  ) async {
    OperationChainAdapter? adapter;
    var stage = 'INVALID_PARAMS';
    void alive() {
      if (context.isCancelled) _fail('TIMEOUT');
    }

    try {
      try {
        validateOrigin(context.origin);
      } catch (_) {
        _fail('UNAUTHORIZED');
      }
      if (_handled.contains(request.requestId) ||
          _handled.length >= maxRequests) {
        _fail('UNAUTHORIZED');
      }
      _handled.add(request.requestId);
      adapter = _adapters[request.chain.key];
      if (adapter == null) _fail('UNSUPPORTED_CHAIN');
      if (!supports(request.chain, request.operation)) {
        _fail('UNSUPPORTED_OPERATION');
      }
      final wallet = request.operation.startsWith('wallet.');
      final signing = RegExp(
        r'^wallet\.(sign|send)',
      ).hasMatch(request.operation);
      if (signing && request.account == null) _fail('UNSUPPORTED_ACCOUNT');
      Future<void> checkAccount() async {
        final account = request.account;
        if (account == null) return;
        if (!await adapter!.validateAccount(account)) {
          _fail('UNSUPPORTED_ACCOUNT');
        }
        if (wallet) {
          if (accounts == null) _fail('UNSUPPORTED_ACCOUNT');
          final available = await accounts!.getAccounts();
          if (!available.any(
            (a) =>
                a.selection.account.namespace == account.namespace &&
                a.selection.account.reference == account.reference &&
                a.selection.account.address == account.address,
          )) {
            _fail('UNSUPPORTED_ACCOUNT');
          }
        }
      }

      await checkAccount();
      alive();
      await adapter.validateOperation(request);
      alive();
      if (!request.operation.startsWith('chain.')) {
        stage = 'UNAUTHORIZED';
        if (approve == null) _fail('UNAUTHORIZED');
        final prepared =
            request.operation == OperationMethods.signMessage &&
                adapter.prepareMessage != null
            ? _snapshot(await adapter.prepareMessage!(request))
            : null;
        alive();
        if (!await approve!(request, context, prepared)) _fail('USER_REJECTED');
        alive();
        await checkAccount();
        alive();
      }
      stage = request.operation == OperationMethods.sendTransaction
          ? 'BROADCAST_FAILED'
          : signing
          ? 'SIGNING_FAILED'
          : request.operation.startsWith('chain.')
          ? 'CHAIN_UNAVAILABLE'
          : 'INTERNAL_ERROR';
      final result = await adapter.handlers[request.operation]!(
        request,
        context,
      );
      alive();
      stage = 'INTERNAL_ERROR';
      return OperationResponse.success(
        request.requestId,
        adapter.normalizeResult != null
            ? adapter.normalizeResult!(request, result)
            : result,
      );
    } catch (e) {
      var code = e is OperationException ? e.code : stage;
      if (e is! OperationException && adapter?.translateError != null) {
        try {
          final translated = adapter!.translateError!(e);
          if (operationErrorMessages.containsKey(translated)) {
            code = translated!;
          }
        } catch (_) {
          /* Safe fallback. */
        }
      }
      return OperationResponse.failure(request.requestId, code);
    }
  }
}

OperationHandler operationAccounts(
  WalletAccountProvider provider,
  OperationChain chain,
) =>
    (request, context) async => (await provider.getAccounts())
        .where(
          (a) =>
              a.selection.account.namespace == chain.namespace &&
              a.selection.account.reference == chain.reference,
        )
        .map((a) => a.selection.account.toJson())
        .toList();

abstract interface class OperationTransport {
  Future<String> exchange(String request);
}

Future<OperationResponse> requestOperation(
  OperationTransport transport,
  ConnectOperation request,
) async => OperationResponse.fromJson(
  await transport.exchange(request.serialize()),
  expectedRequestId: request.requestId,
);
