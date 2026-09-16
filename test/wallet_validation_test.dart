import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_connect/flutter_connect.dart';

void main() {
  final cases =
      jsonDecode(
            File('test/fixtures/wallet-validation.json').readAsStringSync(),
          )
          as List;
  for (final c in cases) {
    test('address: ${c['name']}', () {
      WalletValidationStatus status;
      try {
        final account = WalletIdentity.fromJson(c['account']);
        status = validateWalletAccount(account).status;
        expect(isValidWalletAccount(account), c['status'] == 'valid');
      } on ConnectException {
        status = WalletValidationStatus.invalid;
      }
      expect(status.name, c['status']);
    });
  }
  test(
    'wrapper rejects bad checksum before host policy and retains host rejection',
    () async {
      var called = 0;
      final adapter = withWalletValidation(
        OperationChainAdapter(
          capabilities: [],
          handlers: {},
          validateAccount: (_) {
            called++;
            return true;
          },
          validateOperation: (_) {},
        ),
      );
      WalletIdentity identity(String name) => WalletIdentity.fromJson(
        cases.firstWhere((c) => c['name'] == name)['account'],
      );
      expect(
        await adapter.validateAccount(identity('EVM bad mixed checksum')),
        isFalse,
      );
      expect(called, 0);
      expect(await adapter.validateAccount(identity('ethereum-siwe')), isTrue);
      expect(called, 1);
      expect(await adapter.validateAccount(identity('Monero')), isTrue);
      expect(called, 2);
      final denied = withWalletValidation(
        OperationChainAdapter(
          capabilities: [],
          handlers: {},
          validateAccount: (_) => false,
          validateOperation: (_) {},
        ),
      );
      expect(await denied.validateAccount(identity('ethereum-siwe')), isFalse);
    },
  );
  test('dispatcher rejects bad checksum before approval and handler', () async {
    final account = WalletIdentity.fromJson(
      cases.firstWhere((c) => c['name'] == 'EVM bad mixed checksum')['account'],
    );
    var approved = 0, executed = 0;
    final dispatcher = OperationDispatcher(
      adapters: [
        withWalletValidation(
          OperationChainAdapter(
            capabilities: [
              OperationCapability(account.namespace, account.reference, [
                OperationMethods.getBalance,
              ]),
            ],
            handlers: {
              OperationMethods.getBalance: (r, c) {
                executed++;
                return '0';
              },
            },
            validateAccount: (_) => true,
            validateOperation: (_) {},
          ),
        ),
      ],
      approve: (r, c, p) {
        approved++;
        return true;
      },
    );
    final response = await dispatcher.dispatch(
      ConnectOperation(
        operation: OperationMethods.getBalance,
        chain: OperationChain(account.namespace, account.reference),
        account: account,
        params: {},
      ),
      origin: 'https://example.com',
    );
    expect(response.error!.code, 'UNSUPPORTED_ACCOUNT');
    expect(approved, 0);
    expect(executed, 0);
  });
}
