# mac-server-kit

Turn a Mac into a home media server with one command. The kit installs, connects and looks after
a VPN-routed download stack, Plex and/or Jellyfin, a dashboard, remote access over Tailscale,
health alerts and weekly backups, plus optional extras like a game library and local AI.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white)
![Intel and Apple Silicon](https://img.shields.io/badge/Intel%20%26%20Apple%20Silicon-supported-555555)
![No Homebrew needed](https://img.shields.io/badge/Homebrew-not%20required-FBB040?logo=homebrew&logoColor=white)
![Bash 3.2](https://img.shields.io/badge/bash-3.2%20(stock)-4EAA25?logo=gnubash&logoColor=white)
![Docker via OrbStack](https://img.shields.io/badge/Docker-OrbStack-2496ED?logo=docker&logoColor=white)

## What's included

**Base install**

<table>
  <tr>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/gluetun.svg" width="40" alt=""><br><sub><b>Gluetun</b><br>VPN</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/qbittorrent.svg" width="40" alt=""><br><sub><b>qBittorrent</b><br>downloads</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/prowlarr.svg" width="40" alt=""><br><sub><b>Prowlarr</b><br>indexers</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/sonarr.svg" width="40" alt=""><br><sub><b>Sonarr</b><br>TV shows</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/radarr.svg" width="40" alt=""><br><sub><b>Radarr</b><br>movies</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/bazarr.svg" width="40" alt=""><br><sub><b>Bazarr</b><br>subtitles</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/flaresolverr.svg" width="40" alt=""><br><sub><b>FlareSolverr</b><br>Cloudflare proxy</sub></td>
  </tr>
  <tr>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/seerr.svg" width="40" alt=""><br><sub><b>Seerr</b><br>requests</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/plex.svg" width="40" alt=""><br><sub><b>Plex</b><br>and/or</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/jellyfin.svg" width="40" alt=""><br><sub><b>Jellyfin</b><br>streaming</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/homarr.svg" width="40" alt=""><br><sub><b>Homarr</b><br>dashboard</sub></td>
    <td align="center" width="96"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/tailscale-light.svg"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/tailscale.svg" width="40" alt=""></picture><br><sub><b>Tailscale</b><br>remote access</sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/glances.svg" width="40" alt=""><br><sub><b>Glances</b><br>Mac stats</sub></td>
    <td align="center" width="96"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/healthchecks.svg"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/healthchecks-dark.svg" width="40" alt=""></picture><br><sub><b>Healthchecks</b><br>+ ntfy alerts</sub></td>
  </tr>
</table>

**Optional modules** (`./kit add <name>`)

<table>
  <tr>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/romm.svg" width="40" alt=""><br><sub><b>RomM</b><br><code>romm</code></sub></td>
    <td align="center" width="96"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/ollama-dark.svg"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/ollama.svg" width="40" alt=""></picture><br><sub><b>Ollama</b><br><code>ollama</code></sub></td>
    <td align="center" width="96"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/open-webui-light.svg"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/open-webui.svg" width="40" alt=""></picture><br><sub><b>Open WebUI</b><br><code>open-webui</code></sub></td>
    <td align="center" width="96"><picture><source media="(prefers-color-scheme: dark)" srcset="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/karakeep.svg"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/karakeep-dark.svg" width="40" alt=""></picture><br><sub><b>Karakeep</b><br><code>karakeep</code></sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/tracearr.svg" width="40" alt=""><br><sub><b>Tracearr</b><br><code>tracearr</code></sub></td>
    <td align="center" width="96"><img src="https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/svg/whats-up-docker.svg" width="40" alt=""><br><sub><b>What's Up Docker</b><br><code>wud</code></sub></td>
  </tr>
</table>

## What the kit does for you

- **Installs everything:** containers in OrbStack, native apps (Plex, Jellyfin, Glances, Ollama)
  with or without Homebrew.
- **Connects the apps to each other:** qBittorrent behind the VPN with port forwarding,
  Sonarr/Radarr to qBittorrent and Prowlarr, FlareSolverr to Prowlarr, Seerr to Sonarr/Radarr,
  library rescans in Plex/Jellyfin, a Homarr tile and widget for each app.
- **Makes the logins:** strong passwords for each app, generated on this Mac. `show-logins` lists
  them.
- **Remote access:** each app group gets its own Tailscale address. Only what's meant to be public
  (Seerr's request page, optionally Jellyfin or Open WebUI) goes on the internet through Funnel,
  and only once its owner has set it up.
- **Looks after the Mac:** a health check every 5 minutes with phone alerts, a Server health
  widget, power settings so it never sleeps, everything restarting after a power cut or reboot.
- **Backups and updates:** weekly backups of every app's data (and copies to an external drive),
  and pinned image versions that `update-all` moves forward after a backup.
- **Safe to run again:** `./kit install` only does what isn't done yet, and never overwrites your
  settings.

## Requirements

- A Mac with **macOS 13 (Ventura) or newer**, Intel or Apple Silicon
- **8 GB of memory** or more (works with less, with a warning), and **20 GB free** for apps and
  images, plus room for your media (an external drive is fine)
- An **admin password** for the Mac (asked once, at the start)
- [**OrbStack**](https://orbstack.dev) to run Docker (the kit installs it when Homebrew is
  present; otherwise download it and open it once)
- A **paid VPN** plan: **ProtonVPN** (Plus or higher, with port forwarding) or NordVPN
- A free [**Tailscale**](https://tailscale.com) account
- A free [**Plex**](https://plex.tv) account if you choose Plex (Jellyfin needs none)
- Optional: a free [Healthchecks.io](https://healthchecks.io) check and the
  [ntfy](https://ntfy.sh) app for alerts

Homebrew is **not** required. Some older Macs can't run it, so the kit falls back to each
vendor's own download.

`./kit prepare` prints a complete checklist for your choices, with where to find each key.

## Fresh install, step by step

**1. Get the kit** onto the Mac. With git (`xcode-select --install` gets it, no Homebrew needed):

```bash
git clone https://github.com/andy327/mac-server-kit.git
cd mac-server-kit
```

Or download the ZIP from GitHub and unpack it.

**2. See what to have ready.** Read-only; it lists accounts, keys and settings for your choices:

```bash
./kit prepare                                  # defaults: ProtonVPN, Plex, no modules
./kit prepare --media-server both romm ollama  # or with your choices
```

**3. Check the Mac.** Also read-only:

```bash
./kit check
```

It says whether this Mac can run the kit, and lists anything to do first (installing OrbStack,
for example).

**4. Install.** It asks a few questions (each with a default), then runs on its own:

```bash
./kit install
```

To skip the questions, fill in the two templates first (handy when setting up someone else's
Mac):

```bash
./kit prepare --answers-template answers.conf --secrets-template secrets.conf
# edit both files, then:
./kit install --answers answers.conf --secrets secrets.conf
```

At the end the install prints a summary: what's new, any warnings, each app's address and a
**Still to do** list.

**5. Finish the few steps only you can do.** The Still to do list covers them. Typically:

- add indexers in Prowlarr
- sign in to Seerr with your Plex/Jellyfin account
- sign in to Plex on this Mac and add the Movies and TV Shows libraries
- finish Homarr's setup page and place the tiles on a board
- optionally, turn on automatic login so the server comes back after a power cut

**6. Run the install again.** It connects whatever your steps made possible: Seerr to
Sonarr/Radarr, Plex to Sonarr/Radarr/Homarr, Seerr on Funnel. Repeat until it reports nothing
new and no warnings.

```bash
./kit install
```

Before you change anything, `./kit install --plan` shows what an install would do, without doing
it.

## Your files

Everything specific to your Mac lives in `~/server/`, outside the kit's folder. You can update or
re-clone the kit without losing anything.

| File | What it is | Who edits it |
|---|---|---|
| `~/server/answers.conf` | Your choices: paths, media server, VPN, Tailscale names, modules | You (the kit only adds missing keys and edits `MODULES=`) |
| `~/server/secrets.conf` | Keys you supplied: VPN key, Tailscale auth key, alert URLs | You (private, mode 600) |
| `~/server/kit/generated-secrets.conf` | Passwords and API keys the kit made for the apps | The kit, once; `show-logins` reads it |
| `~/server/<project>/compose.override.yml` | Your own Docker Compose changes, merged in automatically | You (optional) |
| `~/server/local-modules/` | Modules for this Mac only | You (optional) |
| `~/server/appdata/` | Each app's data and settings | The apps |
| `~/server/backups/` | Weekly backups (the newest 8 of each) | `backup-all` |
| `~/server/logs/` | Job and health logs | The kit |
| `~/server/bin/` | Everyday commands (on your PATH) | The kit |

**`answers.conf`** holds your answers to the install's questions, each with a note on what it means:

```bash
# Where should media live (Downloads, Movies, TV Shows)?
MEDIA_ROOT=~/Media

# Media server: plex, jellyfin or both?
MEDIA_SERVER=plex

# VPN provider: protonvpn or nordvpn?
VPN_PROVIDER=protonvpn

# Tailscale machine name for the media stack
TS_NODE_media=media

# Optional modules (./kit add <module> later does the same).
MODULES=romm ollama
```

Change a value and run `./kit install` again to apply it. A few advanced settings, such as
`UPDATE_SCHEDULE=weekly` or `APPS_DIR=~/Applications`, are never asked; the template lists them
commented out.

**`secrets.conf`** holds the keys only you can get. Required ones first, optional ones (left out to
be asked, or empty to skip):

```bash
WIREGUARD_PRIVATE_KEY="..."     # from your VPN provider
TS_AUTHKEY="tskey-auth-..."     # Tailscale admin console → Settings → Keys
HEALTHCHECK_URL="https://hc-ping.com/..."
NTFY_TOPIC="a-hard-to-guess-name"
```

Every other secret (app passwords, API keys) the kit generates itself into
`generated-secrets.conf`. Both files are included in the kit's backups.

## Kit commands

Run from the kit's folder:

```bash
./kit prepare            # what to have ready (--vpn, --media-server, modules)
./kit check              # can this Mac run it, and is it ready? (changes nothing)
./kit install            # install, or apply changed answers; safe to repeat
./kit install --plan     # what an install would change, changing nothing
./kit add <module>       # e.g. ./kit add ollama open-webui
./kit disable <module>   # its containers and jobs go; its data stays
./kit status             # modules, version holds, to-dos, health
```

To update the kit itself:

```bash
git pull --ff-only
./kit install
```

## Everyday commands

Once installed, these are on your PATH:

```bash
check-health             # is everything up? (show-health-history for the past)
show-logins              # each app's address, user and password (show-logins plex)
backup-all               # back up every app and the config, then copy-backups
restore-media-stack      # back to the newest backup (or name one); asks first
update-all               # back up, pull newer images, restart what changed
copy-backups             # copy backups to BACKUP_DRIVE when it's plugged in
start-maintenance        # before planned downtime: pauses alerts
end-maintenance          # after it
```

There's a `restore-<name>` for each part with data: `restore-plex`, `restore-jellyfin`,
`restore-open-webui`, `restore-karakeep`, `restore-romm` (its library and saves, not the games).

### What runs by itself

| When | What |
|---|---|
| Every 5 minutes | `check-health --log`: health sample, Healthchecks.io check-in, ntfy alerts |
| Sundays at 5:30 | `backup-all`, then `copy-backups` if the drive is plugged in |
| Sundays at 6:30 | `update-all`, only with `UPDATE_SCHEDULE=weekly` |
| At login | `wait-volumes`: starts containers once external drives are mounted |
| Always | Plex, Jellyfin, Glances, Ollama, restarted if they stop |

## More docs

- [docs/external-drive.md](docs/external-drive.md): media or games on an external drive
- [docs/design.md](docs/design.md): how it all works, and why

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
