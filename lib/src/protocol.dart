import 'dart:convert';
import 'dart:typed_data';

const coseEd448 = -53;
const coseEd25519 = -19;

class ConnectException implements Exception {
  final String code;
  const ConnectException(this.code);
  @override
  String toString() => 'ConnectException($code)';
}

Never fail(String code) => throw ConnectException(code);
bool matches(String pattern, String value) =>
    RegExp('^(?:$pattern)\$').firstMatch(value)?.end == value.length;
String atom(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 128 ||
      !matches(r'[a-zA-Z0-9._-]+', value)) {
    fail('malformedResponse');
  }
  return value;
}

String identifier(Object? value) {
  if (value is! String || !matches(r'[a-f0-9]{64}', value)) {
    fail('invalidRequest');
  }
  return value;
}

Map<String, dynamic> object(Object? value, List<String> keys) {
  if (value is! Map<String, dynamic> ||
      value.length != keys.length ||
      !keys.every(value.containsKey)) {
    fail('malformedResponse');
  }
  return value;
}

bool validDomain(String domain) =>
    domain.length <= 253 &&
    domain.contains('.') &&
    !matches(r'\d+(\.\d+){3}', domain) &&
    domain
        .split('.')
        .every((l) => matches(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', l));
String validateOrigin(String origin) {
  if (!origin.startsWith('https://') || !validDomain(origin.substring(8))) {
    fail('invalidUri');
  }
  return origin;
}

class ConnectTarget {
  final String origin;
  final String requestId;
  ConnectTarget(String origin, String requestId)
    : origin = validateOrigin(origin),
      requestId = identifier(requestId);
  String get connectUri =>
      'connect://${origin.substring(8)}/connect/v1/$requestId';
}

abstract interface class ConnectTransport {
  ConnectTarget parse(String input);
}

class UriTransport implements ConnectTransport {
  final Set<String> schemes;
  UriTransport({Set<String> schemes = const {'connect', 'https'}})
    : schemes = Set.unmodifiable(schemes);
  @override
  ConnectTarget parse(String input) {
    if (input.length > 512) fail('invalidUri');
    final m = RegExp(
      r'^([a-z][a-z0-9+.-]*):\/\/([^/]+)\/connect\/v1\/([a-f0-9]{64})$',
    ).firstMatch(input);
    if (m == null ||
        m.end != input.length ||
        !schemes.contains(m[1]) ||
        !validDomain(m[2]!)) {
      fail('invalidUri');
    }
    return ConnectTarget('https://${m[2]}', m[3]!);
  }
}

class WalletIdentity {
  final String namespace, reference, address;
  WalletIdentity({
    required String namespace,
    required String reference,
    required String address,
  }) : namespace = atom(namespace),
       reference = atom(reference),
       address = atom(address);
  factory WalletIdentity.fromJson(Object? value) {
    final j = object(value, ['namespace', 'reference', 'address']);
    return WalletIdentity(
      namespace: atom(j['namespace']),
      reference: atom(j['reference']),
      address: atom(j['address']),
    );
  }
  Map<String, dynamic> toJson() => {
    'namespace': namespace,
    'reference': reference,
    'address': address,
  };
}

class SigningSelection {
  final WalletIdentity account;
  final String profile;
  final int? alg;
  SigningSelection({
    required this.account,
    required String profile,
    required this.alg,
  }) : profile = atom(profile);
}

class SigningRequirement {
  final String namespace, reference, profile;
  final int? alg;
  SigningRequirement(this.namespace, this.reference, this.profile, this.alg);
  factory SigningRequirement.fromJson(Object? value) {
    final j = object(value, ['namespace', 'reference', 'profile', 'alg']);
    if (j['alg'] != null && j['alg'] is! int) fail('invalidChallenge');
    return SigningRequirement(
      atom(j['namespace']),
      atom(j['reference']),
      atom(j['profile']),
      j['alg'] as int?,
    );
  }
  bool accepts(SigningSelection s) =>
      namespace == s.account.namespace &&
      reference == s.account.reference &&
      profile == s.profile &&
      alg == s.alg;
  Map<String, dynamic> toJson() => {
    'namespace': namespace,
    'reference': reference,
    'profile': profile,
    'alg': alg,
  };
}

class ConnectChallenge extends ConnectTarget {
  final String nonce, domain, issuedAt, expiresAt;
  final List<SigningRequirement> requirements;
  ConnectChallenge._(
    super.origin,
    super.requestId,
    this.nonce,
    this.domain,
    this.issuedAt,
    this.expiresAt,
    List<SigningRequirement> requirements,
  ) : requirements = List.unmodifiable(requirements);
  factory ConnectChallenge.fromJson(
    Object? value, {
    ConnectTarget? target,
    DateTime? now,
  }) {
    final j = object(value, [
      'version',
      'requestId',
      'nonce',
      'domain',
      'origin',
      'issuedAt',
      'expiresAt',
      'requirements',
    ]);
    if (j['version'] != 1 || j['version'] is! int) {
      fail('unsupportedProtocolVersion');
    }
    if (j['origin'] is! String ||
        j['domain'] is! String ||
        j['issuedAt'] is! String ||
        j['expiresAt'] is! String ||
        j['requirements'] is! List) {
      fail('invalidChallenge');
    }
    final r = j['requirements'] as List;
    if (r.isEmpty || r.length > 32) fail('invalidChallenge');
    final c = ConnectChallenge._(
      j['origin'],
      identifier(j['requestId']),
      identifier(j['nonce']),
      j['domain'],
      j['issuedAt'],
      j['expiresAt'],
      r.map(SigningRequirement.fromJson).toList(),
    );
    if (c.domain != c.origin.substring(8) ||
        (target != null &&
            (target.origin != c.origin || target.requestId != c.requestId))) {
      fail('domainMismatch');
    }
    c.validateTime(now ?? DateTime.now());
    return c;
  }
  void validateTime(DateTime now) {
    DateTime timestamp(String input) {
      if (!matches(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z', input)) {
        fail('invalidChallenge');
      }
      final d = DateTime.tryParse(input);
      if (d == null || d.toUtc().toIso8601String() != input) {
        fail('invalidChallenge');
      }
      return d;
    }

    final issued = timestamp(issuedAt), expires = timestamp(expiresAt);
    final ttl = expires.difference(issued).inMilliseconds;
    if (ttl <= 0 ||
        ttl > 300000 ||
        issued.isAfter(now.add(const Duration(seconds: 30)))) {
      fail('invalidChallenge');
    }
    if (!expires.isAfter(now)) fail('expiredRequest');
  }

  bool accepts(SigningSelection s) => requirements.any((r) => r.accepts(s));
  Map<String, dynamic> toJson() => {
    'version': 1,
    'requestId': requestId,
    'nonce': nonce,
    'domain': domain,
    'origin': origin,
    'issuedAt': issuedAt,
    'expiresAt': expiresAt,
    'requirements': requirements.map((r) => r.toJson()).toList(),
  };
}

String canonicalMessage(ConnectChallenge c, SigningSelection s) {
  if (!c.accepts(s)) fail('unsupportedProfile');
  final a = s.account;
  if (s.profile == 'ethereum-siwe') {
    if (!matches(r'[1-9][0-9]{0,14}', a.reference) ||
        !matches(r'0x[0-9a-fA-F]{40}', a.address)) {
      fail('invalidAccount');
    }
    return '${c.domain} wants you to sign in with your Ethereum account:\n${a.address}\n\nApprove this Connect sign-in request.\n\nURI: ${c.origin}\nVersion: 1\nChain ID: ${a.reference}\nNonce: ${c.nonce}\nIssued At: ${c.issuedAt}\nExpiration Time: ${c.expiresAt}\nRequest ID: ${c.requestId}\nResources:\n- urn:connect:version:1\n- urn:connect:profile:${s.profile}\n- urn:connect:alg:${s.alg ?? 'none'}\n- urn:connect:account:${a.namespace}:${a.reference}:${a.address}';
  }
  return [
    'Connect Authentication',
    'Version: 1',
    'Domain: ${c.domain}',
    'URI: ${c.origin}',
    'Account: ${a.namespace}:${a.reference}:${a.address}',
    'Profile: ${s.profile}',
    'Algorithm: ${s.alg ?? 'none'}',
    'Nonce: ${c.nonce}',
    'Request ID: ${c.requestId}',
    'Issued At: ${c.issuedAt}',
    'Expiration Time: ${c.expiresAt}',
  ].join('\n');
}

Uint8List canonicalBytes(ConnectChallenge c, SigningSelection s) =>
    Uint8List.fromList(utf8.encode(canonicalMessage(c, s)));
