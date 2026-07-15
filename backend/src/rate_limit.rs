//! A tiny in-memory sliding-window rate limiter.
//!
//! Used by the open `POST /recovery/verify` endpoint (W7-14) to throttle the
//! brute-force oracle: a locked-out user has no keypair by definition (that's
//! WHY they need recovery), so `verify` stays open — but after N failed codes
//! in a window it returns 429. The codes are already Argon2id-hashed so each
//! guess is expensive; this adds the missing per-caller throttle.
//!
//! In-memory (not DB-backed): a restart resets the counters, which is
//! acceptable for an online brute-force throttle (the Argon2id KDF remains the
//! primary bound). Process-local (sufficient for a single-node deployment).

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{SystemTime, UNIX_EPOCH};

/// A sliding-window failure counter. Thread-safe via a single `Mutex`. Evicts
/// expired entries opportunistically on each `check`.
pub struct SlidingWindowRateLimiter {
    failures: Mutex<HashMap<String, Vec<i64>>>,
    max: usize,
    window_secs: i64,
}

impl SlidingWindowRateLimiter {
    pub fn new(max: usize, window_secs: i64) -> Self {
        Self {
            failures: Mutex::new(HashMap::new()),
            max,
            window_secs,
        }
    }

    fn now() -> i64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or(0)
    }

    /// Returns `true` if the caller is BELOW the limit (allowed to proceed),
    /// `false` if they are rate-limited (≥ `max` failures in the window).
    pub fn is_allowed(&self, key: &str) -> bool {
        let now = Self::now();
        let cutoff = now - self.window_secs;
        let mut map = self.failures.lock().expect("rate-limiter mutex poisoned");
        let entry = map.entry(key.to_string()).or_default();
        entry.retain(|t| *t > cutoff);
        entry.len() < self.max
    }

    /// Records a failure for `key` (appends a timestamp).
    pub fn record_failure(&self, key: &str) {
        let now = Self::now();
        let cutoff = now - self.window_secs;
        let mut map = self.failures.lock().expect("rate-limiter mutex poisoned");
        let entry = map.entry(key.to_string()).or_default();
        entry.retain(|t| *t > cutoff);
        entry.push(now);
    }

    /// Clears the failure history for `key` (called on a successful verify so a
    /// user who eventually types the right code isn't left near the limit).
    pub fn reset(&self, key: &str) {
        let mut map = self.failures.lock().expect("rate-limiter mutex poisoned");
        map.remove(key);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_until_limit_then_blocks() {
        let limiter = SlidingWindowRateLimiter::new(3, 900);
        let key = "acct-x@1.2.3.4";
        assert!(limiter.is_allowed(key), "0 failures → allowed");
        limiter.record_failure(key);
        assert!(limiter.is_allowed(key), "1 failure → allowed");
        limiter.record_failure(key);
        assert!(limiter.is_allowed(key), "2 failures → allowed");
        limiter.record_failure(key);
        assert!(
            !limiter.is_allowed(key),
            "3 failures → rate-limited (≥ max)"
        );
    }

    #[test]
    fn reset_clears_history() {
        let limiter = SlidingWindowRateLimiter::new(2, 900);
        let key = "acct-y@1.2.3.4";
        limiter.record_failure(key);
        limiter.record_failure(key);
        assert!(!limiter.is_allowed(key));
        limiter.reset(key);
        assert!(limiter.is_allowed(key), "reset must clear the history");
    }

    #[test]
    fn distinct_keys_are_independent() {
        let limiter = SlidingWindowRateLimiter::new(1, 900);
        limiter.record_failure("a@1.1.1.1");
        assert!(!limiter.is_allowed("a@1.1.1.1"));
        assert!(
            limiter.is_allowed("b@2.2.2.2"),
            "a different caller must not inherit the limit"
        );
    }
}
