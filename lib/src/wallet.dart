import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'protocol.dart';
import 'handoff.dart';

class WalletSignature {
  final String signature;
  final String? publicKey;
  const WalletSignature(this.signature, {this.publicKey});
}

abstract interface class WalletAccount {
  SigningSelection get selection;
  Future<WalletSignature> sign(Uint8List canonicalPayload);
}

abstract interface class WalletAccountProvider {
  Future<List<WalletAccount>> getAccounts();
}

abstract interface class ConnectNetwork {
  Future<Object?> challenge(ConnectTarget target);
  Future<Object?> approve(ConnectTarget target, Map<String, dynamic> proof);
}

class HttpsNetwork implements ConnectNetwork {
  final http.Client _client;
  HttpsNetwork({http.Client? client}) : _client = client ?? http.Client();
  void close() => _client.close();
  Future<Object?> _request(
    ConnectTarget target,
    String action, [
    Map<String, dynamic>? body,
  ]) async {
    validateOrigin(target.origin);
    final url = Uri.parse(
      '${target.origin}/api/auth/wallet-connect/$action${body == null ? '?requestId=${target.requestId}' : ''}',
    );
    final abort = Completer<void>();
    final request = http.AbortableRequest(
      body == null ? 'GET' : 'POST',
      url,
      abortTrigger: abort.future,
    )..followRedirects = false;
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      return await (() async {
        final response = await _client.send(request);
        if (response.statusCode != 200) {
          await response.stream.listen((_) {}).cancel();
          fail('serverRejected');
        }
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in response.stream) {
          if (bytes.length + chunk.length > 16384) fail('malformedResponse');
          bytes.add(chunk);
        }
        return jsonDecode(utf8.decode(bytes.takeBytes()));
      })().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (!abort.isCompleted) abort.complete();
          fail('networkError');
        },
      );
    } on ConnectException {
      rethrow;
    } catch (_) {
      fail('networkError');
    } finally {
      if (!abort.isCompleted) abort.complete();
    }
  }

  @override
  Future<Object?> challenge(ConnectTarget target) =>
      _request(target, 'challenge');
  @override
  Future<Object?> approve(ConnectTarget target, Map<String, dynamic> proof) =>
      _request(target, 'approve', proof);
}

enum ConnectState {
  awaitingUserApproval,
  signing,
  submitting,
  approved,
  responseReady,
  rejected,
  cancelled,
  expired,
  failed,
}

class CompatibleAccount {
  final SigningSelection selection;
  final WalletAccount _signer;
  CompatibleAccount._(this.selection, this._signer);
}

class ConnectRequest {
  final ConnectChallenge challenge;
  final List<CompatibleAccount> compatibleAccounts;
  final ConnectNetwork _network;
  String? _response;

  /// Encrypted response to return by BLE, response QR, or another host channel.
  String? get response => _response;
  ConnectHandoff? get handoff =>
      _network is _HandoffNetwork ? _network.ticket : null;
  final DateTime Function() _now;
  final void Function(ConnectRequest) _changed;
  ConnectState _state = ConnectState.awaitingUserApproval;
  ConnectState get state => _state;
  ConnectRequest._(
    this.challenge,
    List<WalletAccount> accounts,
    this._network,
    this._now,
    this._changed,
  ) : compatibleAccounts = List.unmodifiable(
        accounts
            .map((a) => CompatibleAccount._(a.selection, a))
            .where((a) => challenge.accepts(a.selection)),
      );
  void _set(ConnectState state) {
    _state = state;
    _changed(this);
  }

  void _pending() {
    if (_state != ConnectState.awaitingUserApproval) fail('invalidState');
  }

  void cancel() {
    if (_state != ConnectState.awaitingUserApproval &&
        _state != ConnectState.signing) {
      fail('invalidState');
    }
    _set(ConnectState.cancelled);
  }

  /// Local rejection only: possession of a public QR must not allow remote denial.
  void reject() {
    _pending();
    _set(ConnectState.rejected);
  }

  Future<void> approve(CompatibleAccount account) async {
    _pending();
    if (!compatibleAccounts.contains(account)) fail('noCompatibleAccount');
    try {
      challenge.validateTime(_now());
      _set(ConnectState.signing);
      final signature = await account._signer.sign(
        canonicalBytes(challenge, account.selection),
      );
      if (_state == ConnectState.cancelled) fail('cancelled');
      challenge.validateTime(_now());
      _set(ConnectState.submitting);
      final result = await _network.approve(challenge, {
        'requestId': challenge.requestId,
        'account': account.selection.account.toJson(),
        'profile': account.selection.profile,
        'alg': account.selection.alg,
        'signature': signature.signature,
        if (signature.publicKey != null) 'publicKey': signature.publicKey,
      });
      if (result is! Map ||
          !['APPROVED', 'RESPONSE_READY'].contains(result['status']) ||
          result['requestId'] != challenge.requestId) {
        fail('serverRejected');
      }
      if (result['status'] == 'RESPONSE_READY') {
        _response = result['response'] as String;
        _set(ConnectState.responseReady);
      } else {
        _set(ConnectState.approved);
      }
    } catch (e) {
      if (_state != ConnectState.cancelled) {
        _set(
          e is ConnectException && e.code == 'expiredRequest'
              ? ConnectState.expired
              : ConnectState.failed,
        );
      }
      if (e is ConnectException) rethrow;
      fail('signingFailed');
    }
  }
}

class ConnectClient {
  final WalletAccountProvider accountProvider;
  final ConnectNetwork? network;
  final ConnectTransport transport;
  final DateTime Function() now;
  final Set<String> _handled = {};
  final _requests = StreamController<ConnectRequest>.broadcast();
  Stream<ConnectRequest> get requests => _requests.stream;
  ConnectClient({
    required this.accountProvider,
    this.network,
    ConnectTransport? transport,
    DateTime Function()? now,
  }) : transport = transport ?? UriTransport(),
       now = now ?? DateTime.now;
  Future<ConnectRequest> handleUri(String input) => resolve(input);
  Future<ConnectRequest> resolve(String input) {
    if (input.contains('#')) {
      final handoff = ConnectHandoff.parse(input, now: now);
      return _resolve(handoff.challenge, _HandoffNetwork(handoff));
    }
    return resolveTarget(transport.parse(input));
  }

  Future<ConnectRequest> resolveTarget(ConnectTarget target) {
    final adapter = network;
    if (adapter == null) fail('transportUnavailable');
    return _resolve(target, adapter);
  }

  Future<ConnectRequest> _resolve(
    ConnectTarget target,
    ConnectNetwork adapter,
  ) async {
    if (_requests.isClosed) fail('disposed');
    final key = '${target.origin}/${target.requestId}';
    if (!_handled.add(key)) fail('replayedRequest');
    try {
      final challenge = ConnectChallenge.fromJson(
        await adapter.challenge(target),
        target: target,
        now: now(),
      );
      final request = ConnectRequest._(
        challenge,
        await accountProvider.getAccounts(),
        adapter,
        now,
        (r) {
          if (!_requests.isClosed) _requests.add(r);
        },
      );
      if (request.compatibleAccounts.isEmpty) fail('noCompatibleAccount');
      if (_requests.isClosed) fail('disposed');
      _requests.add(request);
      return request;
    } catch (_) {
      _handled.remove(key);
      rethrow;
    }
  }

  Future<void> dispose() => _requests.close();
}

class _HandoffNetwork implements ConnectNetwork {
  final ConnectHandoff ticket;
  _HandoffNetwork(this.ticket);
  @override
  Future<Object?> challenge(ConnectTarget target) async =>
      ticket.challenge.toJson();
  @override
  Future<Object?> approve(
    ConnectTarget target,
    Map<String, dynamic> proof,
  ) async => {
    'requestId': target.requestId,
    'status': 'RESPONSE_READY',
    'response': await ticket.sealProof(proof),
  };
}
