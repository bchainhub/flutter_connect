import 'dart:async';
import 'package:app_links/app_links.dart';
import 'wallet.dart';

/// Create early after WidgetsFlutterBinding.ensureInitialized().
/// Host applications own navigation and display errors through [onError].
class ConnectLinks {
  /// Client that receives raw links for validation and user approval.
  final ConnectClient client;

  /// Receives link delivery or request validation errors for safe UI handling.
  final void Function(Object error) onError;
  final AppLinks _links;
  StreamSubscription<String>? _subscription;
  final Set<String> _delivered = {};

  /// Creates a lifecycle bridge; inject AppLinks when testing OS delivery.
  ConnectLinks({required this.client, required this.onError, AppLinks? links})
    : _links = links ?? AppLinks();
  Future<void> _handle(String uri) async {
    if (!_delivered.add(uri)) return;
    try {
      await client.handleUri(uri);
    } catch (e) {
      onError(e);
    }
  }

  /// Subscribes to warm links and handles the initial cold-start link once.
  Future<void> start() async {
    if (_subscription != null) return;
    // String APIs preserve raw syntax; Uri.toString could normalize hostile input.
    _subscription = _links.stringLinkStream.listen(
      (s) => unawaited(_handle(s)),
      onError: onError,
    );
    final initial = await _links.getInitialLinkString();
    if (initial != null) await _handle(initial);
  }

  /// Stops OS link delivery without disposing the underlying Connect client.
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
