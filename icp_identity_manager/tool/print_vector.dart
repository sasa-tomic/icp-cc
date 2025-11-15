import 'dart:convert';

import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';

Future<void> main() async {
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';
  final entropy = bip39.mnemonicToEntropy(mnemonic);
  final seedBytes = bip39.mnemonicToSeed(mnemonic).sublist(0, 32);
  final edKeyPair = await Ed25519().newKeyPairFromSeed(seedBytes);
  final edPublic = await edKeyPair.extractPublicKey();
  final edPrivate = await edKeyPair.extractPrivateKeyBytes();
  // ignore: avoid_print
  print('mnemonic: $mnemonic');
  // ignore: avoid_print
  print('entropy (hex): $entropy');
  // ignore: avoid_print
  print(
    'seed (hex): ${seedBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}',
  );
  // ignore: avoid_print
  print('ed25519 public (base64): ${base64Encode(edPublic.bytes)}');
  // ignore: avoid_print
  print('ed25519 private (base64): ${base64Encode(edPrivate)}');
}
