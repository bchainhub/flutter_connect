import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter_connect/flutter_connect.dart';
import 'package:flutter_test/flutter_test.dart';
import 'connect_test.dart'
    show Provider, Signer, Network, selection, vectors, now;

class FakeLinks implements AppLinks {
  final String initial;
  final controller = StreamController<String>.broadcast();
  FakeLinks(this.initial);
  @override
  Future<String?> getInitialLinkString() async => initial;
  @override
  Stream<String> get stringLinkStream => controller.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LinkNetwork extends Network {
  LinkNetwork(super.data);
  @override
  Future<Object?> challenge(ConnectTarget t) async => {
    ...data,
    'requestId': t.requestId,
  };
}

void main() {
  test(
    'cold/warm raw links, duplicate delivery, errors and disposal',
    () async {
      final v = vectors()[1] as Map<String, dynamic>;
      var signed = 0;
      final wallet = Signer(selection(v['proof'] as Map<String, dynamic>), (
        _,
      ) async {
        signed++;
        return const WalletSignature('00');
      });
      final client = ConnectClient(
        accountProvider: Provider([wallet]),
        network: LinkNetwork(v['challenge'] as Map<String, dynamic>),
        now: () => now,
      );
      final initial = ConnectTarget('https://example.com', 'a' * 64).connectUri;
      final fake = FakeLinks(initial), errors = <Object>[], seen = <String>[];
      final subscription = client.requests.listen(
        (r) => seen.add(r.challenge.requestId),
      );
      final links = ConnectLinks(
        client: client,
        onError: errors.add,
        links: fake,
      );
      await links.start();
      fake.controller.add(initial);
      fake.controller.add(
        ConnectTarget('https://example.com', 'c' * 64).connectUri,
      );
      await Future<void>.delayed(Duration.zero);
      expect(seen, ['a' * 64, 'c' * 64]);
      expect(errors, isEmpty);
      expect(signed, 0);
      fake.controller.add('$initial\n');
      await Future<void>.delayed(Duration.zero);
      expect(errors.single, isA<ConnectException>());
      await links.dispose();
      fake.controller.add('invalid');
      await Future<void>.delayed(Duration.zero);
      expect(errors.length, 1);
      await subscription.cancel();
      await client.dispose();
      await fake.controller.close();
    },
  );
}
