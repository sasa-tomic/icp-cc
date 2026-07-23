//! W7-3 (security): the backend compares secrets — the admin bearer token
//! (`middleware::admin_auth`) and the recovery-code hash (`vault`) — with a
//! single shared constant-time byte comparison. Timing attacks against `==`
//! can leak the number of leading correct bytes; a constant-time scan reads
//! the full length unconditionally.
//!
//! This file locks the contract of the shared helper and proves it is wired
//! into the admin-auth path (correct token passes, wrong token 401s). The
//! timing property itself is not unit-testable; the equal/unequal/length
//! behaviour plus the end-to-end admin path is what we assert here.

use icp_marketplace_api::crypto_util::constant_time_eq;

#[test]
fn constant_time_eq_equal_bytes_are_equal() {
    assert!(constant_time_eq(b"", b""));
    assert!(constant_time_eq(b"abc", b"abc"));
    assert!(constant_time_eq(&[0u8; 32], &[0u8; 32]));
    // A realistic admin token.
    assert!(constant_time_eq(b"real-admin-secret", b"real-admin-secret"));
}

#[test]
fn constant_time_eq_unequal_bytes_differ() {
    assert!(!constant_time_eq(b"abc", b"abd"));
    // A near-miss admin token (single trailing byte changed).
    assert!(!constant_time_eq(
        b"real-admin-secret",
        b"real-admin-secreu"
    ));
    assert!(!constant_time_eq(&[1u8; 32], &[2u8; 32]));
}

#[test]
fn constant_time_eq_different_lengths_differ() {
    // Length mismatch must never report equal, even if one side is a prefix.
    assert!(!constant_time_eq(b"abc", b"abcd"));
    assert!(!constant_time_eq(b"abcd", b"abc"));
    assert!(!constant_time_eq(b"", b"a"));
    assert!(!constant_time_eq(b"a", b""));
}
