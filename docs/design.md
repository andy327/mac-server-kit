# mac-server-kit design

Decisions settled before implementation. Each section gives the decision first, with any reasoning that affects later choices.

## Scope

- Audience: the owner, his brother, and a few friends. Prompts, an answers file and a README checklist are enough. No hardening for strangers' machines.
- Private repo for now and possibly public later. Because publishing exposes the full history, nothing machine-specific is ever committed.
- Complete break from the original `mac-media-stack` project. The only connection is a credit in the README.
- Platform: macOS only, with Docker via OrbStack. Intel and Apple Silicon. Some target Macs have no Homebrew.

## Language

Bash 3.2 (stock macOS), no dependencies. Chosen over zsh for readability; the installer behaves the same for users either way. The module design avoids needing associative arrays by discovering module folders and reading small key=value files.

## Commands (hybrid)

From the repo checkout:

```
./kit prepare [--vpn <provider>] [--media-server <choice>] [<module>...]
                                   # what to have ready before installing
./kit prepare ... --answers-template <file> --secrets-template <file>
./kit install                      # prompts, or: ./kit install [--answers <file>] [--secrets <file>]
./kit check                        # can this Mac run it, and is it ready? (changes nothing)
./kit add <module>
./kit disable <module>
./kit status                       # enabled modules, holds and their age, health summary
```

`prepare` reads everything from the modules, so it can't drift from what `install` asks for. It uses this machine's answers when there are any, the defaults otherwise, and the flags and named modules on top. It's read-only apart from the templates it writes. Each asked key has a line in its module's `help` file: one sentence on what the service is and what the kit uses it for, then where to get it, naming the provider's actual page and setting (e.g. ProtonVPN → Downloads → WireGuard configuration, NAT-PMP on). The same text shows above the install prompt and in the templates. Items that aren't keys (accounts, tailnet settings, admin password, being at the screen for OrbStack) live in a per-module `ready` file. The list is grouped into: needed during the questions, about the machine, and after the first start (checklist items, so nobody stalls looking for them).

The secrets template is a fill-in `secrets.conf` holding only the keys the user supplies for the given VPN provider and modules, each with its hint. Required keys are present and empty. Optional keys are commented out, so install still asks about them unless the user uncomments one and leaves it empty to skip it for good. Typical use: the owner fills in keys for another person's machine, sends the file privately, and they run `./kit install --secrets <file>`.

The answers template is the same for `answers.conf`: every asked answer with its default (or this run's choice) filled in, `~/` paths that mean the target Mac's home folder, the `MODULES=` line, and the never-asked settings commented out. With both templates filled in, install asks nothing, which also makes test runs repeatable. `--answers` and `--secrets` copy the file into place only when there's no file there yet. A required key left empty is asked again (its new line is appended, since the last line wins).

Installed to `~/server/bin` for runtime, used by launchd and by hand:

```
update-all
backup-all            backup-<module>
restore-<module> <date>
check-health          show-health-history
start-maintenance     end-maintenance
copy-backups
```

## Layout on a machine

- `~/server/<project>/`: compose projects (media stack, separate-project modules)
- `~/server/appdata/<project>/`: app data
- `~/server/backups/<project>/<project>-<date>/`: local backups (keep 8)
- `~/server/bin/`: runtime scripts. Install puts it on the PATH by adding one marked line to `~/.zprofile` (created if missing), only if that line isn't there yet. This is the one write to a file outside `~/server` that the user owns.
- `~/server/logs/`: health logs
- `~/server/local-modules/`: git-ignored, machine-only modules (same layout as repo modules)
- `MEDIA_ROOT` (default `~/Media`: Downloads, Movies, TV Shows) and `GAMES_ROOT` (default `~/Games`). Asked once and stored in the answers file, so they can move to an external drive later.
- `.env` files use absolute paths, not `~`.
- `APPS_DIR` (Advanced answer, default `/Applications`): where the kit installs native apps (Plex, Jellyfin, Ollama). Set it to `~/Applications` to keep the apps in one user's account, as on a test account. Brew casks get `--appdir "$APPS_DIR"`. The kit looks for an app in `APPS_DIR` and then `/Applications`, so one already installed isn't installed again, and launchd jobs point at wherever the app is. Apps the kit doesn't install (OrbStack, the host's Tailscale) stay wherever the user put them.

## Base install

- Gluetun: ProtonVPN default (port forwarding wired up), NordVPN as an option (WireGuard/NordLynx, no port forwarding). No other providers, and no extra DNS or HTTP-proxy settings.
- qBittorrent, Prowlarr, Sonarr, Radarr, Bazarr (subtitles; mounts Movies and TV Shows), FlareSolverr (Prowlarr's indexer proxy), Seerr
- Media server: the installer asks Plex, Jellyfin, or both. Plex runs natively as a login item. Seerr and Tracearr follow the choice.
- The stack's Tailscale node, logged in with auth keys (not printed login URLs, to avoid a login race)
- Homarr on its own Tailscale node (default name `dashboard`)
- Glances, native, 10-second refresh (lower CPU than the 2s default). Installed with brew if present, else with uv (`uv tool install glances`, uv itself from its standalone installer into `~/.local/bin`). uv is the no-Homebrew path for every Python tool the kit installs; never `pip --user`. Glances binds `127.0.0.1` (not `0.0.0.0`): under OrbStack, `host.docker.internal` reaches services that listen only on the Mac's loopback, so glances-proxy still works and Glances stays off the LAN.
- Health: check-health, a 5-minute log-health job, health-web (nginx, `/health/` on the dashboard node, feeds a Homarr iframe widget), maintenance windows. Healthchecks.io dead-man's switch is optional (URL prompt). ntfy is optional: a topic wired into check-health for direct problem/recovery alerts. Linking a Healthchecks check to ntfy is a manual checklist step.
- Backups and updates (below)

## Optional modules

| Module | Notes |
|---|---|
| jellyfin | Native app. Brew cask if brew exists, else download and install the .dmg (hdiutil, pick Intel vs arm64 build). The .dmg path needs its own version check in update-all. Tailscale Funnel front lives in the media stack compose. |
| tracearr | In the media stack compose, own Tailscale node. Requires Plex or Jellyfin. First-run steps go on the checklist. |
| wud | What's Up Docker, in the media stack compose, tailnet-only. |
| romm | Separate compose project. RomM stock config (no tuned scan settings shipped). Asks which platforms to create `roms/<platform>` and `bios/<platform>` folders for, and says more can be added later. Metadata provider credentials are optional prompts. |
| ollama | Own module. Model suggested from machine RAM, changeable. Runs `ollama serve` from the kit's own launchd job (not `brew services`, not the menu-bar app), bound to `127.0.0.1:11434`. Binary: the brew formula if brew exists, else `Ollama.app` from the official .dmg, using the CLI at `Contents/Resources/ollama`. The app's login item is removed so it can't start a second server; update-all checks the .dmg version itself. Needs macOS 14+; Intel Macs run CPU-only (preflight warns). |
| open-webui | Requires ollama. Public via Funnel behind its login by default (user can opt out), 90-day sessions by default, changeable. Turning on MFA is a checklist step. |
| karakeep | Asks whether to turn on AI tagging if ollama is enabled. |

The landing page is not a repo module. It is a local module on the owner's server only.

### Module folder contents

Each module declares:

- compose file, and whether it joins the media stack compose or is its own project
- env template and its prompts (with defaults)
- native prerequisites and how to install them with and without brew
- backup, update and restore scripts
- dependencies on other modules
- Tailscale node name (default, changeable) and exposure (Funnel or tailnet-only default, asked once)
- Homarr apps, and Homarr integrations as a *separate* step (see Homarr)
- widgets/integrations it makes available, for the post-install list
- version holds (see Updates)

## Install model

- One idempotent install path. `add` re-runs it with the module enabled. `docker compose up -d` only recreates changed services, so adding a module doesn't restart unrelated ones. The exception is the stack's Tailscale container restarting briefly when `serve.json` changes.
- File rules: generated files are rebuilt every run; seeded files/settings are create-if-missing; user-owned files are never overwritten or regenerated. The only writes to the answers and secrets files are appending keys that are missing (prompt answers) and editing the single `MODULES=` line (`add`/`disable`). Users customize through `compose.override.yml` per project (Compose merges it automatically) plus the answers and secrets files.
- `.env` files are generated from the answers and secrets files on every run. They are never hand-edited.
- `disable` stops and removes containers (`compose down` without `-v`), unloads launchd jobs, and drops the module from update/backup/health. Volumes and appdata stay. Re-enabling brings it back with data intact. Full removal is not supported.

## Secrets and preflight

- Two input modes, one result: a user-filled secrets file, or prompts at the start. Prompts append to the same secrets file (chmod 600, git-ignored).
- Random app secrets (Homarr encryption key, Gluetun control key, qBittorrent password, database passwords) go in a separate seeded file, `~/server/kit/generated-secrets.conf` (chmod 600). Each key is created once if missing and never changed. Losing this file loses database passwords and Homarr's encryption key, so backup-config and restore-config always include it, along with the answers and secrets files.
- `./kit check` (and the start of every install) checks the Mac itself: macOS 13 or newer and a supported CPU, or "this Mac can't run the kit"; memory (warns under 8 GB) and free disk (warns under 20 GB); then OrbStack installed and running with `docker compose` 2.24+. Missing software isn't a verdict on the Mac: it's listed under "To do first" with the step to take, so `check` works on a Mac that has never had the kit.
- Preflight runs before anything is installed:
  - format checks: Tailscale auth key prefix, WireGuard private key shape, Healthchecks URL shape, Homarr API key shape
  - VPN key, live: throwaway Gluetun container, confirm it connects with a non-home IP, tear it down
  - Healthchecks URL, live: one ping
  - Tailscale auth keys: format only (validating would use them up)
- Plex is native, so there is no claim token. Plex sign-in is a checklist item.

## App wiring

Config files are seeded before first start. If a file already exists, nothing is written and keys are read from it:

- Sonarr, Radarr, Prowlarr `config.xml` with API keys generated into `generated-secrets.conf`, so every consumer knows the keys before anything starts
- qBittorrent `qBittorrent.conf`: generated password (PBKDF2 hash, computed with openssl 3 in a throwaway container), local-auth bypass (needed by Gluetun's port-forward hook) plus a whitelist of only the Docker gateway /32, `tun0`, save and temp paths. `categories.json` with `radarr` and `tv-sonarr`
- Bazarr `config.yaml` with its Sonarr and Radarr connections. If Bazarr rejects a partial file, the fallback is its settings API

Then, through app APIs, for what lives in app databases (create-if-missing, looked up by name first):

- root folders under `MEDIA_ROOT`
- qBittorrent as download client (correct hostname given it sits behind Gluetun)
- Prowlarr: a `flaresolverr` tag and the FlareSolverr indexer proxy (`http://flaresolverr:8191`) carrying it
- Prowlarr → Sonarr/Radarr sync
- Sonarr/Radarr → Plex library updates, if Plex is enabled and its token can be read

The old stack's scripts are a source of working details, not a template. Indexers are not added, and the installer never waits at a prompt for Seerr.

Left to the checklist: indexers (users tag Cloudflare-protected ones `flaresolverr`), quality profiles and size limits (the docs may suggest defaults), and Seerr's setup (interactive Plex sign-in).

## Homarr

- One manual step: the user creates an admin API key in Homarr (it can go in the secrets file).
- The installer then creates apps and integrations for enabled modules via Homarr's API. Plex token is read from native Plex preferences. Jellyfin needs a key created in its UI.
- Integrations are a separate step per module behind `HOMARR_INTEGRATIONS` (default on), so falling back to apps-only is a default flip.
- Homarr's API is unversioned, so failures warn and continue.
- No boards are created. The installer prints iframe URLs for custom widgets (health) and a list of widgets/integrations available for what's installed.

## Updates and image pins

- Image pins (tag@digest) live in a lock file on each machine, untracked. Compose files in the repo carry only `repo:tag`. A generated `zz-images.yml` override applies the pins through Compose's own file merge. Update scripts refresh the lock and regenerate the override. No repo pull needed to update images.
- Backup, update and restore are generic per-project runtime scripts driven by module metadata installed to `~/server/kit/modules/`, with small module hooks only where needed (online SQLite copies, .dmg version checks, release-tag lookups). `backup-<module>` and friends are thin wrappers.
- Version holds: modules ship known-good holds. The answers file can add or lift holds per machine. Each hold records a reason and date, e.g. `meilisearch: v1.41 # <reason>, 2026-11`. `./kit status` lists holds with their age so stale ones stand out. The WUD "hide update" label follows the hold.
- update-all prunes unused images and build cache once at its start. It is manual by default, with an optional weekly schedule (off by default).

## Backups

- One weekly launchd job runs `backup-all`, which backs up each enabled module in order, then config, Plex and Jellyfin (online SQLite copies).
- Keep 8 locally.
- `copy-backups` to an external drive: the installer asks for a drive path and it's off if none is given. APFS recommended. It only copies when the drive is mounted and prunes per project on the drive only.

## Mac settings

- The installer asks laptop or server.
- Server: apply power settings (`sleep 0`, `autorestart 1`, etc.) with sudo after confirmation, filtered by `pmset -g cap` so unsupported settings are skipped.
- Laptop: skip power settings.
- Native apps are added as login items.
- Auto-login is a checklist item (blocked by FileVault, would require handling the password).
- The Mac's own Tailscale app is not installed by the kit. In server mode the checklist recommends it for remote SSH and Screen Sharing. check-health watches it according to `HOST_TAILSCALE=auto|on|off` in the answers file (default `auto`: only if it's installed).

## OrbStack

Prerequisite. Installed with brew if present. Otherwise preflight stops with the download link and waits. Its first launch needs the user at the screen anyway.

## Existing machines

The two machines already running an older setup are adopted once, by hand, after the kit works on a test machine. Nothing for adoption ships in the repo.

## Testing and order of work

1. Repo skeleton and base install, tested in a separate standard user account on the M4 MacBook Air, with `APPS_DIR=~/Applications`. Not a macOS VM: Apple Silicon allows nested virtualization only for Linux guests, so OrbStack can't run inside a macOS VM. Everything the kit writes is under that user's home folder, so deleting the user (with its home folder) removes it all. OrbStack in `/Applications` is shared with the owner's account; quit it in the owner's account during test runs.
2. Modules one at a time.
3. Test the Intel and no-Homebrew paths (.dmg and uv fallbacks) on a spare Intel Mac. The M4 test account can't cover them.
4. Adopt the owner's server, then his brother's.
