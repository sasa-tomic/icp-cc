import 'package:bip39/bip39.dart' as bip39;
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../rust/native_bridge.dart' as rust;

import '../models/profile_keypair.dart';

class IdentityGenerator {
  const IdentityGenerator._();

  static final Uuid _uuid = const Uuid();

  static Future<ProfileKeypair> generate({
    required KeyAlgorithm algorithm,
    String? label,
    String? mnemonic,
    int? identityCount,
  }) async {
    if (kIsWeb) {
      throw UnsupportedError('IdentityGenerator does not support web.');
    }

    final String resolvedMnemonic = _resolveMnemonic(mnemonic);
    final String resolvedLabel = _resolveLabel(label, identityCount);
    final DateTime now = DateTime.now().toUtc();

    final rust.RustBridgeLoader loader = const rust.RustBridgeLoader();
    final int algCode = algorithm == KeyAlgorithm.ed25519 ? 0 : 1;
    final rust.RustIdentityResult? r = loader.generateIdentity(
      alg: algCode,
      mnemonic: resolvedMnemonic,
    );

    if (r == null) {
      throw StateError(
        'Rust FFI failed to generate identity for $algorithm. '
        'Ensure native library is loaded.',
      );
    }

    return ProfileKeypair(
      id: _uuid.v4(),
      label: resolvedLabel,
      algorithm: algorithm,
      publicKey: r.publicKeyB64,
      privateKey: r.privateKeyB64,
      mnemonic: resolvedMnemonic,
      createdAt: now,
      principal: r.principalText,
    );
  }

  static String _resolveLabel(String? label, int? identityCount) {
    if (label != null && label.trim().isNotEmpty) {
      return label.trim();
    }
    if (identityCount != null) {
      return 'Identity ${identityCount + 1}';
    }
    return 'New identity';
  }

  static String _resolveMnemonic(String? mnemonic) {
    if (mnemonic != null && mnemonic.trim().isNotEmpty) {
      return mnemonic.trim();
    }
    return bip39.generateMnemonic(strength: 256);
  }
}
