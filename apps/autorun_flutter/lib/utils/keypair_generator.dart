import 'package:bip39/bip39.dart' as bip39;
import 'package:uuid/uuid.dart';
import '../rust/native_bridge.dart' as rust;

import '../models/profile_keypair.dart';

class KeypairGenerator {
  const KeypairGenerator._();

  static final Uuid _uuid = const Uuid();

  static Future<ProfileKeypair> generate({
    required KeyAlgorithm algorithm,
    String? label,
    String? mnemonic,
    int? keypairCount,
  }) async {
    // Web keygen flows through the same RustBridgeLoader (which dispatches to
    // the pure-Dart Web impl for Ed25519 — R-2). secp256k1 is not yet
    // implemented on Web (clear UnsupportedError from native_bridge_web.dart).

    final String resolvedMnemonic = _resolveMnemonic(mnemonic);
    final String resolvedLabel = _resolveLabel(label, keypairCount);
    final DateTime now = DateTime.now().toUtc();

    final rust.RustBridgeLoader loader = const rust.RustBridgeLoader();
    final int algCode = algorithm == KeyAlgorithm.ed25519 ? 0 : 1;
    final rust.RustKeypairResult? r = loader.generateKeypair(
      alg: algCode,
      mnemonic: resolvedMnemonic,
    );

    if (r == null) {
      throw StateError(
        'Keypair generation failed for $algorithm. '
        'On native ensure libicp_core is loaded; on Web this indicates an '
        'internal error (Ed25519 should always succeed — R-2).',
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

  static String _resolveLabel(String? label, int? keypairCount) {
    if (label != null && label.trim().isNotEmpty) {
      return label.trim();
    }
    if (keypairCount != null) {
      return 'Keypair ${keypairCount + 1}';
    }
    return 'New keypair';
  }

  static String _resolveMnemonic(String? mnemonic) {
    if (mnemonic != null && mnemonic.trim().isNotEmpty) {
      return mnemonic.trim();
    }
    return bip39.generateMnemonic(strength: 256);
  }
}
