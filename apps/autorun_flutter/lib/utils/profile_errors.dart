/// Typed exceptions for the profile-backup import path.
//
// Replaces the bare `StateError` / `FormatException` previously thrown from
// `ProfileRepository.importProfileBackup` (and the `EncryptedExport` crypto
// layer it calls), so the import UI can branch on TYPE instead of guessing
// the cause from an English substring (`e.message.contains('already
// exists')`, `…('Decryption failed')`). See TD-4.
//
// `EncryptedExport` is a generic crypto utility shared with the per-keypair
// export path, so it keeps its `StateError`/`FormatException` contract; the
// translation into these profile-domain types happens at the
// `ProfileRepository.importProfileBackup` boundary (the origin of a
// profile-backup failure).
library;

/// The profile id encoded in the backup already exists in the local store.
///
/// Maps to dialog copy: *"Profile already exists. Delete it first or use a
/// different backup."*
class ProfileAlreadyExistsException implements Exception {
  ProfileAlreadyExistsException(this.profileId);

  final String profileId;

  @override
  String toString() => 'Profile with ID $profileId already exists';
}

/// The backup could not be decrypted — wrong password or corrupted ciphertext.
///
/// Maps to dialog copy: *"Invalid password or corrupted backup."*
class BackupDecryptionException implements Exception {
  BackupDecryptionException([
    this.message = 'wrong password or corrupted data',
  ]);

  final String message;

  @override
  String toString() => 'Decryption failed: $message';
}

/// The backup blob is structurally invalid: bad JSON envelope, wrong envelope
/// version, unsupported algorithm, wrong backup type/version, or the decrypted
/// payload is not valid JSON.
///
/// Maps to dialog copy: *"Invalid backup format: {message}"*.
class InvalidBackupFormatException implements Exception {
  InvalidBackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}
