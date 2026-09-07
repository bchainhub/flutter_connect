import 'dart:async';
import 'package:app_links/app_links.dart';
import 'wallet.dart';

/// Create early after WidgetsFlutterBinding.ensureInitialized().
/// Host applications own navigation and display errors through [onError].
class ConnectLinks {
  final ConnectClient client;
  final void Function(Object error) onError;
  final AppLinks _links;
  StreamSubscription<String>? _subscription;
  final Set<String> _delivered = {};
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

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
