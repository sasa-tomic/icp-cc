import 'dart:convert';

import 'package:bip32/bip32.dart' as bip32;
import 'package:bip39/bip39.dart' as bip39;

void main(List<String> args) {
  const mnemonic =
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';
  final seed = bip39.mnemonicToSeed(mnemonic);
  final root = bip32.BIP32.fromSeed(seed);
  final node = root.derivePath("m/44'/223'/0'/0/0");
  final priv = base64Encode(node.privateKey!);
  final pub = base64Encode(node.publicKey);
  print('private: $priv');
  print('public: $pub');
}
