import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'protocol.dart';
import 'handoff.dart';

/// Signature data returned by a host wallet; never contains private keys.
class WalletSignature {
  /// Signature encoded as required by the selected signing profile.
  final String signature;

  /// Optional encoded public key required by profiles that cannot recover it.
  final String? publicKey;

  /// Creates signature data using the selected profile's wire encodings.
  const WalletSignature(this.signature, {this.publicKey});
}

/// A wallet account capable of signing canonical Connect messages.
abstract interface class WalletAccount {
  /// The account identity, proof profile and algorithm offered by this signer.
  SigningSelection get selection;

  /// Signs the exact canonical bytes after explicit user approval.
  Future<WalletSignature> sign(Uint8List canonicalPayload);
}

/// Supplies accounts available to the host wallet without signing automatically.
abstract interface class WalletAccountProvider {
  /// Returns available signers; the client filters them against request requirements.
  Future<List<WalletAccount>> getAccounts();
}

/// Optional challenge lookup and proof submission for short request URIs.
/// Full offline handoffs do not require a network adapter.
abstract interface class ConnectNetwork {
  /// Retrieves a challenge matching the target origin and request identifier.
  Future<Object?> challenge(ConnectTarget target);

  /// Submits a signed proof and returns the transport's approval result.
  Future<Object?> approve(ConnectTarget target, Map<String, dynamic> proof);
}

/// Optional Better Auth HTTP transport with bounded responses and no redirects.
class HttpsNetwork implements ConnectNetwork {
  final http.Client _client;

  /// Creates a transport, optionally using a caller-provided HTTP client.
  HttpsNetwork({http.Client? client}) : _client = client ?? http.Client();

  /// Closes the HTTP client; call when this transport is no longer needed.
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
  /// Retrieves a challenge matching the target origin and request identifier.
  Future<Object?> challenge(ConnectTarget target) =>
      _request(target, 'challenge');
  @override
  /// Submits a signed proof and returns the transport's approval result.
  Future<Object?> approve(ConnectTarget target, Map<String, dynamic> proof) =>
      _request(target, 'approve', proof);
}

/// Wallet-side request progress; portal authentication is a separate operation.
enum ConnectState {
  /// Waiting for the user to select an account and approve signing.
  awaitingUserApproval,

  /// The host wallet is signing the canonical message.
  signing,

  /// The proof is being encrypted for return or submitted through the transport.
  submitting,

  /// The configured remote transport acknowledged approval.
  approved,

  /// An encrypted offline response is ready; the portal has not yet verified it.
  responseReady,

  /// The user rejected the request locally without signing.
  rejected,

  /// The request was cancelled before proof submission.
  cancelled,

  /// The request expired before signing or submission completed.
  expired,

  /// Signing, validation or transport failed.
  failed,
}

/// An account offered by the wallet that satisfies this request's policy.
class CompatibleAccount {
  /// The identity and signing profile displayed for user selection.
  final SigningSelection selection;
  final WalletAccount _signer;
  CompatibleAccount._(this.selection, this._signer);
}

/// A single request with explicit approval and immutable compatible accounts.
class ConnectRequest {
  /// Validated challenge whose canonical fields must be shown before signing.
  final ConnectChallenge challenge;

  /// Immutable accounts accepted by the challenge's signing requirements.
  final List<CompatibleAccount> compatibleAccounts;
  final ConnectNetwork _network;
  String? _response;

  /// Encrypted response to return by BLE, response QR, or another host channel.
  String? get response => _response;

  /// Pairing ticket for an offline request, or null for a network lookup.
  ConnectHandoff? get handoff =>
      _network is _HandoffNetwork ? _network.ticket : null;
  final DateTime Function() _now;
  final void Function(ConnectRequest) _changed;
  ConnectState _state = ConnectState.awaitingUserApproval;

  /// Current wallet-side lifecycle state.
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

  /// Cancels a pending request or discards a signature still being produced.
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

  /// Signs once using an offered account after explicit user confirmation.
  /// Offline success exposes [response]; the portal must still verify the proof.
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

/// Resolves Connect links, filters accounts and emits requests for trusted UI.
class ConnectClient {
  /// Host account source; signing remains inside its wallet implementations.
  final WalletAccountProvider accountProvider;

  /// Optional network adapter for short links without an embedded challenge.
  final ConnectNetwork? network;

  /// Parser for short request links; full handoffs use their strict parser.
  final ConnectTransport transport;

  /// Clock used for challenge validation; injectable for deterministic tests.
  final DateTime Function() now;
  final Set<String> _handled = {};
  final _requests = StreamController<ConnectRequest>.broadcast();

  /// Broadcasts resolved requests and subsequent lifecycle transitions.
  Stream<ConnectRequest> get requests => _requests.stream;

  /// Creates a client; no network is required for full offline handoffs.
  ConnectClient({
    required this.accountProvider,
    this.network,
    ConnectTransport? transport,
    DateTime Function()? now,
  }) : transport = transport ?? UriTransport(),
       now = now ?? DateTime.now;

  /// Handles a raw OS link or scanned QR string through [resolve].
  Future<ConnectRequest> handleUri(String input) => resolve(input);

  /// Validates a full handoff or looks up a short URI using [network].
  /// Never signs automatically; duplicate resolved requests are rejected.
  Future<ConnectRequest> resolve(String input) {
    if (input.contains('#')) {
      final handoff = ConnectHandoff.parse(input, now: now);
      return _resolve(handoff.challenge, _HandoffNetwork(handoff));
    }
    return resolveTarget(transport.parse(input));
  }

  /// Looks up an already parsed target using the configured network adapter.
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

  /// Closes the request event stream and prevents further resolution.
  Future<void> dispose() => _requests.close();
}

class _HandoffNetwork implements ConnectNetwork {
  final ConnectHandoff ticket;
  _HandoffNetwork(this.ticket);
  @override
  /// Retrieves a challenge matching the target origin and request identifier.
  Future<Object?> challenge(ConnectTarget target) async =>
      ticket.challenge.toJson();
  @override
  /// Submits a signed proof and returns the transport's approval result.
  Future<Object?> approve(
    ConnectTarget target,
    Map<String, dynamic> proof,
  ) async => {
    'requestId': target.requestId,
    'status': 'RESPONSE_READY',
    'response': await ticket.sealProof(proof),
  };
}
