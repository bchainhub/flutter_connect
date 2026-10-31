import 'providers.dart';
import 'wallet_provider.dart';
import 'provider_abi.dart';

void extendNativeWalletActions(
  Blockchain blockchain,
  Map<WalletMethod, WalletHandler> h,
  NativeWalletApi api,
  bool Function() disposed,
) {
  Future<Object?> call(String name, [List<Object?> arguments = const []]) {
    if (disposed()) {
      throw ProviderDisconnectedError('Wallet adapter was disposed.');
    }
    return api.call(name, arguments);
  }

  bool has(String name) => api.methods.containsKey(name);
  if ([Blockchain.bitcoin, Blockchain.litecoin].contains(blockchain)) {
    if (has('getChain')) {
      h[WalletMethod.getNetwork] = (_, _) => call('getChain');
    }
    if (!h.containsKey(WalletMethod.switchNetwork) && has('switchChain')) {
      h[WalletMethod.switchNetwork] = (input, _) => call('switchChain', [
        input is String ? input : providerObject(input)['chain'],
      ]);
    }
    if (has('signMessage')) {
      h[WalletMethod.signMessage] = (input, _) {
        if (input is String) return call('signMessage', [input]);
        final r = providerObject(input);
        if (r['message'] is! String) {
          throw InvalidTransactionError('UTXO message must be a string.');
        }
        return call('signMessage', [
          r['message'],
          if (r['type'] != null) r['type'],
        ]);
      };
    }
    if (has('signPsbt')) {
      h[WalletMethod.signPSBT] = (input, _) {
        if (input is String) return call('signPsbt', [input]);
        final r = providerObject(input);
        if (r['psbt'] is! String) {
          throw InvalidTransactionError('Expected native PSBT string.');
        }
        return call('signPsbt', [
          r['psbt'],
          if (r['options'] != null) r['options'],
        ]);
      };
    }
    if (has('signPsbts')) {
      h[WalletMethod.signPSBTs] = (input, _) {
        if (input is List) return call('signPsbts', [input]);
        final r = providerObject(input);
        if (r['psbts'] is! List) {
          throw InvalidTransactionError('Expected native PSBT strings.');
        }
        return call('signPsbts', [
          r['psbts'],
          if (r['options'] != null) r['options'],
        ]);
      };
    }
    final send = blockchain == Blockchain.bitcoin
        ? 'sendBitcoin'
        : 'sendLitecoin';
    if (has(send)) {
      Object handler(Object? input, WalletCallOptions options) {
        final r = providerObject(input);
        final amount = providerQuantity(r['amount']);
        if (r['to'] is! String || amount > BigInt.from(9007199254740991)) {
          throw InvalidTransactionError(
            'Expected a destination and a safe integer amount in native base units.',
          );
        }
        return call(send, [
          r['to'],
          amount.toInt(),
          if (r['options'] != null) r['options'],
        ]);
      }

      h.putIfAbsent(WalletMethod.transfer, () => handler);
      h.putIfAbsent(WalletMethod.sendTransaction, () => handler);
    }
  }
  if (blockchain == Blockchain.aptos) {
    if (has('changeNetwork') && !h.containsKey(WalletMethod.switchNetwork)) {
      h[WalletMethod.switchNetwork] = (input, _) =>
          api.call('changeNetwork', [input]);
    }
    if (has('signAndSubmitTransaction')) {
      h[WalletMethod.signAndSendTransaction] = (input, _) =>
          api.call('signAndSubmitTransaction', [input]);
      h.putIfAbsent(
        WalletMethod.sendTransaction,
        () => h[WalletMethod.signAndSendTransaction]!,
      );
    }
    if (has('account') && !h.containsKey(WalletMethod.getPublicKey)) {
      h[WalletMethod.getPublicKey] = (_, _) async {
        final r = providerObject(await api.call('account'));
        if (r['publicKey'] == null) {
          throw UnsupportedMethodError('Wallet does not expose a public key.');
        }
        return r['publicKey'];
      };
    }
  }
  if (blockchain == Blockchain.near && has('signAndSendTransaction')) {
    h[WalletMethod.signAndSendTransaction] = (input, _) =>
        api.call('signAndSendTransaction', [input]);
    h.putIfAbsent(
      WalletMethod.sendTransaction,
      () => h[WalletMethod.signAndSendTransaction]!,
    );
  }
  if (blockchain == Blockchain.monero) {
    if (has('getPrimaryAddress')) {
      h[WalletMethod.getAddress] = (_, _) => call('getPrimaryAddress');
    }
    if (has('getPublicSpendKey')) {
      h[WalletMethod.getPublicKey] = (_, _) => call('getPublicSpendKey');
    }
    if (has('getNetworkType') && !h.containsKey(WalletMethod.getNetwork)) {
      h[WalletMethod.getNetwork] = (_, _) => call('getNetworkType');
    }
    if (has('relayTx') && !h.containsKey(WalletMethod.sendRawTransaction)) {
      h[WalletMethod.sendRawTransaction] = (input, _) {
        if (input is! String || input.isEmpty) {
          throw InvalidTransactionError(
            'Expected Monero transaction metadata.',
          );
        }
        return call('relayTx', [input]);
      };
    }
    if (has('signMessage')) {
      h[WalletMethod.signMessage] = (input, _) {
        if (input is String) return call('signMessage', [input]);
        final r = providerObject(input);
        if (r['message'] is! String) {
          throw InvalidTransactionError('Monero message must be a string.');
        }
        return call('signMessage', [
          r['message'],
          r['signatureType'],
          r['accountIndex'],
          r['subaddressIndex'],
        ]);
      };
    }
  }
  if (blockchain == Blockchain.core) {
    if (has('getCode')) {
      h[WalletMethod.getCode] = (input, o) => call('getCode', [
        input is String
            ? input
            : providerObject(input)['address'] ?? o.address ?? o.account,
        o.blockTag ?? 'latest',
      ]);
    }
    if (has('getStorage')) {
      h[WalletMethod.getStorage] = (input, o) {
        final r = providerObject(input),
            position = providerQuantity(providerObject(input)['position']);
        if (position >= BigInt.one << 256) {
          throw InvalidTransactionError('Storage position exceeds 256 bits.');
        }
        return call('getStorage', [
          r['address'] ?? o.address ?? o.account,
          position,
          o.blockTag ?? 'latest',
        ]);
      };
    }
    if (has('getBalance')) {
      h[WalletMethod.getBalance] = (input, o) {
        final target = input is String
            ? input
            : input is Map
            ? input['address']
            : o.address ?? o.account;
        return call(
          'getBalance',
          target == null ? [] : [target, o.blockTag ?? 'latest'],
        );
      };
    }
    if (has('getTransactionCount') && !h.containsKey(WalletMethod.getNonce)) {
      h[WalletMethod.getNonce] = (input, o) => call('getTransactionCount', [
        input ?? o.address ?? o.account,
        o.blockTag ?? 'pending',
      ]);
    }
    if (has('call') && !h.containsKey(WalletMethod.callContract)) {
      h[WalletMethod.callContract] = (input, o) => call('call', [
        walletContractRequest(input, blockchain),
        o.blockTag ?? 'latest',
      ]);
    }
    if (h.containsKey(WalletMethod.callContract) &&
        !h.containsKey(WalletMethod.readContract)) {
      h[WalletMethod.readContract] = (input, o) async {
        final r = providerObject(input);
        final data = await h[WalletMethod.callContract]!(input, o);
        return r['abi'] != null
            ? decodeWalletContract({...r, 'data': data}, blockchain)
            : data;
      };
    }
    if (has('getLogs') && !h.containsKey(WalletMethod.getContractEvents)) {
      h[WalletMethod.getContractEvents] = (input, _) =>
          call('getLogs', [input]);
    }
    if (has('broadcastTransaction') &&
        !h.containsKey(WalletMethod.sendRawTransaction)) {
      h[WalletMethod.sendRawTransaction] = (input, _) =>
          call('broadcastTransaction', [input]);
    }

    if (has('getNetworkId')) {
      h[WalletMethod.getChainId] = (_, _) => call('getNetworkId');
    }
    if (has('getEnergyPrice')) {
      h[WalletMethod.getGasPrice] = (_, _) => call('getEnergyPrice');
    }
    if (has('estimateEnergy')) {
      h[WalletMethod.estimateGas] = (input, _) =>
          call('estimateEnergy', [input]);
    }
  }
  if (blockchain == Blockchain.solana && has('signAndSendTransaction')) {
    h[WalletMethod.signAndSendTransaction] = (input, o) => call(
      'signAndSendTransaction',
      [input, if (o.nativeOptions != null) o.nativeOptions],
    );
  }
  if (blockchain == Blockchain.solana && has('signAllTransactions')) {
    h[WalletMethod.signTransactions] = (input, _) {
      if (input is! List || input.isEmpty) {
        throw InvalidTransactionError('Expected native transactions.');
      }
      return call('signAllTransactions', [input]);
    };
  }
  if (blockchain == Blockchain.ton && has('connect')) {
    h[WalletMethod.connect] = (input, _) => api.property('account') != null
        ? Future.value({'account': api.property('account')})
        : api.call('connect', input == null ? [] : [input]);
  }
  if (h.containsKey(WalletMethod.signTransaction) &&
      !h.containsKey(WalletMethod.signTransactions)) {
    h[WalletMethod.signTransactions] = (input, options) async {
      if (input is! List || input.isEmpty) {
        throw InvalidTransactionError('Expected native transactions.');
      }
      final output = <Object?>[];
      for (final tx in input) {
        output.add(await h[WalletMethod.signTransaction]!(tx, options));
      }
      return output;
    };
  }
  if (h.containsKey(WalletMethod.getAccounts)) {
    h.putIfAbsent(
      WalletMethod.getAddresses,
      () => h[WalletMethod.getAccounts]!,
    );
  }
}
