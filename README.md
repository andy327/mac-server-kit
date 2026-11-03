# mac-server-kit

Installer and runtime scripts for a macOS home server: a VPN-routed media stack (Gluetun,
qBittorrent, Prowlarr, Sonarr, Radarr, Bazarr, FlareSolverr, Seerr), Plex and/or Jellyfin,
a Homarr dashboard on Tailscale, Glances, health monitoring and backups, plus optional modules
(RomM, Ollama, Open WebUI, Karakeep, Tracearr, What's Up Docker).

Stock macOS only: bash 3.2, no Homebrew required. Docker runs in OrbStack.

**Status:** under construction. `./kit install` currently collects and checks the answers and
secrets and resolves modules; it doesn't install anything yet.

## Usage

```bash
./kit prepare                      # what to have ready (options: --vpn, --media-server, modules)
./kit check                        # preflight only
./kit install                      # asks for what it needs
./kit install --answers <file> --secrets <file>    # from filled-in templates, no questions
./kit add <module>                 # e.g. ./kit add ollama open-webui
./kit disable <module>             # containers and jobs go; data stays
./kit status                       # modules, version holds, health
```

`./kit prepare --answers-template <file> --secrets-template <file>` writes fill-in versions of
both files, with a note on every key saying what it is and where to get it.

Everything machine-specific lives in `~/server/`, outside this checkout:
`answers.conf` and `secrets.conf` are yours to edit (the kit only appends missing keys and edits
`MODULES=`), and `~/server/local-modules/` holds modules for this machine only.

Design and decisions: [docs/design.md](docs/design.md).

## Development

```bash
tests/run
```

Runs every test with `/bin/bash` 3.2 against a temporary `~/server`, and shellcheck when it's
installed.

## Credits

Started from [mac-media-stack](https://github.com/liamvibecodes/mac-media-stack) by liamvibecodes.
