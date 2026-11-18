# Contributing

Thanks for helping. Bug reports, fixes, new modules and doc improvements are all welcome.

## Before you start

- Read [docs/design.md](docs/design.md). It explains how install, modules, generated and seeded
  files and the runtime scripts fit together, and why.
- For anything bigger than a small fix, open an issue first so we can agree on the approach.
- Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Rules the code follows

- **Stock `/bin/bash` 3.2, no dependencies.** No associative arrays, `mapfile`, `${var,,}`, jq,
  yq or anything that needs Homebrew. Some target Macs can't run Homebrew.
- **Nothing machine-specific in tracked files:** no tailnet or host names, usernames, emails,
  keys or paths under a real home folder. Machine specifics belong in the answers and secrets
  files, `compose.override.yml` and `~/server/local-modules/`.
- **Keep the three kinds of files apart:** generated (rebuilt every run), seeded (created only if
  missing) and user-owned (never overwritten). See the design doc.
- **Every install step is idempotent** and skip-if-done. Steps that can break across app versions
  (API calls especially) warn and continue; they never abort the install.
- **Every asked answer key needs a line in its module's `help` file.** A test checks it.
- **Naming:** install-time commands go through `./kit`; runtime scripts in `~/server/bin` are
  verb-first (`backup-<module>`, `check-health`, ...); launchd labels are
  `io.github.andy327.mac-server-kit.<job>`.

## Testing

```bash
tests/run
```

Run it before every commit. It runs the tests with `/bin/bash` 3.2, then shellcheck and
`tests/compose-check` when they're installed, then `tests/check-private`. Fake values in tests
end their line with `# check-private: allow` or go in `tests/private-allow`.

Containers can't run in CI, so changes that touch real installs should also be tried on a Mac,
ideally in a separate user account ([docs/test-account.md](docs/test-account.md)). Say in the
pull request what you ran and what you couldn't.

## Pull requests

- Keep each pull request to one change, with tests for new behavior.
- Update the docs (`README.md`, `docs/`, the module's `help` file) when behavior changes.
- Write commit messages that say what changed and why, in the imperative ("Retry Cloudflare-blocked
  indexers through FlareSolverr").

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE),
and that you'll follow the [Code of Conduct](CODE_OF_CONDUCT.md).
