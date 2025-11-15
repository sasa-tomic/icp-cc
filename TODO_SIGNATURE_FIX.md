# TODO: Fix Signature Verification to Use Real ICP Signatures

## Problem
Currently, 13 Flutter tests are failing with 401 authentication errors because:
1. Dart tests use `TestSignatureUtils.generateTestSignature()` - a fake hash-based signature
2. Rust API has placeholder signature verification that always rejects non-"test-auth-token" signatures
3. Neither side implements REAL cryptographic signature verification as ICP uses

## Goal
Implement proper ICP-compatible signature verification:
- **Ed25519**: Primary signature algorithm (MUST implement)
- **secp256k1**: Secondary algorithm (TODO for later)

## Implementation Plan

### Phase 1: Ed25519 Support (Current Focus)
1. **Dart Side - Test Helpers**
   - Create a deterministic Ed25519 test identity (fixed mnemonic for reproducibility)
   - Update `testable_script_repository.dart` to use real Ed25519 signatures when `AuthenticationMethod.realSignature`
   - Use `ScriptSignatureService.signScriptUpload/Update/Deletion()` with the test identity
   - Include `author_principal` and `author_public_key` in requests

2. **Rust Side - API Verification**
   - Implement `verify_signature_payload()` function that:
     - Reconstructs canonical JSON payload from request fields
     - Extracts public key from request
     - Verifies Ed25519 signature
   - Update `create_script`, `update_script`, `delete_script`, `publish_script` handlers
   - Keep "test-auth-token" as a bypass for non-signature tests

3. **Remove Fake Signatures**
   - Delete or deprecate `TestSignatureUtils` (fake hash-based signatures)
   - Update all test helpers to use real signatures

### Phase 2: secp256k1 Support (Future)
- Add `k256` or `secp256k1` crate to Rust
- Implement ECDSA signature verification
- Update Dart to use proper secp256k1 ECDSA (not HMAC!)
- Add tests for secp256k1

## Files to Modify

### Dart
- `apps/autorun_flutter/lib/services/script_signature_service.dart` - already has Ed25519 signing
- `apps/autorun_flutter/test/test_helpers/testable_script_repository.dart` - update to use real signatures
- `apps/autorun_flutter/test/test_helpers/test_signature_utils.dart` - DELETE or mark deprecated

### Rust
- `poem-backend/Cargo.toml` - has ed25519-dalek dependency ✓
- `poem-backend/src/main.rs` - implement verification logic

## Current Status
- [x] Identified issue
- [x] Added ed25519-dalek dependency
- [x] Removed HMAC (was incorrect approach)
- [ ] Create test Ed25519 identity in Dart
- [ ] Update Dart test helpers to sign with Ed25519
- [ ] Implement Rust signature verification
- [ ] All tests passing

## Notes
- Test identity should use a FIXED mnemonic for reproducibility
- Signature verification must match the exact payload structure used in signing
- Principal must be derived from public key correctly
