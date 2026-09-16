import 'dart:async';
import 'package:flutter_connect/flutter_connect.dart';

/// Implement these callbacks with the wallet's SDKs and approval UI.
/// validateOperation must validate the complete native payload for the chain.
abstract interface class OperationsHost {
  WalletAccountProvider get accounts;
  FutureOr<bool> approve(
    ConnectOperation request,
    OperationContext context,
    Object? preparedMessage,
  );
  FutureOr<bool> validateAccount(WalletIdentity account);
  FutureOr<void> validateOperation(ConnectOperation request);
  FutureOr<Object?> signEvm(ConnectOperation request, OperationContext context);
  FutureOr<Object?> signPsbt(
    ConnectOperation request,
    OperationContext context,
  );
  FutureOr<Object?> signSolana(
    ConnectOperation request,
    OperationContext context,
  );
  FutureOr<Object?> signCore(
    ConnectOperation request,
    OperationContext context,
  );
  FutureOr<Object?> getBalance(
    ConnectOperation request,
    OperationContext context,
  );
}

OperationDispatcher createExampleOperations(OperationsHost host) {
  final definitions = <(ConnectChain, String, OperationHandler)>[
    (ConnectChains.ethereum, OperationMethods.signTransaction, host.signEvm),
    (ConnectChains.bitcoin, OperationMethods.signPsbt, host.signPsbt),
    (ConnectChains.solana, OperationMethods.signTransaction, host.signSolana),
    (ConnectChains.core, OperationMethods.signTransaction, host.signCore),
  ];
  return OperationDispatcher(
    accounts: host.accounts,
    approve: host.approve,
    adapters: definitions.map((entry) {
      final chain = OperationChain.fromChain(entry.$1);
      return withWalletValidation(
        OperationChainAdapter(
          capabilities: [
            OperationCapability(chain.namespace, chain.reference, [
              entry.$2,
              OperationMethods.getAccounts,
              OperationMethods.getBalance,
            ]),
          ],
          validateAccount: host.validateAccount,
          validateOperation: host.validateOperation,
          handlers: {
            entry.$2: entry.$3,
            OperationMethods.getAccounts: operationAccounts(
              host.accounts,
              chain,
            ),
            OperationMethods.getBalance: host.getBalance,
          },
        ),
      );
    }),
  );
}

/// Supply real native transactions; these payload formats are deliberately different.
List<ConnectOperation> exampleRequests({
  required WalletIdentity evm,
  required WalletIdentity bitcoin,
  required WalletIdentity solana,
  required WalletIdentity core,
  required Map<String, Object?> evmTransaction,
  required String psbt,
  required String solanaTransaction,
  required Map<String, Object?> coreTransaction,
}) {
  ConnectOperation make(
    String operation,
    WalletIdentity account,
    Map<String, Object?> params,
  ) => ConnectOperation(
    operation: operation,
    chain: OperationChain(account.namespace, account.reference),
    account: account,
    params: params,
    metadata: {'application': 'Example dapp'},
  );
  return [
    make(OperationMethods.signTransaction, evm, {
      'transaction': evmTransaction,
    }),
    make(OperationMethods.signPsbt, bitcoin, {
      'psbt': psbt,
      'encoding': 'base64',
    }),
    make(OperationMethods.signTransaction, solana, {
      'transaction': solanaTransaction,
      'encoding': 'base64',
    }),
    make(OperationMethods.signTransaction, core, {
      'transaction': coreTransaction,
    }),
    make(OperationMethods.getBalance, evm, {'address': evm.address}),
  ];
}
// Dapp: requestOperation(transport, request).
// Wallet: dispatcher.dispatchJson(receivedJson, origin: authenticatedTransportOrigin).
// Encrypted channels wrap dispatch with OperationCipher.openRequest / sealResponse.
