# Release keys

`astral-plasma.pub` is the project's minisign public key (key id
`47F66C1650F9EE59`). It is pinned in
`daemon/src/infrastructure/update_source.rs` as `PINNED_MINISIGN_KEY`, and that
pinning is what a signature is verified against.

- **Never commit a secret key.** The matching secret key lives on the release
  machine (`~/.minisign/astral-plasma.key`) and in the repository secret
  `MINISIGN_SECRET_KEY`.
- **Rotating** is a two-release operation; see
  [`docs/UPDATES.md` §15](../../docs/UPDATES.md).
- The daemon verifies in-process (`minisign-verify`), so a user needs no signing
  tool; only CI signs (`scripts/astral-sign.sh`).
