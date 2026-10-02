//! Identity of the login the shell is running in.
//!
//! Desktop-integration state (KDE shortcuts, the panel marker, KWin's blur)
//! lives in files, so it survives the process that created it - including a
//! reboot that never ran a hand-back. The boot id is the one piece of ground
//! truth that separates "this session's claim" from "a claim a previous boot
//! left behind", and it is read from the kernel rather than guessed.

use crate::domain::branding;

/// Where the kernel publishes the current boot id (a UUID, one per boot).
pub const BOOT_ID_PATH: &str = "/proc/sys/kernel/random/boot_id";

/// Boot id of the running system, or `None` when it cannot be established.
///
/// `ASTRAL_PLASMA_BOOT_ID` overrides the kernel file, which is how tests drive
/// the previous-boot case deterministically.
pub fn current_boot_id() -> Option<String> {
    if let Some(value) = branding::env_value(branding::ENV_BOOT_ID) {
        return parse_boot_id(&value);
    }
    let raw = std::fs::read_to_string(BOOT_ID_PATH).ok()?;
    parse_boot_id(&raw)
}

/// Validate a boot id.
///
/// The kernel publishes a UUID: hex digits and hyphens. An empty or malformed
/// value is not an identity, and returning `None` for it is deliberate - a claim
/// that cannot be compared against a real boot id is released rather than kept
/// (`desktop_integration::claim_is_stale`).
pub fn parse_boot_id(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    let well_formed = trimmed.len() >= 8
        && trimmed.contains('-')
        && trimmed.chars().all(|c| c.is_ascii_hexdigit() || c == '-');
    well_formed.then(|| trimmed.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_kernel_boot_id_is_accepted() {
        assert_eq!(
            parse_boot_id("19b856cd-3601-443d-a12f-dbaef4533265\n").as_deref(),
            Some("19b856cd-3601-443d-a12f-dbaef4533265")
        );
    }

    #[test]
    fn an_unreadable_boot_id_is_not_an_identity() {
        for raw in ["", "   ", "\n", "unknown", "0", "not a boot id"] {
            assert_eq!(parse_boot_id(raw), None, "{raw:?} must not identify a boot");
        }
    }

    #[test]
    fn the_override_wins_over_the_kernel_file() {
        // A kernel boot id is a UUID: the override has to look like one, because
        // anything else is not an identity (see the rejection test above).
        std::env::set_var(branding::ENV_BOOT_ID, "19b856cd-3601-443d-a12f-dbaef4533265");
        assert_eq!(
            current_boot_id().as_deref(),
            Some("19b856cd-3601-443d-a12f-dbaef4533265")
        );
        // A whitespace-only override reads as "not set", so the kernel's own id
        // applies - the same tolerance every other override in `branding` has.
        std::env::set_var(branding::ENV_BOOT_ID, "   ");
        let kernel = std::fs::read_to_string(BOOT_ID_PATH).expect("kernel boot id");
        assert_eq!(current_boot_id(), parse_boot_id(&kernel));
        // A malformed override is not an identity: the session must not keep a
        // claim on the strength of a placeholder.
        std::env::set_var(branding::ENV_BOOT_ID, "not a boot id");
        assert_eq!(current_boot_id(), None);
        std::env::remove_var(branding::ENV_BOOT_ID);
    }
}
