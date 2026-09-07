/// Wallet-side Connect authentication for dapps and optional Better Auth portals.
///
/// Resolve a full connect:// handoff with [ConnectClient], show its origin and
/// accounts, then call [ConnectRequest.approve] only after user confirmation.
/// The portal must verify wallet ownership before establishing a session.
library;

export 'src/protocol.dart';
export 'src/wallet.dart';
export 'src/links.dart';
export 'src/chains.dart';

export 'src/handoff.dart';
export 'src/bluetooth.dart';
