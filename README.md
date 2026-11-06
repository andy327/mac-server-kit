# mac-server-kit

Installer and runtime scripts for a macOS home server: a VPN-routed media stack (Gluetun,
qBittorrent, Prowlarr, Sonarr, Radarr, Bazarr, FlareSolverr, Seerr), Plex and/or Jellyfin,
a Homarr dashboard on Tailscale, Glances, health monitoring and backups, plus optional modules
(RomM, Ollama, Open WebUI, Karakeep, Tracearr, What's Up Docker).

Stock macOS only: bash 3.2, no Homebrew required. Docker runs in OrbStack.

**Status:** under construction. `./kit install` sets up, starts and connects the media stack
(Gluetun, qBittorrent, the *arr apps, Seerr, Homarr) on this Mac, puts it on your tailnet
(Seerr public through Funnel once it's set up), fills Homarr with a tile and widget for each
app, and watches the Mac's health every 5 minutes (Healthchecks.io and ntfy alerts, a Server
health widget in Homarr). Backups, updates, Plex and Glances come next.

## Usage

```bash
./kit prepare                      # what to have ready (options: --vpn, --media-server, modules)
./kit check                        # can this Mac run it, and is it ready? (changes nothing)
./kit install                      # asks for what it needs
./kit install --answers <file> --secrets <file>    # from filled-in templates
./kit add <module>                 # e.g. ./kit add ollama open-webui
./kit disable <module>             # containers and jobs go; data stays
./kit status                       # modules, version holds, health
```

`./kit prepare --answers-template <file> --secrets-template <file>` writes fill-in versions of
both files, with a note on every key saying what it is and where to get it.

Everything machine-specific lives in `~/server/`, outside this checkout:
`answers.conf` and `secrets.conf` are yours to edit (the kit only appends missing keys and edits
`MODULES=`), and `~/server/local-modules/` holds modules for this machine only.

Once installed, `~/server/bin` (on your PATH) has the everyday commands:

```bash
check-health                       # is everything up? (show-health-history for the past)
show-logins                        # each app's address, user and password (show-logins jellyfin)
backup-all                         # every project and the config; weekly on Sunday by itself
restore-media-stack                # back to the newest backup (or name one); asks first
restore-plex                       # the same for Plex (backup-all backs it up while it runs)
restore-jellyfin                   # the same for Jellyfin
update-all                         # pull new images, re-pin, restart what changed; Jellyfin, Glances
copy-backups                       # to BACKUP_DRIVE when it's plugged in
```

Design and decisions: [docs/design.md](docs/design.md).

## Development

```bash
tests/run
```

Runs every test with `/bin/bash` 3.2 against a temporary `~/server` and home folder, several test
files at a time (`KIT_TEST_JOBS`, default one per CPU; `-v` lists each test), then shellcheck when it's installed, then `tests/compose-check` when Docker Compose is
installed (it generates the compose projects and has `docker compose config` check them; it starts
nothing), then `tests/check-private`, which fails if a file holds anything
machine-specific: real-looking keys, `*.ts.net` names, `/Users/<name>` paths, email addresses,
your username, and any words in `~/.config/mac-server-kit/private-words` (machine and tailnet
names; that file stays outside the repo). Fake values in tests end their line with
`# check-private: allow` or are listed in `tests/private-allow`.

### CI

GitHub Actions ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs on every pull request
and on pushes to `main`:

- **Tests** on an Intel macOS runner, with the same stock `/bin/bash` 3.2 a target Mac has
  (Intel because GitHub's Apple Silicon runners kept cancelling the job for lack of capacity).
- **Shellcheck**, **`tests/compose-check`** and **`tests/check-private --history`** on Linux. The history check covers every
  commit's changes and message, because a slip that reaches GitHub stays in the history.

Containers can't run on GitHub's macOS runners, so real installs are tested at each milestone in a
separate user account on a Mac (not a macOS VM, where OrbStack can't run). Before pushing for the
first time, run `tests/check-private --history` locally.

## Credits

Started from [mac-media-stack](https://github.com/liamvibecodes/mac-media-stack) by liamvibecodes.
