import 'provider_compat.dart';
import 'provider_rpc.dart' as rpc;
import 'provider_abi.dart';
export 'provider_rpc.dart' show coreRpcMethods;
import 'dart:async';
import 'dart:convert';
import 'providers.dart';

/// Universal operation names; availability is determined by wallet capabilities.
enum WalletMethod {
  /// Requests wallet authorization and records the approved connection.
  connect,

  /// Ends the selected local wallet session.
  disconnect,

  /// Returns the accounts exposed by the selected wallet.
  getAccounts,

  /// Returns a single authorized account; ambiguous accounts require selection.
  getAccount,

  /// Returns a public key when the native wallet exposes one.
  getPublicKey,

  /// Requests an explicit native network switch.
  switchNetwork,

  /// Requests native registration of a network configuration.
  addNetwork,

  /// Reads the native chain identifier, or Core network ID.
  getChainId,

  /// Reads the native network descriptor without switching networks.
  getNetwork,

  /// Reads the latest block height.
  getBlockNumber,

  /// Reads a block by hash, height or native block tag.
  getBlock,

  /// Reads contract bytecode at an address and optional block tag.
  getCode,

  /// Reads a contract storage slot at an unsigned 256-bit position.
  getStorage,

  /// Looks up a submitted transaction by its hash.
  getTransaction,

  /// Reads a transaction receipt; null means no receipt is available.
  getTransactionReceipt,

  /// Classifies a receipt as pending, mined, confirmed or reverted.
  getTransactionStatus,

  /// Reads the native resource price, including Core energy price.
  getGasPrice,

  /// Estimates transaction resource units, including Core energy.
  estimateGas,

  /// Estimates a fee in native base units; fee caps are upper bounds.
  estimateFee,

  /// Reads a public address balance without requesting authorization.
  getBalance,

  /// Reads balances for the explicit addresses in call options.
  getBalances,

  /// Reads a fungible token balance for an owner.
  getTokenBalance,

  /// Reads balances for the explicit tokens in call options.
  getTokenBalances,

  /// Delegates asset enumeration to an available native SDK handler.
  getAssets,

  /// Delegates NFT enumeration to an available native SDK handler.
  getNFTs,

  /// Reads an account transaction count, using pending state by default.
  getNonce,

  /// Reads native unspent outputs when the selected SDK supports it.
  getUTXOs,

  /// Returns the selected wallet address without choosing among accounts.
  getAddress,

  /// Returns native wallet addresses in their original chain format.
  getAddresses,

  /// Requests native signing of UTF-8 text or message bytes.
  signMessage,

  /// Verifies a supported message signature or delegates to a host handler.
  verifyMessage,

  /// Signs native structured data; Core uses CIP-712 networkId domains.
  signTypedData,

  /// Signs a native transaction without submitting it.
  signTransaction,

  /// Signs native transactions without treating batch signing as broadcast.
  signTransactions,

  /// Requests native signing and submission of a transaction.
  signAndSendTransaction,

  /// Signs a native partially signed Bitcoin transaction with wallet options.
  signPSBT,

  /// Signs a batch of native PSBT values when supported.
  signPSBTs,

  /// Signs chain-specific structured data, such as CIP-30 data.
  signData,

  /// Requests submission through the selected wallet.
  sendTransaction,

  /// Broadcasts a previously signed native transaction.
  sendRawTransaction,

  /// Sends a native-currency amount expressed in integer base units.
  transfer,

  /// Submits a supported fungible token transfer.
  transferToken,

  /// Submits an ERC-721 or ERC-1155 compatible transfer, or native handler.
  transferNFT,

  /// Fills declared transaction fields without signing or submitting.
  prepareTransaction,

  /// Performs a read-only transaction simulation.
  simulateTransaction,

  /// Estimates a transaction fee without submitting the transaction.
  estimateTransactionFee,

  /// Polls for a receipt within explicit timeout and confirmation limits.
  waitForTransaction,

  /// Calls a contract with raw or ABI-encoded calldata.
  callContract,

  /// Calls a contract and decodes its ABI result when supplied.
  readContract,

  /// Requests a wallet-authorized contract write.
  writeContract,

  /// Encodes and submits a supported contract transaction.
  sendContractTransaction,

  /// Combines bytecode and ABI constructor arguments for deployment.
  deployContract,

  /// Estimates gas or Core energy for an encoded contract call.
  estimateContractGas,

  /// Encodes ABI calldata locally using the selected blockchain rules.
  encodeContractCall,

  /// Decodes ABI return data locally using the selected blockchain rules.
  decodeContractResult,

  /// Reads native contract logs for an explicit filter.
  getContractEvents,

  /// Reads contract name, symbol and decimals without an asset indexer.
  getTokenMetadata,

  /// Reads the amount an owner has approved for a spender.
  getTokenAllowance,

  /// Requests a native token allowance approval transaction.
  approveToken,

  /// Requests wallet tracking of a supplied asset when supported.
  watchAsset,

  /// Requests native registration of token metadata when supported.
  addToken,
}

class WalletProviderException implements Exception {
  final String message;
  final Object? cause, providerCode;
  WalletProviderException(this.message, {this.cause, this.providerCode});
  String get name => 'WalletProviderException';
  @override
  String toString() => '$name: $message';
}

class ProviderNotFoundError extends WalletProviderException {
  @override
  String get name => 'ProviderNotFoundError';
  ProviderNotFoundError(super.message, {super.cause, super.providerCode});
}

class WalletNotConnectedError extends WalletProviderException {
  @override
  String get name => 'WalletNotConnectedError';
  WalletNotConnectedError(super.message, {super.cause, super.providerCode});
}

class UnsupportedBlockchainError extends WalletProviderException {
  @override
  String get name => 'UnsupportedBlockchainError';
  UnsupportedBlockchainError(super.message, {super.cause, super.providerCode});
}

class UnsupportedMethodError extends WalletProviderException {
  @override
  String get name => 'UnsupportedMethodError';
  UnsupportedMethodError(super.message, {super.cause, super.providerCode});
}

class UnsupportedCapabilityError extends UnsupportedMethodError {
  @override
  String get name => 'UnsupportedCapabilityError';
  UnsupportedCapabilityError(super.message, {super.cause, super.providerCode});
}

class UserRejectedRequestError extends WalletProviderException {
  @override
  String get name => 'UserRejectedRequestError';
  UserRejectedRequestError(super.message, {super.cause, super.providerCode});
}

class InvalidTransactionError extends WalletProviderException {
  @override
  String get name => 'InvalidTransactionError';
  InvalidTransactionError(super.message, {super.cause, super.providerCode});
}

class NetworkMismatchError extends WalletProviderException {
  @override
  String get name => 'NetworkMismatchError';
  NetworkMismatchError(super.message, {super.cause, super.providerCode});
}

class ProviderDisconnectedError extends WalletProviderException {
  @override
  String get name => 'ProviderDisconnectedError';
  ProviderDisconnectedError(super.message, {super.cause, super.providerCode});
}

class TransactionFailedError extends WalletProviderException {
  @override
  String get name => 'TransactionFailedError';
  TransactionFailedError(super.message, {super.cause, super.providerCode});
}

WalletProviderException normalizeWalletError(Object error) {
  if (error is WalletProviderException) return error;
  final code = error is Map ? error['code'] : null;
  if ([4001, '4001', 'USER_REJECTED', 'ACTION_REJECTED'].contains(code)) {
    return UserRejectedRequestError(
      'Wallet request rejected.',
      cause: error,
      providerCode: code,
    );
  }
  if ([4200, -32601, 'UNSUPPORTED_METHOD'].contains(code)) {
    return UnsupportedMethodError(
      'Wallet method is unavailable.',
      cause: error,
      providerCode: code,
    );
  }
  if (code == 4100) {
    return WalletNotConnectedError(
      'Wallet authorization required.',
      cause: error,
      providerCode: code,
    );
  }
  if (code == -32602) {
    return InvalidTransactionError(
      'Invalid wallet request parameters.',
      cause: error,
      providerCode: code,
    );
  }
  if (code == 4901) {
    return NetworkMismatchError(
      'Wallet is not connected to this network.',
      cause: error,
      providerCode: code,
    );
  }
  if (code == 4900) {
    return ProviderDisconnectedError(
      'Wallet provider disconnected.',
      cause: error,
      providerCode: code,
    );
  }
  return WalletProviderException(
    'Wallet request failed.',
    cause: error,
    providerCode: code,
  );
}

class WalletCallOptions {
  final Blockchain? blockchain;
  final String? providerId, account, requestId;
  final Object? network;
  final String? address, blockTag;
  final List<String>? addresses, tokens;
  final Object? nativeOptions;
  const WalletCallOptions({
    this.blockchain,
    this.providerId,
    this.account,
    this.requestId,
    this.network,
    this.address,
    this.blockTag,
    this.addresses,
    this.tokens,
    this.nativeOptions,
  });
  WalletCallOptions withAccount(String account) => WalletCallOptions(
    blockchain: blockchain,
    providerId: providerId,
    account: account,
    requestId: requestId,
    network: network,
    address: address,
    blockTag: blockTag,
    addresses: addresses,
    tokens: tokens,
    nativeOptions: nativeOptions,
  );
}

class WalletCapabilities {
  final Set<WalletMethod> methods;
  final Set<String> nativeMethods, networks;
  WalletCapabilities({
    required Iterable<WalletMethod> methods,
    Iterable<String> nativeMethods = const [],
    Iterable<String> networks = const [],
  }) : methods = Set.unmodifiable(methods),
       nativeMethods = Set.unmodifiable(nativeMethods),
       networks = Set.unmodifiable(networks);
}

class WalletProviderDescriptor {
  final String id;
  final Blockchain blockchain;
  final ProviderInfo? info;
  final bool connected;
  final WalletCapabilities capabilities;
  WalletProviderDescriptor(WalletAdapter adapter)
    : id = adapter.id,
      blockchain = adapter.blockchain,
      info = adapter.info,
      connected = adapter.connected,
      capabilities = adapter.getCapabilities();
}

typedef WalletHandler =
    FutureOr<Object?> Function(Object? input, WalletCallOptions options);
typedef NativeWalletMethod =
    FutureOr<Object?> Function(List<Object?> arguments);

/// Host-owned SDK bindings. Values and transaction objects retain their native types.
class NativeWalletApi {
  final Map<String, NativeWalletMethod> methods;
  final Object? Function(String) property;
  final FutureOr<Object?> Function(String, Object?)? request;
  final Stream<ProviderEvent>? events;
  final void Function()? onDispose;
  final bool asynchronousConnection;
  NativeWalletApi({
    required Map<String, NativeWalletMethod> methods,
    Object? Function(String)? property,
    this.request,
    this.events,
    this.onDispose,
    this.asynchronousConnection = false,
  }) : methods = Map.unmodifiable(methods),
       property = property ?? ((_) => null);
  Future<Object?> call(
    String name, [
    List<Object?> arguments = const [],
  ]) async {
    final method = methods[name];
    if (method == null) {
      throw UnsupportedMethodError('Native method unavailable: $name');
    }
    return method(arguments);
  }
}

abstract interface class WalletAdapter {
  String get id;
  Blockchain get blockchain;
  Object get nativeProvider;
  ProviderInfo? get info;
  bool get connected;
  WalletCapabilities getCapabilities();
  Future<Object?> invoke(
    WalletMethod method,
    Object? input,
    WalletCallOptions options,
  );
  Future<Object?> request(String method, Object? params);
  Stream<ProviderEvent> get events;
  void dispose();
}

const ethereumRpcMethods = {
  'eth_requestAccounts',
  'eth_accounts',
  'eth_chainId',
  'eth_getBalance',
  'eth_sendTransaction',
  'personal_sign',
  'eth_signTypedData_v4',
  'eth_call',
  'eth_estimateGas',
  'eth_getTransactionReceipt',
  'wallet_switchEthereumChain',
  'wallet_addEthereumChain',
  'wallet_watchAsset',
  'eth_blockNumber',
  'eth_getBlockByNumber',
  'eth_getTransactionByHash',
  'eth_gasPrice',
  'eth_getTransactionCount',
  'eth_sendRawTransaction',
  'eth_getLogs',
  ...rpc.additionalEthereumRpcMethods,
};
const _cardanoNativeMethods = [
  'isEnabled',
  'getNetworkId',
  'getUsedAddresses',
  'getUnusedAddresses',
  'getChangeAddress',
  'getRewardAddresses',
  'getUtxos',
  'getBalance',
  'signTx',
  'signData',
  'submitTx',
  'getCollateral',
  'getExtensions',
];
final _directMethods = <WalletMethod, String>{
  WalletMethod.connect: 'connect',
  WalletMethod.disconnect: 'disconnect',
  WalletMethod.getAccounts: 'getAccounts',
  WalletMethod.getPublicKey: 'getPublicKey',
  WalletMethod.getAddress: 'getAddress',
  WalletMethod.getAddresses: 'getAddresses',
  WalletMethod.getChainId: 'getChainId',
  WalletMethod.getNetwork: 'getNetwork',
  WalletMethod.switchNetwork: 'switchNetwork',
  WalletMethod.getBalance: 'getBalance',
  WalletMethod.getBalances: 'getBalances',
  WalletMethod.getBlockNumber: 'getBlockNumber',
  WalletMethod.getBlock: 'getBlock',
  WalletMethod.getTransaction: 'getTransaction',
  WalletMethod.getTransactionReceipt: 'getTransactionReceipt',
  WalletMethod.getTransactionStatus: 'getTransactionStatus',
  WalletMethod.getGasPrice: 'getGasPrice',
  WalletMethod.estimateGas: 'estimateGas',
  WalletMethod.estimateFee: 'estimateFee',
  WalletMethod.getTokenBalance: 'getTokenBalance',
  WalletMethod.getTokenBalances: 'getTokenBalances',
  WalletMethod.getAssets: 'getAssets',
  WalletMethod.getNFTs: 'getNFTs',
  WalletMethod.getNonce: 'getNonce',
  WalletMethod.verifyMessage: 'verifyMessage',
  WalletMethod.signData: 'signData',
  WalletMethod.transfer: 'transfer',
  WalletMethod.transferToken: 'transferToken',
  WalletMethod.transferNFT: 'transferNFT',
  WalletMethod.prepareTransaction: 'prepareTransaction',
  WalletMethod.simulateTransaction: 'simulateTransaction',
  WalletMethod.estimateTransactionFee: 'estimateTransactionFee',
  WalletMethod.waitForTransaction: 'waitForTransaction',
  WalletMethod.callContract: 'callContract',
  WalletMethod.readContract: 'readContract',
  WalletMethod.writeContract: 'writeContract',
  WalletMethod.sendContractTransaction: 'sendContractTransaction',
  WalletMethod.deployContract: 'deployContract',
  WalletMethod.estimateContractGas: 'estimateContractGas',
  WalletMethod.encodeContractCall: 'encodeContractCall',
  WalletMethod.decodeContractResult: 'decodeContractResult',
  WalletMethod.getContractEvents: 'getContractEvents',
  WalletMethod.getTokenMetadata: 'getTokenMetadata',
  WalletMethod.getTokenAllowance: 'getTokenAllowance',
  WalletMethod.approveToken: 'approveToken',
  WalletMethod.watchAsset: 'watchAsset',
  WalletMethod.addToken: 'addToken',
  WalletMethod.getUTXOs: 'getUtxos',
  WalletMethod.signMessage: 'signMessage',
  WalletMethod.signTypedData: 'signTypedData',
  WalletMethod.signTransaction: 'signTransaction',
  WalletMethod.signTransactions: 'signAllTransactions',
  WalletMethod.signAndSendTransaction: 'signAndSendTransaction',
  WalletMethod.sendTransaction: 'sendTransaction',
  WalletMethod.signPSBT: 'signPsbt',
  WalletMethod.signPSBTs: 'signPsbts',
  WalletMethod.sendRawTransaction: 'sendRawTransaction',
};

abstract interface class PerRequestNetworkWalletAdapter {
  bool get perRequestNetwork;
}

abstract interface class ResettableWalletAdapter {
  void resetConnection();
}

class NativeWalletAdapter implements WalletAdapter, ResettableWalletAdapter {
  @override
  final String id;
  @override
  final Blockchain blockchain;
  @override
  final ProviderInfo? info;
  @override
  final NativeWalletApi nativeProvider;
  late NativeWalletApi _api;
  final Set<String> _rpcMethods, _networks;
  final Set<String> _nativeSubmissions = {};
  final Map<WalletMethod, WalletHandler> _handlers = {};
  final _events = StreamController<ProviderEvent>.broadcast(sync: true);
  StreamSubscription<ProviderEvent>? _subscription;
  final void Function(Object?, WalletMethod)? validateTransaction;
  bool _connected = false;
  bool _connectionRequested = false;
  bool _disposed = false;
  @override
  bool get connected => _connected;
  @override
  Stream<ProviderEvent> get events => _events.stream;
  NativeWalletAdapter({
    required this.id,
    required this.blockchain,
    required this.nativeProvider,
    this.info,
    Iterable<String>? rpcMethods,
    Iterable<String> networks = const [],
    Map<WalletMethod, WalletHandler> handlers = const {},
    this.validateTransaction,
  }) : _rpcMethods = Set.unmodifiable(
         rpcMethods ??
             (blockchain == Blockchain.ethereum
                 ? ['eth_requestAccounts', 'eth_accounts', 'eth_chainId']
                 : blockchain == Blockchain.core
                 ? ['xcb_requestAccounts', 'xcb_accounts', 'xcb_networkId']
                 : <String>[]),
       ),
       _networks = Set.unmodifiable(networks) {
    for (final method in _rpcMethods) {
      if (RegExp(
            r'(private.?key|seed.?phrase|mnemonic|secret.?key)',
            caseSensitive: false,
          ).hasMatch(method) ||
          (blockchain == Blockchain.ethereum &&
              !RegExp(
                r'^(eth_|wallet_|personal_sign$|net_version$|web3_clientVersion$)',
              ).hasMatch(method)) ||
          (blockchain != Blockchain.ethereum &&
              RegExp(r'^eth_').hasMatch(method)) ||
          (blockchain != Blockchain.ethereum &&
              blockchain != Blockchain.core &&
              method == 'personal_sign')) {
        throw UnsupportedMethodError(
          'Incompatible or secret-bearing RPC method.',
        );
      }
    }
    _api = nativeProvider;
    for (final entry in _directMethods.entries) {
      if (_api.methods.containsKey(entry.value)) {
        _handlers[entry.key] = (input, _) =>
            _callNative(entry.value, input == null ? [] : [input]);
      }
    }
    switch (blockchain) {
      case Blockchain.ethereum:
        if (_api.request != null) _handlers.clear();
        _bindRpc();
      case Blockchain.cardano:
        _handlers.clear();
        _bindCardano();
        if (_api.methods.containsKey('enable')) {
          _handlers[WalletMethod.connect] = (_, _) async {
            final authorized = await _callNative('enable');
            if (authorized is! NativeWalletApi) {
              throw WalletNotConnectedError('Invalid CIP-30 API.');
            }
            _api = authorized;
            _bindCardano();
            return _handlers[WalletMethod.getAccounts]?.call(
              null,
              const WalletCallOptions(),
            );
          };
        }
      case Blockchain.solana:
        if (_api.methods.containsKey('signMessage')) {
          _handlers[WalletMethod.signMessage] = (input, _) => _callNative(
            'signMessage',
            [input is String ? utf8.encode(input) : input],
          );
        }
        _handlers[WalletMethod.getAccounts] = (_, _) {
          final key = _api.property('publicKey');
          return key == null ? [] : [key];
        };
        _handlers[WalletMethod.getPublicKey] = (_, _) =>
            _api.property('publicKey');
      case Blockchain.aptos:
        if (_api.methods.containsKey('account')) {
          _handlers[WalletMethod.getAccounts] = (_, _) async => [
            await _callNative('account'),
          ];
        }
        if (_api.methods.containsKey('network')) {
          _handlers[WalletMethod.getNetwork] = (_, _) => _callNative('network');
        }
        if (_api.methods.containsKey('signAndSubmitTransaction')) {
          _handlers[WalletMethod.signAndSendTransaction] = (input, _) =>
              _callNative('signAndSubmitTransaction', [input]);
        }
      case Blockchain.near:
        if (_api.methods.containsKey('signIn')) {
          _handlers[WalletMethod.connect] = (input, _) =>
              _callNative('signIn', [input]);
        }
        if (_api.methods.containsKey('signOut')) {
          _handlers[WalletMethod.disconnect] = (_, _) => _callNative('signOut');
        }
      case Blockchain.ton:
        _handlers[WalletMethod.getAccounts] = (_, _) {
          final account = _api.property('account');
          return account == null ? [] : [account];
        };
        _handlers[WalletMethod.getChainId] = (_, _) {
          final account = _api.property('account');
          return account is Map ? account['chain'] : null;
        };
        if (_api.methods.containsKey('signData')) {
          _handlers[WalletMethod.signData] = (input, _) =>
              _callNative('signData', [input]);
        }
      case Blockchain.core:
        _bindRpc();
      case Blockchain.monero:
      case Blockchain.zcash:
        break;
      case Blockchain.bitcoin:
      case Blockchain.litecoin:
        if (_api.methods.containsKey('requestAccounts')) {
          _handlers[WalletMethod.connect] = (_, _) =>
              _callNative('requestAccounts');
        }
        if (_api.methods.containsKey('pushTx')) {
          _handlers[WalletMethod.sendRawTransaction] = (input, _) =>
              _callNative('pushTx', [input]);
        }
    }
    extendNativeWalletActions(blockchain, _handlers, _api, () => _disposed);
    _handlers.putIfAbsent(
      WalletMethod.disconnect,
      () =>
          (_, _) => null,
    );
    _handlers.addAll(handlers);
    _subscription = nativeProvider.events?.listen((event) {
      if (event.name == 'connect' && _connectionRequested && !_disposed) {
        _connected = true;
      }
      if (event.name == 'disconnect' ||
          (event.name == 'accountsChanged' &&
              event.arguments.isNotEmpty &&
              event.arguments.first is List &&
              (event.arguments.first as List).isEmpty)) {
        _connected = false;
        _connectionRequested = false;
      }
      _events.add(event);
    });
  }
  Future<Object?> _callNative(
    String name, [
    List<Object?> arguments = const [],
  ]) {
    if (_disposed) {
      throw ProviderDisconnectedError('Wallet adapter was disposed.');
    }
    return _api.call(name, arguments);
  }

  void _bindRpc() {
    final mapped = rpc.providerRpcActions(
      blockchain: blockchain,
      methods: _api.request == null ? {} : _rpcMethods,
      request: request,
      disposed: () => _disposed,
      emit: _events.add,
    );
    for (final entry in mapped.entries) {
      _handlers.putIfAbsent(entry.key, () => entry.value);
    }
  }

  void _bindCardano() {
    final bindings = <WalletMethod, String>{
      WalletMethod.getAccounts: 'getUsedAddresses',
      WalletMethod.getAddresses: 'getUsedAddresses',
      WalletMethod.getAddress: 'getChangeAddress',
      WalletMethod.getChainId: 'getNetworkId',
      WalletMethod.getBalance: 'getBalance',
      WalletMethod.getUTXOs: 'getUtxos',
      WalletMethod.sendRawTransaction: 'submitTx',
    };
    for (final entry in bindings.entries) {
      if (_api.methods.containsKey(entry.value)) {
        _handlers[entry.key] = (input, _) =>
            _callNative(entry.value, input == null ? [] : [input]);
      }
    }
    if (_api.methods.containsKey('signTx')) {
      _handlers[WalletMethod.signTransaction] = (input, _) {
        final value = input is String
            ? {'cbor': input, 'partialSign': false}
            : _object(input);
        if (value['cbor'] is! String ||
            !RegExp(
              r'^(?:[0-9a-fA-F]{2})+$',
            ).hasMatch(value['cbor'] as String) ||
            (value['partialSign'] != null && value['partialSign'] is! bool)) {
          throw InvalidTransactionError(
            'Expected Cardano CBOR hex and optional partialSign boolean.',
          );
        }
        return _callNative('signTx', [
          value['cbor'],
          value['partialSign'] ?? false,
        ]);
      };
    }
    if (_api.methods.containsKey('signTx')) {
      _handlers[WalletMethod.signTransactions] = (input, options) async {
        if (input is! List || input.isEmpty) {
          throw InvalidTransactionError('Expected Cardano transactions.');
        }
        final output = <Object?>[];
        for (final tx in input) {
          output.add(
            await _handlers[WalletMethod.signTransaction]!(tx, options),
          );
        }
        return output;
      };
    }
    if (_api.methods.containsKey('signData')) {
      _handlers[WalletMethod.signData] = (input, _) {
        final value = _object(input);
        return _callNative('signData', [value['address'], value['payload']]);
      };
    }
  }

  @override
  WalletCapabilities getCapabilities() => WalletCapabilities(
    methods: _handlers.keys,
    nativeMethods: {
      if (_api.request != null) ..._rpcMethods,
      if (blockchain == Blockchain.cardano)
        ..._cardanoNativeMethods.where(_api.methods.containsKey),
    },
    networks: _networks,
  );
  @override
  Future<Object?> invoke(
    WalletMethod method,
    Object? input,
    WalletCallOptions options,
  ) async {
    if (method == WalletMethod.connect) _connectionRequested = true;
    if (method == WalletMethod.disconnect) {
      _connectionRequested = false;
      _connected = false;
    }
    final handler = _handlers[method];
    if (handler == null) {
      throw UnsupportedMethodError(
        '${blockchain.name}: ${method.name} unavailable.',
      );
    }
    try {
      validateNativeInput(method, input, blockchain);
      if (method == WalletMethod.signMessage &&
          [
            Blockchain.core,
            Blockchain.ethereum,
            Blockchain.solana,
            Blockchain.monero,
            Blockchain.zcash,
            Blockchain.bitcoin,
            Blockchain.litecoin,
          ].contains(blockchain) &&
          input is! Map) {
        providerBytes(input);
      }
      if (blockchain == Blockchain.ethereum &&
          input is Map &&
          input['from'] != null &&
          options.account != null &&
          input['from'].toString().toLowerCase() !=
              options.account!.toLowerCase()) {
        throw InvalidTransactionError(
          'Transaction sender does not match the selected account.',
        );
      }
      if (_isMutation(method.name)) validateTransaction?.call(input, method);
      final result = await handler(input, options);
      if (_disposed) {
        throw ProviderDisconnectedError('Wallet adapter was disposed.');
      }
      if (method == WalletMethod.connect) {
        _connected =
            blockchain == Blockchain.ton &&
                nativeProvider.asynchronousConnection
            ? _connected || _api.property('account') != null
            : true;
        if (_connected) _events.add(ProviderEvent('connect', [result]));
      }
      if (method == WalletMethod.disconnect) {
        _connected = false;
        _events.add(ProviderEvent('disconnect', [result]));
      }
      return result;
    } catch (error) {
      if (method == WalletMethod.connect) _connectionRequested = false;
      final normalized = normalizeWalletError(error);
      if (RegExp(r'^(send|transfer|write|deploy)').hasMatch(method.name) &&
          normalized.runtimeType == WalletProviderException) {
        throw TransactionFailedError(
          'Native transaction failed.',
          cause: error,
          providerCode: normalized.providerCode,
        );
      }
      throw normalized;
    }
  }

  @override
  Future<Object?> request(String method, Object? params) async {
    if (_disposed) {
      throw ProviderDisconnectedError('Wallet adapter was disposed.');
    }
    if (blockchain == Blockchain.cardano &&
        _cardanoNativeMethods.contains(method) &&
        _api.methods.containsKey(method)) {
      return _callNative(
        method,
        params is List
            ? params.cast<Object?>()
            : params == null
            ? []
            : [params],
      );
    }
    if (!_rpcMethods.contains(method) || _api.request == null) {
      throw UnsupportedMethodError('Native RPC not declared: $method');
    }
    try {
      final submission = RegExp(
        r'_(sendTransaction|sendRawTransaction)$',
      ).hasMatch(method);
      final key = '$method:${_fingerprint(params)}';
      if (submission && _nativeSubmissions.contains(key)) {
        throw InvalidTransactionError('Duplicate native submission.');
      }
      if (submission) _nativeSubmissions.add(key);
      try {
        return await _api.request!(method, params);
      } finally {
        _nativeSubmissions.remove(key);
      }
    } catch (error) {
      throw normalizeWalletError(error);
    }
  }

  @override
  void resetConnection() {
    _connected = false;
    _connectionRequested = false;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _connected = false;
    _connectionRequested = false;
    _subscription?.cancel();
    nativeProvider.onDispose?.call();
    _events.close();
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) {
    throw InvalidTransactionError('Expected a native request object.');
  }
  return Map<String, Object?>.from(value);
}

bool _isMutation(String method) =>
    RegExp(r'^(sign|send|transfer|write|deploy|approve)').hasMatch(method);
bool _requiresConnection(WalletMethod method) =>
    _isMutation(method.name) ||
    [
      WalletMethod.switchNetwork,
      WalletMethod.addNetwork,
      WalletMethod.watchAsset,
      WalletMethod.addToken,
    ].contains(method);
void validateNativeInput(
  WalletMethod method,
  Object? input,
  Blockchain blockchain,
) {
  if (RegExp(
    r'^(sign|send|prepare|simulate).*Transactions?$',
  ).hasMatch(method.name)) {
    if (input == null ||
        input is Function ||
        input is num ||
        input is bool ||
        input == '') {
      throw InvalidTransactionError('Expected a native transaction.');
    }
    if (blockchain == Blockchain.ethereum &&
        method != WalletMethod.sendRawTransaction &&
        method != WalletMethod.signTransactions) {
      final tx = _object(input);
      for (final field in [
        'value',
        'gas',
        'gasPrice',
        'maxFeePerGas',
        'maxPriorityFeePerGas',
        'nonce',
      ]) {
        if (tx[field] != null) providerQuantity(tx[field]);
      }
      if (tx['to'] != null &&
          (tx['to'] is! String ||
              !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(tx['to'] as String))) {
        throw InvalidTransactionError('Invalid EVM destination.');
      }
      if (tx['data'] != null &&
          (tx['data'] is! String ||
              !RegExp(
                r'^0x(?:[0-9a-fA-F]{2})*$',
              ).hasMatch(tx['data'] as String))) {
        throw InvalidTransactionError('Invalid EVM calldata.');
      }
    }
  }
}

class UniversalWalletProvider {
  final Map<String, WalletAdapter> _adapters = {};
  final Map<Blockchain, String> _selected = {};
  final Map<String, StreamSubscription<ProviderEvent>> _subscriptions = {};
  final _events = StreamController<ProviderEvent>.broadcast(sync: true);
  final Set<String> _pending = {}, _consumed = {};
  WalletAdapter? _active;
  bool _connecting = false;
  final Map<String, ({bool activate, Object? network})> _pendingConnections =
      {};
  bool _disposed = false;
  Stream<ProviderEvent> get events => _events.stream;
  UniversalWalletProvider([Iterable<WalletAdapter> adapters = const []]) {
    for (final adapter in adapters) {
      registerProvider(adapter);
    }
  }
  String _key(WalletAdapter adapter) =>
      '${adapter.blockchain.name}:${adapter.id}';
  void registerProvider(WalletAdapter adapter) {
    if (_disposed) {
      throw ProviderDisconnectedError('Provider API was disposed.');
    }
    final key = _key(adapter);
    final existing = _adapters[key];
    if (existing != null) {
      if (identical(existing.nativeProvider, adapter.nativeProvider)) {
        if (!identical(existing, adapter)) adapter.dispose();
        return;
      }
      throw ProviderNotFoundError('Provider identifier is already registered.');
    }
    if (_adapters.values.any(
      (a) =>
          a.blockchain == adapter.blockchain &&
          identical(a.nativeProvider, adapter.nativeProvider),
    )) {
      adapter.dispose();
      return;
    }
    _adapters[key] = adapter;
    _subscriptions[key] = adapter.events.listen((event) {
      final pending = _pendingConnections[key];
      if (event.name == 'disconnect') _pendingConnections.remove(key);
      if (event.name == 'connect' &&
          pending != null &&
          !_connecting &&
          adapter.connected) {
        _pendingConnections.remove(key);
        unawaited(() async {
          try {
            if (pending.network != null) {
              await _checkNetwork(adapter, pending.network!);
            }
            if (_disposed || !adapter.connected) return;
            if (_active == null || pending.activate) {
              _active = adapter;
              _events.add(
                ProviderEvent('connect', [
                  adapter.blockchain.name,
                  adapter.id,
                  ...event.arguments,
                ]),
              );
            }
          } catch (error) {
            if (adapter is ResettableWalletAdapter) {
              (adapter as ResettableWalletAdapter).resetConnection();
            }
            if (!_disposed) {
              _events.add(
                ProviderEvent('disconnect', [
                  adapter.blockchain.name,
                  adapter.id,
                  error,
                ]),
              );
            }
          }
        }());
        return;
      }
      if (!identical(_active, adapter) ||
          (event.name == 'connect' && _connecting)) {
        return;
      }
      if (event.name == 'disconnect' ||
          (event.name == 'accountsChanged' &&
              event.arguments.isNotEmpty &&
              event.arguments.first is List &&
              (event.arguments.first as List).isEmpty)) {
        _active = null;
      }
      _events.add(
        ProviderEvent(event.name, [
          adapter.blockchain.name,
          adapter.id,
          ...event.arguments,
        ]),
      );
      if (event.name == 'chainChanged') {
        _events.add(
          ProviderEvent('networkChanged', [
            adapter.blockchain.name,
            adapter.id,
            ...event.arguments,
          ]),
        );
      }
    });
    _events.add(
      ProviderEvent('providerChanged', [
        adapter.blockchain.name,
        adapter.id,
        {'available': true},
      ]),
    );
  }

  WalletAdapter _resolve([
    WalletCallOptions options = const WalletCallOptions(),
  ]) {
    if (_disposed) {
      throw ProviderDisconnectedError('Provider API was disposed.');
    }
    final blockchain = options.blockchain ?? _active?.blockchain;
    final candidates = _adapters.values
        .where((a) => blockchain == null || a.blockchain == blockchain)
        .toList();
    final id = options.providerId ?? _selected[blockchain];
    if (id != null) {
      for (final adapter in candidates) {
        if (adapter.id == id) return adapter;
      }
      throw ProviderNotFoundError('Selected provider is unavailable.');
    }
    if (candidates.length != 1) {
      throw ProviderNotFoundError(
        candidates.isEmpty
            ? 'No compatible wallet provider.'
            : 'Select a wallet explicitly.',
      );
    }
    return candidates.single;
  }

  List<WalletProviderDescriptor> getProviders([Blockchain? blockchain]) =>
      List.unmodifiable(
        _adapters.values
            .where((a) => blockchain == null || a.blockchain == blockchain)
            .map(WalletProviderDescriptor.new),
      );
  WalletAdapter getProvider([Blockchain? blockchain, String? providerId]) =>
      _resolve(
        WalletCallOptions(blockchain: blockchain, providerId: providerId),
      );
  WalletAdapter? getConnectedProvider() => _active;
  Blockchain? getConnectedBlockchain() => _active?.blockchain;
  List<Blockchain> getAvailableBlockchains() =>
      List.unmodifiable(_adapters.values.map((a) => a.blockchain).toSet());
  WalletCapabilities getCapabilities([
    WalletCallOptions options = const WalletCallOptions(),
  ]) {
    final caps = _resolve(options).getCapabilities();
    return WalletCapabilities(
      methods: {
        ...caps.methods,
        if (caps.methods.contains(WalletMethod.getAccounts)) ...[
          WalletMethod.getAccount,
          WalletMethod.getAddress,
          WalletMethod.getAddresses,
        ],
        if (caps.methods.contains(WalletMethod.getChainId))
          WalletMethod.getNetwork,
      },
      nativeMethods: caps.nativeMethods,
      networks: caps.networks,
    );
  }

  bool isConnected([WalletCallOptions options = const WalletCallOptions()]) {
    try {
      return _resolve(options).connected;
    } catch (_) {
      return false;
    }
  }

  void selectProvider(Blockchain blockchain, String providerId) {
    final adapter = _resolve(
      WalletCallOptions(blockchain: blockchain, providerId: providerId),
    );
    if (_active?.blockchain == blockchain && !identical(_active, adapter)) {
      throw WalletNotConnectedError(
        'Disconnect the active wallet before selecting another.',
      );
    }
    _selected[blockchain] = providerId;
    _events.add(
      ProviderEvent('providerChanged', [blockchain.name, providerId]),
    );
  }

  /// Requests wallet authorization and records the approved connection.
  Future<Object?> connect({
    WalletCallOptions options = const WalletCallOptions(),
    bool activate = false,
    Object? input,
  }) async {
    if (_connecting) {
      throw InvalidTransactionError('A connection request is already pending.');
    }
    final adapter = _resolve(options);
    final connectedBefore = adapter.connected;
    _connecting = true;
    _pendingConnections[_key(adapter)] = (
      activate: activate,
      network: options.network,
    );
    try {
      final result = await adapter.invoke(WalletMethod.connect, input, options);
      _selected[adapter.blockchain] = adapter.id;
      if (!adapter.connected) return result;
      _pendingConnections.remove(_key(adapter));
      if (options.network != null) {
        await _checkNetwork(adapter, options.network!);
      }
      if (_disposed) {
        throw ProviderDisconnectedError('Provider API was disposed.');
      }
      _selected[adapter.blockchain] = adapter.id;
      if (_active == null || activate || identical(_active, adapter)) {
        _active = adapter;
        _events.add(
          ProviderEvent('connect', [
            adapter.blockchain.name,
            adapter.id,
            result,
          ]),
        );
      }
      return result;
    } catch (error) {
      if (!connectedBefore && adapter is ResettableWalletAdapter) {
        (adapter as ResettableWalletAdapter).resetConnection();
      }
      _pendingConnections.remove(_key(adapter));
      rethrow;
    } finally {
      _connecting = false;
    }
  }

  Future<void> disconnect([
    WalletCallOptions options = const WalletCallOptions(),
  ]) async {
    if (_active == null &&
        options.blockchain == null &&
        options.providerId == null) {
      final keys = _pendingConnections.keys.toList();
      _pendingConnections.clear();
      for (final key in keys) {
        await _adapters[key]?.invoke(
          WalletMethod.disconnect,
          null,
          const WalletCallOptions(),
        );
      }
      return;
    }
    final adapter = _resolve(options);
    _pendingConnections.remove(_key(adapter));
    await adapter.invoke(WalletMethod.disconnect, null, options);
    if (identical(_active, adapter)) _active = null;
  }

  Future<void> switchBlockchain(
    Blockchain blockchain, {
    String? providerId,
  }) async {
    final adapter = _resolve(
      WalletCallOptions(blockchain: blockchain, providerId: providerId),
    );
    if (!adapter.connected) {
      throw WalletNotConnectedError(
        'Connect this wallet explicitly before selecting it.',
      );
    }
    _active = adapter;
    _selected[blockchain] = adapter.id;
    _events.add(
      ProviderEvent('providerChanged', [blockchain.name, adapter.id]),
    );
  }

  Future<void> _checkNetwork(WalletAdapter adapter, Object expected) async {
    if (adapter is PerRequestNetworkWalletAdapter &&
        (adapter as PerRequestNetworkWalletAdapter).perRequestNetwork) {
      return;
    }
    final methods = adapter.getCapabilities().methods;
    final method = methods.contains(WalletMethod.getChainId)
        ? WalletMethod.getChainId
        : methods.contains(WalletMethod.getNetwork)
        ? WalletMethod.getNetwork
        : null;
    if (method == null) {
      throw UnsupportedMethodError('Cannot verify wallet network.');
    }
    final result = await adapter.invoke(
      method,
      null,
      const WalletCallOptions(),
    );
    if (!rpc.providerNetworkMatches(result, expected, adapter.blockchain)) {
      throw NetworkMismatchError(
        'Connected network does not match requested network.',
      );
    }
  }

  Future<Object?> execute(
    WalletMethod method, [
    Object? input,
    WalletCallOptions options = const WalletCallOptions(),
  ]) async {
    if (method == WalletMethod.connect) {
      return connect(options: options, input: input);
    }
    if (method == WalletMethod.disconnect) {
      await disconnect(options);
      return null;
    }
    final adapter = _resolve(options);
    if (_requiresConnection(method) && !adapter.connected) {
      throw WalletNotConnectedError('Connect the selected wallet first.');
    }
    if (method == WalletMethod.signTypedData && input is String) {
      try {
        input = providerObject(jsonDecode(input));
      } catch (_) {
        throw InvalidTransactionError('Expected typed data JSON.');
      }
    }
    if (method == WalletMethod.switchNetwork ||
        method == WalletMethod.addNetwork) {
      if (options.network != null) {
        await _checkNetwork(adapter, options.network!);
      }
    } else if (method == WalletMethod.signTransactions && input is List) {
      for (final tx in input) {
        final network = rpc.assertProviderPayloadNetwork(
          tx,
          options.network,
          adapter.blockchain,
        );
        if (network != null) await _checkNetwork(adapter, network);
      }
    } else {
      final network = rpc.assertProviderPayloadNetwork(
        input,
        options.network,
        adapter.blockchain,
      );
      if (network != null) await _checkNetwork(adapter, network);
    }
    final capabilities = adapter.getCapabilities();
    final aliases = {
      WalletMethod.getAccount: WalletMethod.getAccounts,
      WalletMethod.getAddress: WalletMethod.getAccounts,
      WalletMethod.getAddresses: WalletMethod.getAccounts,
      WalletMethod.getNetwork: WalletMethod.getChainId,
    };
    final native = capabilities.methods.contains(method)
        ? method
        : aliases[method];
    if (native == null || !capabilities.methods.contains(native)) {
      throw UnsupportedMethodError('${method.name} unavailable.');
    }
    final mutation = _isMutation(method.name);
    final key = options.requestId != null
        ? '${_key(adapter)}:request:${options.requestId}'
        : '${_key(adapter)}:${method.name}:${_fingerprint(input)}';
    _guard(key, mutation, options.requestId);
    try {
      var effective = options;
      if (options.account != null &&
          capabilities.methods.contains(WalletMethod.getAccounts)) {
        final accounts = await adapter.invoke(
          WalletMethod.getAccounts,
          null,
          const WalletCallOptions(),
        );
        if (accounts is! List ||
            !accounts.any(
              (a) => _sameProviderAccount(
                _accountAddress(a),
                options.account,
                adapter.blockchain,
              ),
            )) {
          throw WalletNotConnectedError(
            'The requested account is not authorized.',
          );
        }
      }
      if ([Blockchain.ethereum, Blockchain.core].contains(adapter.blockchain) &&
          capabilities.methods.contains(WalletMethod.getAccounts) &&
          options.account == null &&
          [
            WalletMethod.signMessage,
            WalletMethod.signTypedData,
            WalletMethod.sendTransaction,
            WalletMethod.sendContractTransaction,
            WalletMethod.writeContract,
            WalletMethod.getBalance,
            WalletMethod.getNonce,
            WalletMethod.signTransaction,
            WalletMethod.signTransactions,
            WalletMethod.signAndSendTransaction,
            WalletMethod.approveToken,
            WalletMethod.transferToken,
            WalletMethod.transferNFT,
            WalletMethod.transfer,
            WalletMethod.deployContract,
            WalletMethod.prepareTransaction,
            WalletMethod.getTokenBalance,
            WalletMethod.getTokenBalances,
            WalletMethod.getTokenAllowance,
            WalletMethod.getBalances,
          ].contains(method) &&
          !((options.address != null ||
                  options.addresses?.isNotEmpty == true) &&
              method.name.startsWith('get'))) {
        final accounts = await adapter.invoke(
          WalletMethod.getAccounts,
          null,
          const WalletCallOptions(),
        );
        if (accounts is! List ||
            accounts.length != 1 ||
            _accountAddress(accounts.first) == null) {
          throw WalletNotConnectedError('Select one authorized account.');
        }
        effective = options.withAccount(_accountAddress(accounts.first)!);
      }
      if (_requiresConnection(method) && !adapter.connected) {
        throw WalletNotConnectedError('Wallet disconnected before execution.');
      }
      final result = await adapter.invoke(native, input, effective);
      if ([WalletMethod.getAccount, WalletMethod.getAddress].contains(method) &&
          native == WalletMethod.getAccounts) {
        final accounts = result is List && options.account != null
            ? result
                  .where(
                    (a) => _sameProviderAccount(
                      _accountAddress(a),
                      options.account,
                      adapter.blockchain,
                    ),
                  )
                  .toList()
            : result;
        if (accounts is! List || accounts.length != 1) {
          throw WalletNotConnectedError('Select one authorized account.');
        }
        return method == WalletMethod.getAddress
            ? _accountAddress(accounts.single)
            : accounts.single;
      }
      return result;
    } catch (error) {
      throw normalizeWalletError(error);
    } finally {
      _pending.remove(key);
    }
  }

  void _guard(String key, bool mutation, String? requestId) {
    if (!mutation) return;
    if (_pending.contains(key) ||
        (requestId != null && _consumed.contains(key))) {
      throw InvalidTransactionError('Duplicate wallet operation.');
    }
    if (requestId != null && _consumed.length >= 4096) {
      throw InvalidTransactionError('Request identifier limit reached.');
    }
    _pending.add(key);
    if (requestId != null) _consumed.add(key);
  }

  Future<Object?> request({
    required String method,
    Object? params,
    WalletCallOptions options = const WalletCallOptions(),
  }) async {
    final adapter = _resolve(options);
    if (!adapter.getCapabilities().nativeMethods.contains(method)) {
      throw UnsupportedMethodError('Native method not declared.');
    }
    Object? payload;
    if (RegExp(
          r'_(sendTransaction|signTransaction|call|estimateGas|estimateEnergy)$',
        ).hasMatch(method) &&
        params is List &&
        params.isNotEmpty) {
      payload = params.first;
    }
    if (RegExp(r'_signTypedData_v4$').hasMatch(method) &&
        params is List &&
        params.length > 1) {
      try {
        payload = params[1] is String
            ? jsonDecode(params[1] as String)
            : params[1];
      } catch (_) {
        throw InvalidTransactionError('Expected typed data JSON.');
      }
    }
    final expected = rpc.assertProviderPayloadNetwork(
      payload,
      options.network,
      adapter.blockchain,
    );
    if (expected != null) await _checkNetwork(adapter, expected);
    final passive = RegExp(
      r'^(eth|xcb|core)_(accounts|chainId|networkId|blockNumber|gasPrice|energyPrice|get[A-Z]|call|estimateGas|estimateEnergy|feeHistory|maxPriorityFeePerGas)',
    ).hasMatch(method);
    if (!passive && !adapter.connected) {
      throw WalletNotConnectedError(
        'Connect the wallet before a native request.',
      );
    }
    final key = options.requestId != null
        ? '${_key(adapter)}:request:${options.requestId}'
        : '${_key(adapter)}:native:$method:${_fingerprint(params)}';
    _guard(key, !passive, options.requestId);
    try {
      return await adapter.request(method, params);
    } finally {
      _pending.remove(key);
    }
  }

  /// Returns the accounts exposed by the selected wallet.
  Future<Object?> getAccounts({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getAccounts, null, options);

  /// Returns a single authorized account; ambiguous accounts require selection.
  Future<Object?> getAccount({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getAccount, null, options);

  /// Returns a public key when the native wallet exposes one.
  Future<Object?> getPublicKey({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getPublicKey, null, options);

  /// Requests an explicit native network switch.
  Future<Object?> switchNetwork(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.switchNetwork, input, options);

  /// Requests native registration of a network configuration.
  Future<Object?> addNetwork(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.addNetwork, input, options);

  /// Reads the native chain identifier, or Core network ID.
  Future<Object?> getChainId({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getChainId, null, options);

  /// Reads the native network descriptor without switching networks.
  Future<Object?> getNetwork({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getNetwork, null, options);

  /// Reads the latest block height.
  Future<Object?> getBlockNumber({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getBlockNumber, null, options);

  /// Reads a block by hash, height or native block tag.
  Future<Object?> getBlock(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getBlock, input, options);

  /// Looks up a submitted transaction by its hash.
  Future<Object?> getTransaction(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getTransaction, input, options);

  /// Reads a transaction receipt; null means no receipt is available.
  Future<Object?> getTransactionReceipt(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getTransactionReceipt, input, options);

  /// Classifies a receipt as pending, mined, confirmed or reverted.
  Future<Object?> getTransactionStatus(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getTransactionStatus, input, options);

  /// Reads the native resource price, including Core energy price.
  Future<Object?> getGasPrice({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getGasPrice, null, options);

  /// Estimates transaction resource units, including Core energy.
  Future<Object?> estimateGas(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.estimateGas, input, options);

  /// Estimates a fee in native base units; fee caps are upper bounds.
  Future<Object?> estimateFee(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.estimateFee, input, options);

  /// Reads contract bytecode at an address and optional block tag.
  Future<Object?> getCode(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getCode, input, options);

  /// Reads a contract storage slot at an unsigned 256-bit position.
  Future<Object?> getStorage(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getStorage, input, options);

  /// Reads a public address balance without requesting authorization.
  Future<Object?> getBalance({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getBalance, null, options);

  /// Reads balances for the explicit addresses in call options.
  Future<Object?> getBalances({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getBalances, null, options);

  /// Reads a fungible token balance for an owner.
  Future<Object?> getTokenBalance(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getTokenBalance, input, options);

  /// Reads balances for the explicit tokens in call options.
  Future<Object?> getTokenBalances({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getTokenBalances, null, options);

  /// Delegates asset enumeration to an available native SDK handler.
  Future<Object?> getAssets({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getAssets, null, options);

  /// Delegates NFT enumeration to an available native SDK handler.
  Future<Object?> getNFTs({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getNFTs, null, options);

  /// Reads an account transaction count, using pending state by default.
  Future<Object?> getNonce({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getNonce, null, options);

  /// Reads native unspent outputs when the selected SDK supports it.
  Future<Object?> getUTXOs({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getUTXOs, null, options);

  /// Returns the selected wallet address without choosing among accounts.
  Future<Object?> getAddress({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getAddress, null, options);

  /// Returns native wallet addresses in their original chain format.
  Future<Object?> getAddresses({
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getAddresses, null, options);

  /// Requests native signing of UTF-8 text or message bytes.
  Future<Object?> signMessage(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.signMessage, input, options);

  /// Verifies a supported message signature or delegates to a host handler.
  Future<Object?> verifyMessage(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.verifyMessage, input, options);

  /// Signs native structured data; Core uses CIP-712 networkId domains.
  Future<Object?> signTypedData(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.signTypedData, input, options);

  /// Signs a native transaction without submitting it.
  Future<Object?> signTransaction(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.signTransaction, input, options);

  /// Signs native transactions without treating batch signing as broadcast.
  Future<Object?> signTransactions(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.signTransactions, input, options);

  /// Requests native signing and submission of a transaction.
  Future<Object?> signAndSendTransaction(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.signAndSendTransaction, input, options);

  /// Signs a native partially signed Bitcoin transaction with wallet options.
  Future<Object?> signPSBT(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.signPSBT, input, options);

  /// Signs a batch of native PSBT values when supported.
  Future<Object?> signPSBTs(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.signPSBTs, input, options);

  /// Signs chain-specific structured data, such as CIP-30 data.
  Future<Object?> signData(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.signData, input, options);

  /// Requests submission through the selected wallet.
  Future<Object?> sendTransaction(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.sendTransaction, input, options);

  /// Broadcasts a previously signed native transaction.
  Future<Object?> sendRawTransaction(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.sendRawTransaction, input, options);

  /// Sends a native-currency amount expressed in integer base units.
  Future<Object?> transfer(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.transfer, input, options);

  /// Submits a supported fungible token transfer.
  Future<Object?> transferToken(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.transferToken, input, options);

  /// Submits an ERC-721 or ERC-1155 compatible transfer, or native handler.
  Future<Object?> transferNFT(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.transferNFT, input, options);

  /// Fills declared transaction fields without signing or submitting.
  Future<Object?> prepareTransaction(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.prepareTransaction, input, options);

  /// Performs a read-only transaction simulation.
  Future<Object?> simulateTransaction(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.simulateTransaction, input, options);

  /// Estimates a transaction fee without submitting the transaction.
  Future<Object?> estimateTransactionFee(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.estimateTransactionFee, input, options);

  /// Polls for a receipt within explicit timeout and confirmation limits.
  Future<Object?> waitForTransaction(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.waitForTransaction, input, options);

  /// Calls a contract with raw or ABI-encoded calldata.
  Future<Object?> callContract(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.callContract, input, options);

  /// Calls a contract and decodes its ABI result when supplied.
  Future<Object?> readContract(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.readContract, input, options);

  /// Requests a wallet-authorized contract write.
  Future<Object?> writeContract(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.writeContract, input, options);

  /// Encodes and submits a supported contract transaction.
  Future<Object?> sendContractTransaction(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.sendContractTransaction, input, options);

  /// Combines bytecode and ABI constructor arguments for deployment.
  Future<Object?> deployContract(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.deployContract, input, options);

  /// Estimates gas or Core energy for an encoded contract call.
  Future<Object?> estimateContractGas(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.estimateContractGas, input, options);

  /// Encodes ABI calldata locally using the selected blockchain rules.
  Future<Object?> encodeContractCall(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.encodeContractCall, input, options);

  /// Decodes ABI return data locally using the selected blockchain rules.
  Future<Object?> decodeContractResult(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.decodeContractResult, input, options);

  /// Reads native contract logs for an explicit filter.
  Future<Object?> getContractEvents(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getContractEvents, input, options);

  /// Reads contract name, symbol and decimals without an asset indexer.
  Future<Object?> getTokenMetadata(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getTokenMetadata, input, options);

  /// Reads the amount an owner has approved for a spender.
  Future<Object?> getTokenAllowance(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.getTokenAllowance, input, options);

  /// Requests a native token allowance approval transaction.
  Future<Object?> approveToken(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.approveToken, input, options);

  /// Requests wallet tracking of a supplied asset when supported.
  Future<Object?> watchAsset(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.watchAsset, input, options);

  /// Requests native registration of token metadata when supported.
  Future<Object?> addToken(
    Object? input, {
    WalletCallOptions options = const WalletCallOptions(),
  }) => execute(WalletMethod.addToken, input, options);
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions.values) {
      subscription.cancel();
    }
    for (final adapter in _adapters.values) {
      adapter.dispose();
    }
    _subscriptions.clear();
    _adapters.clear();
    _selected.clear();
    _pendingConnections.clear();
    _active = null;
    _events.close();
  }
}

String? _accountAddress(Object? value) => value is String
    ? value
    : value is Map
    ? value['address'] as String?
    : null;
Object? _canonicalFingerprint(Object? value, [int depth = 0]) {
  if (depth > 32) {
    throw InvalidTransactionError('Native payload nesting limit.');
  }
  if (value is BigInt) return '${value}n';
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is List) {
    return value.map((v) => _canonicalFingerprint(v, depth + 1)).toList();
  }
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {
      for (final key in keys) key: _canonicalFingerprint(value[key], depth + 1),
    };
  }
  throw InvalidTransactionError('Opaque native payload.');
}

String _fingerprint(Object? input) {
  try {
    return jsonEncode(_canonicalFingerprint(input));
  } catch (_) {
    return 'native:${identityHashCode(input)}';
  }
}

bool _sameProviderAccount(String? a, String? b, Blockchain blockchain) {
  if (a == null || b == null) return false;
  if (blockchain == Blockchain.core) {
    return a
            .replaceFirst(RegExp(r'^0x', caseSensitive: false), '')
            .toLowerCase() ==
        b.replaceFirst(RegExp(r'^0x', caseSensitive: false), '').toLowerCase();
  }
  return blockchain == Blockchain.ethereum
      ? a.toLowerCase() == b.toLowerCase()
      : a == b;
}
