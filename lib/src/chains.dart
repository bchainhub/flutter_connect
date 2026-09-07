import 'dart:typed_data';
import 'wallet.dart';
import 'protocol.dart';

/// Canonical UTF-8 bytes must be passed unchanged to [signingMethod].
/// Encodings describe the returned proof fields.
class ConnectChain {
  final String name,
      namespace,
      reference,
      profile,
      signingMethod,
      signatureEncoding;
  final String? publicKeyEncoding;
  final int? alg;
  const ConnectChain({
    required this.name,
    required this.namespace,
    required this.reference,
    required this.profile,
    required this.alg,
    required this.signingMethod,
    required this.signatureEncoding,
    this.publicKeyEncoding,
  });
  factory ConnectChain.evm(String name, int chainId) {
    if (chainId <= 0 || chainId > 999999999999999) fail('invalidChain');
    return ConnectChain(
      name: name,
      namespace: 'eip155',
      reference: '$chainId',
      profile: 'ethereum-siwe',
      alg: null,
      signingMethod: 'personal_sign',
      signatureEncoding: 'hex0x',
    );
  }
  SigningRequirement get requirement =>
      SigningRequirement(namespace, reference, profile, alg);
  SigningSelection account(String address) => SigningSelection(
    account: WalletIdentity(
      namespace: namespace,
      reference: reference,
      address: address,
    ),
    profile: profile,
    alg: alg,
  );
}

abstract final class ConnectChains {
  static const core = ConnectChain(
    name: 'Core Blockchain',
    namespace: 'core',
    reference: '1',
    profile: 'xcb-ed448',
    alg: -53,
    signingMethod: 'ed448',
    signatureEncoding: 'hex',
    publicKeyEncoding: 'hex',
  );
  static const ethereum = ConnectChain(
    name: 'Ethereum',
    namespace: 'eip155',
    reference: '1',
    profile: 'ethereum-siwe',
    alg: null,
    signingMethod: 'personal_sign',
    signatureEncoding: 'hex0x',
  );
  static const polygon = ConnectChain(
    name: 'Polygon',
    namespace: 'eip155',
    reference: '137',
    profile: 'ethereum-siwe',
    alg: null,
    signingMethod: 'personal_sign',
    signatureEncoding: 'hex0x',
  );
  static const base = ConnectChain(
    name: 'Base',
    namespace: 'eip155',
    reference: '8453',
    profile: 'ethereum-siwe',
    alg: null,
    signingMethod: 'personal_sign',
    signatureEncoding: 'hex0x',
  );
  static const bnb = ConnectChain(
    name: 'BNB Smart Chain',
    namespace: 'eip155',
    reference: '56',
    profile: 'ethereum-siwe',
    alg: null,
    signingMethod: 'personal_sign',
    signatureEncoding: 'hex0x',
  );
  static const bitcoin = ConnectChain(
    name: 'Bitcoin',
    namespace: 'bip122',
    reference: '000000000019d6689c085ae165831e93',
    profile: 'bitcoin-bip322-p2wpkh',
    alg: null,
    signingMethod: 'bip322-simple',
    signatureEncoding: 'base64',
  );
  static const solana = ConnectChain(
    name: 'Solana',
    namespace: 'solana',
    reference: '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp',
    profile: 'solana-ed25519',
    alg: -19,
    signingMethod: 'signMessage',
    signatureEncoding: 'hex',
  );
  static const tron = ConnectChain(
    name: 'TRON',
    namespace: 'tron',
    reference: '728126428',
    profile: 'tron-signmessage-v2',
    alg: null,
    signingMethod: 'signMessageV2',
    signatureEncoding: 'hex0x',
  );
  static const monero = ConnectChain(
    name: 'Monero',
    namespace: 'monero',
    reference: '418015bb9ae982a1975da7d79277c270',
    profile: 'monero-spend-v2',
    alg: null,
    signingMethod: 'sign-spend',
    signatureEncoding: 'sigv2',
  );
  static const stellar = ConnectChain(
    name: 'Stellar',
    namespace: 'stellar',
    reference: 'pubnet',
    profile: 'stellar-sep53',
    alg: -19,
    signingMethod: 'sep53',
    signatureEncoding: 'hex',
  );
  static const litecoin = ConnectChain(
    name: 'Litecoin',
    namespace: 'bip122',
    reference: '12a765e31ffd4059bada1e25190f6e98',
    profile: 'litecoin-signmessage',
    alg: null,
    signingMethod: 'signmessage',
    signatureEncoding: 'base64',
  );
  static const ripple = ConnectChain(
    name: 'XRP Ledger',
    namespace: 'xrpl',
    reference: '0',
    profile: 'xrpl-secp256k1',
    alg: null,
    signingMethod: 'sign',
    signatureEncoding: 'hex',
    publicKeyEncoding: 'hex',
  );
  static const zcash = ConnectChain(
    name: 'Zcash',
    namespace: 'bip122',
    reference: '00040fe8ec8471911baa1db1266ea15d',
    profile: 'zcash-signmessage',
    alg: null,
    signingMethod: 'signmessage',
    signatureEncoding: 'base64',
  );
  static const cardano = ConnectChain(
    name: 'Cardano',
    namespace: 'cip34',
    reference: '1-764824073',
    profile: 'cardano-cip8',
    alg: -19,
    signingMethod: 'signData',
    signatureEncoding: 'cose-hex',
    publicKeyEncoding: 'cose-hex',
  );
  static const bitcoinLegacy = ConnectChain(
    name: 'Bitcoin (legacy P2PKH)',
    namespace: 'bip122',
    reference: '000000000019d6689c085ae165831e93',
    profile: 'bitcoin-signmessage',
    alg: null,
    signingMethod: 'signmessage',
    signatureEncoding: 'base64',
  );
  static const rippleEd25519 = ConnectChain(
    name: 'XRP Ledger (Ed25519)',
    namespace: 'xrpl',
    reference: '0',
    profile: 'xrpl-ed25519',
    alg: -19,
    signingMethod: 'sign',
    signatureEncoding: 'hex',
    publicKeyEncoding: 'hex',
  );
  static const all = [
    core,
    ethereum,
    polygon,
    base,
    bnb,
    bitcoin,
    solana,
    tron,
    monero,
    stellar,
    litecoin,
    ripple,
    zcash,
    cardano,
    bitcoinLegacy,
    rippleEd25519,
  ];
}

List<SigningRequirement> requirementsFor(Iterable<ConnectChain> chains) {
  final result = <String, SigningRequirement>{};
  for (final chain in chains) {
    final r = chain.requirement;
    result['${r.namespace}:${r.reference}:${r.profile}:${r.alg}'] = r;
  }
  return List.unmodifiable(result.values);
}

/// Connect adapter around an existing wallet's message-signing operation.
class ChainWalletAccount implements WalletAccount {
  @override
  final SigningSelection selection;
  final Future<WalletSignature> Function(Uint8List) _sign;
  ChainWalletAccount({
    required ConnectChain chain,
    required String address,
    required Future<WalletSignature> Function(Uint8List) sign,
  }) : selection = chain.account(address),
       _sign = sign;
  @override
  Future<WalletSignature> sign(Uint8List canonicalPayload) =>
      _sign(canonicalPayload);
}
