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

The answers template is the same for `answers.conf`: every asked answer with its default (or this run's choice) filled in, `~/` paths that mean the target Mac's home folder, the `MODULES=` line, and the never-asked settings commented out. With both templates filled in, install asks nothing, once each optional key in the secrets template is uncommented (left empty to skip it). Optional keys left commented out are asked, with Enter to skip. That also makes test runs repeatable. `--answers` and `--secrets` copy the file into place only when there's no file there yet, and only once the questions are done and every value has passed its check: until then the run works on a draft in `~/server/kit/`, so an install that's quit, or stopped by a bad value, leaves nothing behind and can be rerun with the corrected file. Messages about a value name the user's own file. Without these options, answers typed at the prompts are saved as they're given, so an interrupted run keeps them. A required key left empty is asked again (its new line is appended, since the last line wins).

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
- `~/Library/LaunchAgents/io.github.andy327.mac-server-kit.<job>.plist`: the kit's launchd jobs, generated each install from the modules' `jobs` files (launchd loads a user's jobs at login only from there). A job no enabled module declares is unloaded and its plist removed. Job output goes to `~/server/logs/<job>.log`.
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
- Tailscale details: each node is a `tailscale/tailscale` container (`<node>-tailscale`) in its project, logged in once with `TS_AUTHKEY` (`TS_AUTH_ONCE`), its state in app data, healthy once it has its tailnet address. The auth key carries a tag (`tag:server`), so the nodes' logins never expire; that needs a `tagOwners` entry in the tailnet policy first, and Funnel's policy entry has to list the tag too (tagged machines aren't `autogroup:member`). What a node serves comes from the modules' `serve` files (`node|port|path|target|when|funnel`); the kit generates `~/server/<project>/tailscale/<node>/serve.json` from them, mounted as a folder so a change applies without a restart. Funnel is port 443 only, needs `EXPOSE_<node>=funnel`, and waits until the app behind it is set up (Seerr: until someone has signed in), so no stranger can claim a fresh app first. After the start the kit reads each node's real address (Tailscale adds `-1` when a name is taken) into `~/server/kit/tailnet.conf`, warns about a taken name, a missing tag, MagicDNS or HTTPS certificates being off, and shows the tailnet addresses in the report
- Glances, native, 10-second refresh (lower CPU than the 2s default). Installed with brew if present, else with uv (`uv tool install glances`, uv itself from its standalone installer into `~/.local/bin`). uv is the no-Homebrew path for every Python tool the kit installs; never `pip --user`. Glances binds `127.0.0.1` (not `0.0.0.0`): under OrbStack, `host.docker.internal` reaches services that listen only on the Mac's loopback, so glances-proxy still works and Glances stays off the LAN.
- Health (the `health` module, ported from the reference's scripts): check-health (a report with a diagnosis, or `--log`: one sample every 5 minutes from the `log-health` launchd job, incident snapshots, a Healthchecks.io check-in, ntfy alerts), show-health-history, export-health-status, start/end-maintenance, and the media stack's check-media-stack. What they check comes from the generated `~/server/kit/runtime.conf` (mode 600): the projects, the Healthchecks URL and optional API key, the ntfy URL, `HOST_TAILSCALE`, and native apps from the modules' `NATIVE_HEALTH` lines (`name|port|path|fail or warn|how to start|extra logs`, several separated by `;`). ntfy alerts go out when something breaks, when it recovers, and when the Mac is back after a restart or a gap; not inside a maintenance window or while an update-, backup- or restore- script runs. The install checks in with Healthchecks.io once and sends an ntfy test message the first time a topic is set. health-web (nginx, a service in the media stack, its config inline in its compose file) serves `status.json` and the newest incident zip from `~/server/logs/health/web`, to Homarr's "Server health" custom widget as `http://health-web` and on the dashboard node at `/health/` (which the widget's download link uses). Healthchecks.io and ntfy are both optional (secrets prompts). Linking a Healthchecks check to ntfy is a manual checklist step.
- Runtime scripts: a module's `bin/` files are copied into `~/server/bin` on each install; `~/server/kit/bin.list` records which are the kit's, so ones no module has any more are removed and the user's own are left alone. They follow `KIT_SERVER_DIR` like the kit, for tests.
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
- prompts (with defaults) and an `env` file: `KEY|value|when` lines for the project's generated `.env`, where `${NAME}` is an answer, a secret, a generated secret or a kit value (`KIT_PUID`, `KIT_PGID`, `KIT_APPDATA`, `KIT_LOGS`). A module adds to another project with `env.<project>` and `compose.<project>.yml`
- native prerequisites and how to install them with and without brew
- backup, update and restore scripts
- dependencies on other modules
- Tailscale node name (default, changeable) and exposure (Funnel or tailnet-only default, asked once)
- Homarr apps, and Homarr integrations as a *separate* step (see Homarr)
- widgets/integrations it makes available, for the post-install list
- version holds (see Updates)

## Install model

- One idempotent install path. `add` re-runs it with the module enabled. `docker compose up -d` only recreates changed services, so adding a module doesn't restart unrelated ones. A changed `serve.json` applies without restarting its Tailscale node. Install runs: preflight, answers and secrets, folders and the PATH line, generate (`.env`, `compose.d/`, image pins, `serve.json`), seed (`hooks/seed`), then `docker compose up -d --wait --wait-timeout 300 --remove-orphans` per project (`--remove-orphans` takes away a disabled module's containers), reads the Tailscale nodes' addresses, wires the apps (`hooks/wire`, Homarr included) and imports the Homarr custom widgets, installs the runtime scripts, `runtime.conf` and the launchd jobs, and ends with the addresses and the checklist. A project that doesn't start shows `compose ps` and the hints (a module's `hints` file, `service|text`) of the services that aren't running and healthy, and the install stops.
- Each project folder holds a generated `compose.d/` (every enabled module's compose file for it, rebuilt each run, so a disabled module's file is simply gone) and a `COMPOSE_FILE` list in `.env`. The list starts with a generated `project.yml` (just the project name), because Compose resolves `./` in every file against the first file's folder; without it, `./tailscale/...` would point into `compose.d/`. It ends with `compose.override.yml` when the user has one. Plain `docker compose` commands in the folder see the same project. The kit's compose files follow fixed layout rules (two-space services, one `image: repo:tag` line each) so the kit can read their images without a YAML parser; a test enforces the rules.
- File rules: generated files are rebuilt every run; seeded files/settings are create-if-missing; user-owned files are never overwritten or regenerated. The only writes to the answers and secrets files are appending keys that are missing (prompt answers) and editing the single `MODULES=` line (`add`/`disable`). Users customize through `compose.override.yml` per project (Compose merges it automatically) plus the answers and secrets files.
- `.env` files are generated from the answers and secrets files on every run. They are never hand-edited. Each holds `COMPOSE_PROJECT_NAME` and single-quoted values, and is private (600) because it carries keys. A value can't contain a `'` or a line break; the install stops if one would.
- `disable` stops and removes containers (`compose down` without `-v`), unloads launchd jobs, and drops the module from update/backup/health. Volumes and appdata stay. Re-enabling brings it back with data intact. Full removal is not supported.

## Secrets and preflight

- Two input modes, one result: a user-filled secrets file, or prompts at the start. Prompts append to the same secrets file (chmod 600, git-ignored).
- Random app secrets (Homarr encryption key, Gluetun control key, qBittorrent password, database passwords) go in a separate seeded file, `~/server/kit/generated-secrets.conf` (chmod 600). Each key is created once if missing and never changed. Losing this file loses database passwords and Homarr's encryption key, so backup-config and restore-config always include it, along with the answers and secrets files.
- `./kit check` (and the start of every install) checks the Mac itself: macOS 13 or newer and a supported CPU, or "this Mac can't run the kit"; memory (warns under 8 GB) and free disk (warns under 20 GB); then OrbStack installed and running with `docker compose` 2.24+. Missing software isn't a verdict on the Mac: it's listed under "To do first" with the step to take, so `check` works on a Mac that has never had the kit.
- Preflight runs before anything is installed:
  - format checks: Tailscale auth key prefix, WireGuard private key shape, Healthchecks URL shape, Homarr API key shape
  - VPN key, live: throwaway Gluetun container, confirm it connects with a non-home IP, tear it down
  - Healthchecks URL, live: one ping
  - Tailscale auth keys: format only (validating would use them up). Whether a node joined, and with a tag, is checked after the start
- Plex is native, so there is no claim token. Plex sign-in is a checklist item.

## App wiring

Config files are seeded before first start by the module's `hooks/seed` (bash, run in a subshell). If a file already exists, nothing is written and keys are read from it (an existing `config.xml`'s API key wins over the generated one):

- Sonarr, Radarr, Prowlarr `config.xml` with API keys generated into `generated-secrets.conf`, so every consumer knows the keys before anything starts. Only `ApiKey` and `LogLevel` (info) are seeded; the apps fill in the rest, and ask for a login to be created on first open (a checklist item)
- qBittorrent `qBittorrent.conf` (5.x layout: a `[WebUI]` section and `[Meta] MigrationVersion=12`): login `admin` with the generated password as qBittorrent's PBKDF2-HMAC-SHA512 hash (100,000 rounds, computed with the perl that ships with macOS, so no container), local-auth bypass (needed by Gluetun's port-forward hook) plus a whitelist of only the Docker gateway /32, `tun0`, save and temp paths. `categories.json` with `radarr` and `tv-sonarr`
- Bazarr `config/config.yaml` with its own API key and its Sonarr and Radarr connections (a partial file works; Bazarr fills in the rest). Bazarr reads any value that looks like a number as one, even quoted, and then drops it, so the *arr API keys are generated to start with a letter

Then, after the stack has started, the module's `hooks/wire` sets what lives in app databases through their APIs (`lib/api.sh`: curl and text tools, no jq). Each item is looked up by name or path first and created only if missing, so re-runs create nothing; a failed item warns, and the install goes on:

- Sonarr and Radarr: root folders `/tv` and `/movies`, and qBittorrent as download client at `gluetun:8080` (it shares Gluetun's network), login `admin` with the generated password, categories `tv-sonarr` and `radarr`. The apps log in to qBittorrent when the client is added, so this also checks the seeded password
- Prowlarr: a `flaresolverr` tag, the FlareSolverr indexer proxy (`http://flaresolverr:8191/`) carrying it, and Sonarr and Radarr as full-sync apps with the reference stack's categories (Prowlarr's own defaults leave out anime, sport and documentaries). Prowlarr checks each app's API key when it's added
- Seerr, once someone has signed in to it (its API refuses its own key before that): Sonarr and Radarr as its services, with their first quality profile and the library folders. Before sign-in the install only says so; the next run connects it. Not yet checked against a signed-in Seerr (that needs a media server, so it waits for the Plex milestone)
- Sonarr/Radarr → Plex library updates, if Plex is enabled and its token can be read (with Plex, in a later milestone)

The old stack's scripts are a source of working details, not a template. Indexers are not added, and the installer never waits at a prompt for Seerr.

Left to the checklist: indexers (users tag Cloudflare-protected ones `flaresolverr`), quality profiles and size limits (the docs may suggest defaults), and signing in to Seerr (interactive Plex or Jellyfin sign-in), followed by `./kit install` again.

## Homarr

- A fresh Homarr gets its first account from the kit: `admin`, with the generated `HOMARR_ADMIN_PASSWORD`, and an API key for the kit, stored in `generated-secrets.conf`. It does this through the same calls Homarr's setup pages make (claim the setup, step past the welcome page, create the account, sign in, create a key), once per machine. The rest of Homarr's setup (server settings, first board) is left to the user, who signs in as admin to finish it. Homarr 2 takes its address from each request, so it needs no `BASE_URL`.
- A Homarr that already has an account (set up by hand, or adopted) needs a key from its owner: `HOMARR_API_KEY` in `secrets.conf`, which wins over the kit's own. The install says so and goes on without tiles until then.
- The installer then creates a tile (app) for each app via Homarr's published API, opening the app's Tailscale address (this Mac's when the node isn't up), and its widget connection (integration) linked to the tile. Integrations go through Homarr's internal API, as Homarr's own pages do (its published API can't create them). Each is looked up by name first, so re-runs create nothing; tiles aren't changed once made. Plex token is read from native Plex preferences. Jellyfin needs a key created in its UI.
- Integrations are a separate step behind `HOMARR_INTEGRATIONS` (default on), so falling back to tiles only is a default flip.
- Homarr's internal API is unversioned, so failures warn and continue. Homarr publishes only exact version tags (`v2.3.0`) and `latest`, no major-version tag; keeping updates within one major version is update-all's job (it can compare release tags).
- No boards are created. Custom widgets ship with their module as `homarr-widget.json` (a `homarr-custom-widget-v2` definition without its template) and `homarr-widget.jsx` (the template); the install imports each once, by name, through tRPC `customWidget.import` (checked against Homarr 2.11). Modules: health (Server health); glances (Mac Host Info, a draft until Glances is installed).

## Updates and image pins

- Image pins (tag@digest) live in a lock file on each machine, untracked. Compose files in the repo carry only `repo:tag`. A generated `zz-images.yml` override applies the pins through Compose's own file merge. Update scripts refresh the lock and regenerate the override. No repo pull needed to update images. Install pins only services that have no pin yet, pulling the tracked tag (the compose file's, or a hold's); it never moves an existing pin, and re-pins only when a service's image repo changes. Deleting a line from `images.lock` makes the next install pin it afresh. A disabled module's pins stay in the lock but leave `zz-images.yml`.
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
