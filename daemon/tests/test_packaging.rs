//! The packaging contract: a package install must stay a package install.
//!
//! These read the files that ship. They are cheap, and they catch the two
//! mistakes that would turn an AUR install into a second owner of the same
//! binary: installing somewhere other than `/usr/bin`, or advertising a
//! self-updating install.

use std::path::PathBuf;

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .expect("daemon/ has a parent")
        .to_path_buf()
}

fn read(rel: &str) -> String {
    let path = repo_root().join(rel);
    std::fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("cannot read {}: {err}", path.display()))
}

#[test]
fn the_package_installs_the_binary_pacman_owns() {
    let pkgbuild = read("packaging/aur/PKGBUILD");
    assert!(
        pkgbuild.contains("/usr/bin/astral-plasma"),
        "the package must install to /usr/bin so `pacman -Qo` can report the owner"
    );
    assert!(
        pkgbuild.contains("provides=('astral-plasma')")
            && pkgbuild.contains("conflicts=('astral-plasma')"),
        "the package must own the `astral-plasma` name so a checkout install cannot coexist"
    );
    assert!(
        pkgbuild.contains("pkgname=astral-plasma-bin"),
        "a binary package, not a source build"
    );
    assert!(
        pkgbuild.contains("quickshell>=0.3.0"),
        "the runtime floor is a dependency, not a runtime surprise"
    );
}

#[test]
fn the_package_documents_who_updates_it() {
    let readme = read("packaging/aur/README.md");
    assert!(readme.contains("pacman -Qo"), "ownership is detected, not assumed");
    assert!(
        readme.contains("must not self-update"),
        "the reason the updates page refuses is documentation, not folklore"
    );
}

#[test]
fn updates_are_documented_where_the_apps_platform_expects_them() {
    // docs/APPS-PLATFORM-SPEC.md links docs/UPDATES.md as the install/update
    // ownership contract; the phases it names must stay described.
    let spec = read("docs/APPS-PLATFORM-SPEC.md");
    assert!(spec.contains("UPDATES.md"), "the apps platform links the update contract");
    let updates = read("docs/UPDATES.md");
    for phase in ["P2", "P3", "P4", "P5", "P6"] {
        assert!(
            updates.contains(phase),
            "docs/UPDATES.md must keep phase {phase}; the platform work stacks on it"
        );
    }
}
