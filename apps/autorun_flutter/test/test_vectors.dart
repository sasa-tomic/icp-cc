// Shared test vectors used across Dart tests

// BIP-39 mnemonic used for deterministic keypair generation in tests
const String kTestMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon art';

// Expected keys and principals for ed25519
const String kEd25519PrivateKeyB64 =
    'QIsoXBI4NgBPS4hCyJMkwfATgkUMDUOa80W6f8Saz3A=';
const String kEd25519PublicKeyB64 =
    'HeNS5EzTM2clk/IzSnMOGAqvKQ3omqFtSA3llONOKWE=';
const String kEd25519PrincipalText =
    'yhnve-5y5qy-svqjc-aiobw-3a53m-n2gzt-xlrvn-s7kld-r5xid-td2ef-iae';

// Expected keys and principals for secp256k1
const String kSecp256k1PrivateKeyB64 =
    'Yb+9dY8vXeoLiLMSqhpHbE4MhT2HkGRk0Ai8NkBcD/I=';
const String kSecp256k1PublicKeyB64 =
    'BBz+IZWfHzq8STHpP6u3hU/DOJS6Fy5m3ewbQautk0Vd3u79WEhh0/0gvh886bxxFK9et89Fi2sBc4LDysmVe4g=';
const String kSecp256k1PrincipalText =
    'm7bn6-s5er4-xouui-ymkqf-azncv-qfche-3qghk-2fvpm-atfyh-ozg2w-iqe';
