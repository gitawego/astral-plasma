//! The broker: what a hosted app may ask the shell to do.
//!
//! An app in the sandbox has one controlled way out — a Unix socket — and this module
//! decides every request that arrives on it. Three rules, and nothing else:
//!
//! 1. **A method has one required permission.** The catalog is closed: an unknown method
//!    is `unsupported`, never forwarded.
//! 2. **The permission must have been granted** at install time (registry), not merely
//!    declared in the manifest. Declaring is asking; granting is consent.
//! 3. **Every call is rate limited and audited**, granted or denied: an audit trail that
//!    only records successes cannot answer "what did this app try to do?".
//!
//! Pure functions over plain data, so the whole policy is testable without a socket.

use std::collections::BTreeSet;

/// `method -> permission required`. Closed on purpose: adding a method means adding it
/// here, where its permission is reviewed.
pub const METHODS: [(&str, &str); 7] = [
    ("session.windows", "windows.read"),
    ("session.activate", "windows.control"),
    ("session.close", "windows.control"),
    ("workspaces.list", "workspaces.read"),
    ("workspaces.switch", "workspaces.control"),
    ("media.state", "media.read"),
    ("notifications.post", "notifications.post"),
];

/// Calls allowed per second per app, and the burst it may spend.
pub const RATE_LIMIT_PER_SECOND: u32 = 20;
pub const RATE_BURST: u32 = 40;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Decision {
    Allow { permission: &'static str },
    /// The method exists but the app has not been granted what it needs.
    Deny { permission: &'static str },
    /// No such method: the app is asking for something the platform does not offer.
    Unsupported,
    /// Too many calls in the last second.
    RateLimited,
}

impl Decision {
    pub fn status(&self) -> &'static str {
        match self {
            Self::Allow { .. } => "applied",
            Self::Deny { .. } => "denied",
            Self::Unsupported => "unsupported",
            Self::RateLimited => "stale",
        }
    }
}

/// What the broker does with the request it just received.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AuditEntry {
    pub at_ms: u64,
    pub app_id: String,
    pub method: String,
    /// `applied`, `denied`, `unsupported`, `stale`, or `invalid`.
    pub outcome: &'static str,
    /// Why, when the outcome is not `applied`.
    pub reason: String,
}

impl AuditEntry {
    /// One line, stable shape: `at app method outcome [reason]`.
    pub fn line(&self) -> String {
        if self.reason.is_empty() {
            format!("{} {} {} {}", self.at_ms, self.app_id, self.method, self.outcome)
        } else {
            format!("{} {} {} {} {}", self.at_ms, self.app_id, self.method, self.outcome, self.reason)
        }
    }
}

/// Token bucket per app: `RATE_BURST` to spend, refilled `RATE_LIMIT_PER_SECOND` times a
/// second. Bounded arithmetic on integers, so a clock that jumps cannot mint calls.
#[derive(Debug, Clone)]
pub struct RateLimiter {
    tokens: u32,
    last_refill_ms: u64,
}

impl RateLimiter {
    pub fn new(now_ms: u64) -> Self {
        Self {
            tokens: RATE_BURST,
            last_refill_ms: now_ms,
        }
    }

    pub fn allow(&mut self, now_ms: u64) -> bool {
        let elapsed = now_ms.saturating_sub(self.last_refill_ms);
        let refilled = (elapsed / (1000 / RATE_LIMIT_PER_SECOND as u64)) as u32;
        if refilled > 0 {
            self.tokens = (self.tokens + refilled).min(RATE_BURST);
            self.last_refill_ms = now_ms;
        }
        if self.tokens == 0 {
            return false;
        }
        self.tokens -= 1;
        true
    }
}

/// Decide one request. `now_ms` is passed in so tests own the clock.
pub fn authorize(
    method: &str,
    granted: &BTreeSet<String>,
    limiter: &mut RateLimiter,
    now_ms: u64,
) -> Decision {
    let Some((_, permission)) = METHODS.iter().find(|(name, _)| *name == method) else {
        return Decision::Unsupported;
    };
    if !limiter.allow(now_ms) {
        return Decision::RateLimited;
    }
    if !granted.contains(*permission) {
        return Decision::Deny { permission };
    }
    Decision::Allow { permission }
}

/// The permission a method needs, or `None` for an unknown method.
pub fn permission_for(method: &str) -> Option<&'static str> {
    METHODS
        .iter()
        .find(|(name, _)| *name == method)
        .map(|(_, permission)| *permission)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn granted(permissions: &[&str]) -> BTreeSet<String> {
        permissions.iter().map(|p| p.to_string()).collect()
    }

    #[test]
    fn a_granted_method_is_allowed() {
        let mut limiter = RateLimiter::new(0);
        let decision = authorize("session.windows", &granted(&["windows.read"]), &mut limiter, 0);
        assert_eq!(decision, Decision::Allow { permission: "windows.read" });
        assert_eq!(decision.status(), "applied");
    }

    #[test]
    fn declaring_is_not_granting() {
        let mut limiter = RateLimiter::new(0);
        let decision = authorize("session.windows", &granted(&[]), &mut limiter, 0);
        assert_eq!(decision, Decision::Deny { permission: "windows.read" });
        assert_eq!(decision.status(), "denied");
    }

    #[test]
    fn an_unknown_method_is_unsupported_not_forwarded() {
        let mut limiter = RateLimiter::new(0);
        assert_eq!(
            authorize("shell.exit", &granted(&["windows.read"]), &mut limiter, 0),
            Decision::Unsupported
        );
    }

    #[test]
    fn every_catalogued_method_names_a_permission() {
        for (method, permission) in METHODS {
            assert!(!method.is_empty() && !permission.is_empty());
            assert_eq!(permission_for(method), Some(permission));
        }
        assert_eq!(permission_for("nope"), None);
    }

    #[test]
    fn the_rate_limit_refuses_a_burst() {
        let mut limiter = RateLimiter::new(0);
        let permissions = granted(&["windows.read"]);
        let mut allowed = 0;
        for _ in 0..(RATE_BURST + 10) {
            if authorize("session.windows", &permissions, &mut limiter, 0) != Decision::RateLimited {
                allowed += 1;
            }
        }
        assert_eq!(allowed, RATE_BURST, "the burst is spent, then refused");
        // A second later the bucket has refilled by the per-second rate.
        let mut allowed_after = 0;
        for _ in 0..RATE_LIMIT_PER_SECOND {
            if authorize("session.windows", &permissions, &mut limiter, 1000) != Decision::RateLimited {
                allowed_after += 1;
            }
        }
        assert_eq!(allowed_after, RATE_LIMIT_PER_SECOND);
    }

    #[test]
    fn a_clock_that_goes_backwards_cannot_mint_calls() {
        let mut limiter = RateLimiter::new(10_000);
        let permissions = granted(&["windows.read"]);
        for _ in 0..RATE_BURST {
            authorize("session.windows", &permissions, &mut limiter, 10_000);
        }
        assert_eq!(
            authorize("session.windows", &permissions, &mut limiter, 5_000),
            Decision::RateLimited
        );
    }

    #[test]
    fn an_audit_line_is_stable_and_names_the_reason() {
        let entry = AuditEntry {
            at_ms: 42,
            app_id: "io.github.alice.clock".to_string(),
            method: "session.activate".to_string(),
            outcome: "denied",
            reason: "needs windows.control".to_string(),
        };
        assert_eq!(entry.line(), "42 io.github.alice.clock session.activate denied needs windows.control");
        let ok = AuditEntry { reason: String::new(), outcome: "applied", ..entry };
        assert_eq!(ok.line(), "42 io.github.alice.clock session.activate applied");
    }

    #[test]
    fn a_denied_call_still_costs_a_token() {
        // A refused request is traffic too: otherwise an app can hammer the socket for free.
        let mut limiter = RateLimiter::new(0);
        for _ in 0..RATE_BURST {
            authorize("session.activate", &granted(&[]), &mut limiter, 0);
        }
        assert_eq!(
            authorize("session.activate", &granted(&[]), &mut limiter, 0),
            Decision::RateLimited
        );
    }
}
