import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';

const address = '0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
NativeWalletAdapter adapter(
  Blockchain chain,
  Map<String, NativeWalletMethod> methods, {
  String id = 'test',
  NativeWalletApi? native,
  Map<WalletMethod, WalletHandler> handlers = const {},
}) => NativeWalletAdapter(
  id: id,
  blockchain: chain,
  nativeProvider: native ?? NativeWalletApi(methods: methods),
  handlers: handlers,
);
void main() {
  test(
    'Monero and Zcash native routing, signing and submission stay separate',
    () async {
      final calls = <Object?>[];
      final api = UniversalWalletProvider([
        for (final blockchain in [Blockchain.monero, Blockchain.zcash])
          adapter(blockchain, {
            'connect': (_) => ['${blockchain.name}:address'],
            'getAccounts': (_) => ['${blockchain.name}:address'],
            'getNetwork': (_) => 'mainnet',
            'getBalance': (_) => {'native': blockchain.name, 'balance': '123'},
            'signMessage': (args) => {
              'blockchain': blockchain.name,
              'message': args.single,
            },
            'sendTransaction': (args) {
              calls.add(args.single);
              return '${blockchain.name}:txid';
            },
          }),
      ]);
      expect(api.getAvailableBlockchains(), [
        Blockchain.monero,
        Blockchain.zcash,
      ]);
      expect(calls, isEmpty);
      await api.connect(
        options: const WalletCallOptions(blockchain: Blockchain.monero),
      );
      await api.connect(
        options: const WalletCallOptions(blockchain: Blockchain.zcash),
      );
      expect(api.getConnectedBlockchain(), Blockchain.monero);
      expect(await api.getAccounts(), ['monero:address']);
      expect(
        await api.getBalance(
          options: const WalletCallOptions(
            blockchain: Blockchain.zcash,
            network: 'mainnet',
          ),
        ),
        {'native': 'zcash', 'balance': '123'},
      );
      for (final blockchain in [Blockchain.monero, Blockchain.zcash]) {
        final options = WalletCallOptions(blockchain: blockchain);
        final transaction = Object();
        expect(
          await api.sendTransaction(transaction, options: options),
          '${blockchain.name}:txid',
        );
        expect(identical(calls.last, transaction), true);
        expect(await api.signMessage('hello', options: options), {
          'blockchain': blockchain.name,
          'message': 'hello',
        });
        await expectLater(
          api.signPSBT('not-native', options: options),
          throwsA(isA<UnsupportedMethodError>()),
        );
      }
      expect(api.getConnectedBlockchain(), Blockchain.monero);
      api.dispose();
    },
  );

  test(
    'all native adapters preserve transaction identity and enforce capabilities',
    () async {
      for (final chain in [
        Blockchain.core,
        Blockchain.solana,
        Blockchain.bitcoin,
        Blockchain.litecoin,
        Blockchain.aptos,
        Blockchain.ton,
        Blockchain.near,
        Blockchain.monero,
        Blockchain.zcash,
      ]) {
        Object? seen;
        final native = adapter(chain, {
          'connect': (_) => [],
          'getAccounts': (_) => [address],
          'signTransaction': (args) {
            seen = args.single;
            return seen;
          },
        });
        final api = UniversalWalletProvider([native]);
        await expectLater(
          api.signTransaction({'native': true}),
          throwsA(isA<WalletNotConnectedError>()),
        );
        await api.connect();
        expect(api.getConnectedBlockchain(), chain);
        final tx = Object();
        expect(identical(await api.signTransaction(tx), tx), true);
        expect(identical(seen, tx), true);
        await expectLater(
          api.deployContract({}),
          throwsA(isA<UnsupportedMethodError>()),
        );
        await api.disconnect();
        expect(api.isConnected(), false);
        api.dispose();
      }
    },
  );
  test(
    'EVM mappings, account selection, native RPC allowlist and network guards',
    () async {
      final calls = <Map<String, Object?>>[];
      final native = NativeWalletApi(
        methods: {},
        request: (method, params) {
          calls.add({'method': method, 'params': params});
          if (method == 'eth_chainId') return '0x1';
          if (method == 'eth_sendTransaction') return '0xhash';
          return [address];
        },
      );
      final api = UniversalWalletProvider([
        NativeWalletAdapter(
          id: 'evm',
          blockchain: Blockchain.ethereum,
          nativeProvider: native,
          rpcMethods: ethereumRpcMethods,
        ),
      ]);
      await api.connect();
      expect(await api.getChainId(), '0x1');
      expect(
        await api.sendTransaction({'to': address, 'value': '0x1'}),
        '0xhash',
      );
      expect(calls.last['params'], [
        {'to': address, 'value': '0x1', 'from': address},
      ]);
      await api.signMessage('hello');
      expect(calls.last['params'], ['0x68656c6c6f', address]);
      await api.switchNetwork(5);
      expect(calls.last['params'], [
        {'chainId': '0x5'},
      ]);
      await expectLater(
        api.getBalance(options: const WalletCallOptions(network: '0x2')),
        throwsA(isA<NetworkMismatchError>()),
      );
      await expectLater(
        api.sendTransaction({'to': 'bad'}),
        throwsA(isA<InvalidTransactionError>()),
      );
      await expectLater(
        api.request(method: 'xcb_accounts'),
        throwsA(isA<UnsupportedMethodError>()),
      );
      expect(await api.request(method: 'eth_chainId'), '0x1');
      api.dispose();
    },
  );
  test('CIP-30 enable, CBOR signing and native read operations', () async {
    var enables = 0;
    List<Object?>? signed;
    final authorized = NativeWalletApi(
      methods: {
        'getUsedAddresses': (_) => ['cborAddress'],
        'getUnusedAddresses': (_) => ['unused'],
        'getChangeAddress': (_) => 'cborChange',
        'getNetworkId': (_) => 1,
        'getBalance': (_) => 'cborValue',
        'signTx': (args) {
          signed = args;
          return 'witness';
        },
        'signData': (args) => args,
        'submitTx': (args) => args.single,
      },
    );
    final api = UniversalWalletProvider([
      adapter(Blockchain.cardano, {
        'enable': (_) {
          enables++;
          return authorized;
        },
      }),
    ]);
    expect(enables, 0);
    await api.connect();
    expect(enables, 1);
    expect(await api.getBalance(), 'cborValue');
    expect(await api.getAddress(), 'cborChange');
    expect(
      await api.signTransaction({'cbor': 'abcd', 'partialSign': true}),
      'witness',
    );
    expect(signed, ['abcd', true]);
    expect(await api.signData({'address': 'cborAddress', 'payload': 'abcd'}), [
      'cborAddress',
      'abcd',
    ]);
    expect(await api.sendRawTransaction('abcd'), 'abcd');
    expect(await api.request(method: 'getUnusedAddresses'), ['unused']);
    api.dispose();
  });
  test(
    'provider selection and overrides never silently replace active wallet',
    () async {
      final api = UniversalWalletProvider([
        adapter(Blockchain.core, {
          'connect': (_) => [],
          'getAccounts': (_) => ['one'],
        }, id: 'one'),
        adapter(Blockchain.core, {
          'connect': (_) => [],
          'getAccounts': (_) => ['two'],
        }, id: 'two'),
        adapter(Blockchain.bitcoin, {
          'connect': (_) => [],
          'getAccounts': (_) => ['btc'],
        }, id: 'btc'),
      ]);
      await expectLater(
        api.connect(
          options: const WalletCallOptions(blockchain: Blockchain.core),
        ),
        throwsA(isA<ProviderNotFoundError>()),
      );
      api.selectProvider(Blockchain.core, 'two');
      await api.connect(
        options: const WalletCallOptions(blockchain: Blockchain.core),
      );
      expect(await api.getAccounts(), ['two']);
      await api.connect(
        options: const WalletCallOptions(blockchain: Blockchain.bitcoin),
      );
      expect(api.getConnectedBlockchain(), Blockchain.core);
      expect(
        await api.getAccounts(
          options: const WalletCallOptions(blockchain: Blockchain.bitcoin),
        ),
        ['btc'],
      );
      await api.switchBlockchain(Blockchain.bitcoin);
      expect(api.getConnectedBlockchain(), Blockchain.bitcoin);
      api.dispose();
    },
  );
  test('wallet rejection, duplicate submissions and events', () async {
    final events = StreamController<ProviderEvent>.broadcast(sync: true);
    final pending = Completer<Object?>();
    final native = NativeWalletApi(
      methods: {
        'connect': (_) => [],
        'signMessage': (_) => throw {'code': 4001},
        'sendTransaction': (_) => pending.future,
      },
      events: events.stream,
    );
    final api = UniversalWalletProvider([
      adapter(Blockchain.bitcoin, {}, native: native),
    ]);
    await api.connect();
    await expectLater(
      api.signMessage('hello'),
      throwsA(
        isA<UserRejectedRequestError>().having(
          (e) => e.providerCode,
          'code',
          4001,
        ),
      ),
    );
    final first = api.sendTransaction({'outputs': []});
    await expectLater(
      api.sendTransaction({'outputs': []}),
      throwsA(isA<InvalidTransactionError>()),
    );
    pending.complete('txid');
    expect(await first, 'txid');
    final observed = <String>[];
    final subscription = api.events.listen((e) => observed.add(e.name));
    events.add(ProviderEvent('chainChanged', ['testnet']));
    expect(observed, contains('networkChanged'));
    events.add(ProviderEvent('accountsChanged', [[]]));
    expect(api.getConnectedProvider(), null);
    await subscription.cancel();
    api.dispose();
    await events.close();
  });
}
