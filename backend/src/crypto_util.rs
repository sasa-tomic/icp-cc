//! Shared cryptographic comparison helper — single source of truth.
//!
//! Constant-time byte comparison used by every secret comparison in the
//! backend:
//! - [`crate::middleware::admin_auth`] — admin bearer-token check
//! - [`crate::vault`] — recovery-code hash verification
//!
//! A `==` compare short-circuits on the first differing byte, leaking how many
//! leading bytes of a guessed secret are correct via timing. This helper
//! ALWAYS consumes the full length of both slices (no early return) so the
//! elapsed time is independent of where (or whether) they differ. Length
//! differences fold into the same accumulator + a final length check so as not
//! to leak length via a timing distinction either.

/// Constant-time byte comparison. Returns `true` iff `a` and `b` are the same
/// length and byte-for-byte equal. Both slices are fully scanned on every call.
pub fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    let mut acc: u8 = 0;
    let n = a.len().max(b.len());
    for i in 0..n {
        let x = a.get(i).copied().unwrap_or(0);
        let y = b.get(i).copied().unwrap_or(0);
        acc |= x ^ y;
    }
    // The length guard ensures a length mismatch is never masked by a
    // coincidentally-zero accumulator (e.g. one side empty vs a zeroed one).
    acc == 0 && a.len() == b.len()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn equal_bytes_are_equal() {
        assert!(constant_time_eq(b"", b""));
        assert!(constant_time_eq(b"abc", b"abc"));
        assert!(constant_time_eq(&[0u8; 32], &[0u8; 32]));
    }

    #[test]
    fn unequal_bytes_differ() {
        assert!(!constant_time_eq(b"abc", b"abd"));
        assert!(!constant_time_eq(&[1u8; 32], &[2u8; 32]));
    }

    #[test]
    fn different_lengths_differ() {
        assert!(!constant_time_eq(b"abc", b"abcd"));
        assert!(!constant_time_eq(b"abcd", b"abc"));
        assert!(!constant_time_eq(b"", b"a"));
        assert!(!constant_time_eq(b"a", b""));
    }
}
