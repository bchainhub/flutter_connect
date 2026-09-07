import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_connect/flutter_connect.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: ConnectDemo()));
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

class DemoAccount implements WalletAccount {
  final SimpleKeyPair _key;
  @override
  final SigningSelection selection;
  DemoAccount(this._key, String address)
    : selection = SigningSelection(
        account: WalletIdentity(
          namespace: 'raw',
          reference: 'ed25519',
          address: address,
        ),
        profile: 'raw-ed25519',
        alg: coseEd25519,
      );
  @override
  Future<WalletSignature> sign(Uint8List canonicalPayload) async {
    final signature = await Ed25519().sign(canonicalPayload, keyPair: _key);
    return WalletSignature(
      hex(signature.bytes),
      publicKey: selection.account.address,
    );
  }
}

class DemoAccounts implements WalletAccountProvider {
  Future<WalletAccount>? _account;
  Future<WalletAccount> _create() async {
    final key = await Ed25519().newKeyPair();
    return DemoAccount(key, hex((await key.extractPublicKey()).bytes));
  }

  @override
  Future<List<WalletAccount>> getAccounts() async => [
    await (_account ??= _create()),
  ];
}

class ConnectDemo extends StatefulWidget {
  const ConnectDemo({super.key});
  @override
  State<ConnectDemo> createState() => _ConnectDemoState();
}

class _ConnectDemoState extends State<ConnectDemo> {
  final input = TextEditingController();
  ConnectBluetoothPeripheral? bluetooth;
  late final ConnectClient client;
  late final ConnectLinks links;
  StreamSubscription<ConnectRequest>? subscription;
  ConnectRequest? request;
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    client = ConnectClient(accountProvider: DemoAccounts());
    subscription = client.requests.listen((r) {
      if (request?.challenge.requestId != r.challenge.requestId) {
        unawaited(bluetooth?.stop());
        bluetooth = null;
      }
      if (mounted) {
        setState(() {
          request = r;
          error = null;
        });
      }
    });
    links = ConnectLinks(client: client, onError: showError);
    unawaited(links.start().catchError(showError));
  }

  void showError(Object e) {
    if (mounted) {
      setState(
        () => error = e is ConnectException
            ? e.code
            : 'Unable to process request',
      );
    }
  }

  Future<void> open() async {
    setState(() {
      loading = true;
      request = null;
      error = null;
    });
    try {
      await bluetooth?.stop();
      bluetooth = null;
      await client.handleUri(input.text);
    } catch (e) {
      showError(e);
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  void dispose() {
    unawaited(links.dispose());
    unawaited(subscription?.cancel());
    unawaited(client.dispose());
    unawaited(bluetooth?.stop());
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = request;
    return Scaffold(
      appBar: AppBar(title: const Text('Connect wallet')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Reference wallet',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          const Text(
            'Uses an ephemeral Ed25519 test account. Use the nearby dapp example, which allows raw-ed25519. A real wallet supplies its own account and signing implementation.',
          ),
          const SizedBox(height: 24),
          TextField(
            controller: input,
            decoration: const InputDecoration(
              labelText: 'Paste a Connect URI',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: loading ? null : open,
            child: Text(loading ? 'Loading…' : 'Review request'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Request error: $error',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (r != null) ...[
            if (r.handoff != null &&
                r.state == ConnectState.awaitingUserApproval)
              OutlinedButton(
                onPressed: () async {
                  try {
                    await bluetooth?.stop();
                    final peripheral = ConnectBluetoothPeripheral(
                      handoff: r.handoff!,
                      onError: showError,
                    );
                    bluetooth = peripheral;
                    await peripheral.start();
                  } catch (e) {
                    showError(e);
                  }
                },
                child: const Text(
                  'Confirm website and enable nearby Bluetooth',
                ),
              ),
            if (r.response != null) ...[
              const Text(
                'Return this encrypted response to the portal. If Bluetooth is enabled, the portal can collect it now.',
              ),
              QrImageView(data: r.response!, size: 300),
              SelectableText(r.response!),
            ],
            const Divider(height: 40),
            const Text(
              'Sign in on another device?',
              style: TextStyle(fontSize: 22),
            ),
            const SizedBox(height: 12),
            Text(
              r.challenge.domain,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(r.challenge.origin),
            Text('Expires: ${r.challenge.expiresAt}'),
            SelectableText(
              'Account: ${r.compatibleAccounts.first.selection.account.address}',
            ),
            Text('Profile: ${r.compatibleAccounts.first.selection.profile}'),
            Text('Status: ${r.state.name}'),
            if (r.state == ConnectState.awaitingUserApproval) ...[
              FilledButton(
                onPressed: () async {
                  try {
                    await r.approve(r.compatibleAccounts.first);
                    if (r.response != null) {
                      bluetooth?.publish(r.response!);
                    }
                  } catch (e) {
                    showError(e);
                  }
                },
                child: const Text('Approve sign-in'),
              ),
              OutlinedButton(onPressed: r.reject, child: const Text('Reject')),
            ],
          ],
        ],
      ),
    );
  }
}
