# Testing in a separate account

Real installs are tested in a separate macOS user account, `kit-test`, on the M4 MacBook Air, because OrbStack can't run inside a macOS VM (see design.md, Testing). Everything the kit writes goes into that account's home folder, so deleting the account removes it all.

## In your own account

1. **Create the account.** System Settings → Users & Groups → Add User. Choose **Standard**, enter the account name `kit-test`, and give it any full name (for example "Kit Test") and a password.
2. **Quit OrbStack** (menu bar icon → Quit). The stack's ports listen on the whole Mac, and each account runs its own OrbStack.
3. **Get Tailscale ready** (milestone 4 on):
   - https://login.tailscale.com/admin/dns: MagicDNS and HTTPS Certificates both enabled.
   - https://login.tailscale.com/admin/acls/file (the JSON editor). Copy the whole text somewhere first, so you can paste it back. Then:
     - Under `"tagOwners"`, add `"tag:server": ["autogroup:admin"],`. If there's no `"tagOwners"`, add `"tagOwners": {"tag:server": ["autogroup:admin"]},` after the first `{`.
     - Under `"nodeAttrs"`, find the entry with `"attr": ["funnel"]` (the default policy has one) and add `"tag:server"` to its `"target"` list: `["autogroup:member", "tag:server"]`.
     - Save. The console checks the file first and changes nothing if it's broken.
   - https://login.tailscale.com/admin/settings/keys → Generate auth key, just for testing: Reusable on, Ephemeral off, Pre-approved on (only shown when device approval is on), Tags: `tag:server`. Copy it (it's shown once).
4. **Copy the repo** to a folder both accounts can read (it brings this document along):

   ```bash
   cp -R ~/src/andy327/mac-server-kit /Users/Shared/
   ```

## In the kit-test account

5. **Log in** and finish the macOS welcome screens.
6. **Open OrbStack** from Applications and finish its first-run steps. If it asks for an admin password for its helper, use your own.
7. **Copy the repo into this account and check the Mac** (in Terminal):

   ```bash
   cp -R /Users/Shared/mac-server-kit ~/ && cd ~/mac-server-kit && ./kit check
   ```

   Everything should be ✓. Under "To do first" it says what's missing, if anything.

8. **Make the answers and secrets files:**

   ```bash
   ./kit prepare --answers-template answers.conf --secrets-template secrets.conf
   ```

   ```bash
   open -e secrets.conf
   ```

   - `WIREGUARD_PRIVATE_KEY`: a real key. Create a new ProtonVPN WireGuard configuration just for testing (account.protonvpn.com → Downloads → WireGuard configuration, NAT-PMP on, a P2P server), so you can revoke it afterwards. Copy the PrivateKey value under [Interface], not the PublicKey under [Peer].
   - `TS_AUTHKEY`: the tagged test key from step 3.
   - The optional keys (`HEALTHCHECK_URL`, `NTFY_TOPIC`) are commented out, so install asks for them and Enter skips each. To skip them without being asked, uncomment them and leave them empty.

   Then open `answers.conf` (`open -e answers.conf`):

   - Change `MACHINE_ROLE=server` to `MACHINE_ROLE=laptop`, so a later milestone doesn't change the Mac's power settings during a test.
   - Change `TS_NODE_media=media` to `TS_NODE_media=kit-media` and `TS_NODE_dashboard=dashboard` to `TS_NODE_dashboard=kit-dashboard`, so the test machines don't clash with your server's.
   - Add this line at the end, so native apps from a later milestone install into this account only (the kit ignores it until then):

     ```
     APPS_DIR=~/Applications
     ```

9. **Install:**

   ```bash
   ./kit install --answers answers.conf --secrets secrets.conf
   ```

10. **Run it again.** It should pull nothing, keep every seeded file and leave the containers running:

   ```bash
   ./kit install
   ```

## Checks

11. Open http://localhost:7575 (Homarr) and http://localhost:8080 (qBittorrent opens with **no login** on this Mac).
12. The VPN. The first command should print a VPN address, not your home IP. The second prints the forwarded port (ProtonVPN only):

    ```bash
    docker exec gluetun wget -qO- https://ipinfo.io/ip
    ```

    ```bash
    docker exec gluetun cat /tmp/gluetun/forwarded_port
    ```

13. Memory use, to set the kit's memory warning from a real figure:

    ```bash
    docker stats --no-stream
    ```

14. The containers' state:

    ```bash
    cd ~/server/media-stack && docker compose ps
    ```

### App connections (milestone 3)

The install's "Connecting the apps" section should list eight ✓ lines the first time and "(already set)" the second time.

15. **Sonarr** (http://localhost:8989; it asks you to create a login first):
    - Settings → Media Management → Root Folders lists `/tv`.
    - Settings → Download Clients lists qBittorrent. Open it and click **Test**: it should go green.
16. **Radarr** (http://localhost:7878): the same, with `/movies`.
17. **Prowlarr** (http://localhost:9696):
    - Settings → Apps lists Sonarr and Radarr. **Test** on each should go green.
    - Settings → Indexers lists the FlareSolverr proxy with the `flaresolverr` tag.
18. **Indexer sync, end to end:** in Prowlarr, Indexers → Add Indexer, add any public indexer and save. Within a minute it should show up in Sonarr's and Radarr's Settings → Indexers.
19. **Seerr** can't be checked yet: signing in to it needs a Plex or Jellyfin server, which comes in a later milestone. Its line should say "not set up yet".

### Tailscale and Homarr (milestone 4)

20. **The nodes.** The install's "Tailscale" section shows `kit-media` and `kit-dashboard` with their `https://` addresses and no `!` lines, then "Seerr stays tailnet-only until it's set up". In the admin console → Machines, both show the `tag:server` tag and "Expiry disabled".
21. **From another device on your tailnet** (your phone, or your own account): `https://kit-dashboard.<your-tailnet>.ts.net` opens Homarr, `https://kit-media.<your-tailnet>.ts.net:8989` opens Sonarr, and `:8080` opens qBittorrent, which asks for a login there (admin and `QBITTORRENT_PASSWORD`).
22. **No Funnel yet:** this prints 0, since Seerr isn't set up:

    ```bash
    grep -c AllowFunnel ~/server/media-stack/tailscale/media/serve.json
    ```

23. **Homarr.** Get the admin password:

    ```bash
    grep HOMARR_ADMIN_PASSWORD ~/server/kit/generated-secrets.conf
    ```

    Open Homarr: it should say "Administrator sign-in required". Sign in as `admin` with that password and finish the setup page. Then:
    - Under Management → Apps: Seerr, Sonarr, Radarr, Prowlarr, Bazarr and qBittorrent, each opening its `kit-media` address.
    - Under Management → Integrations: Sonarr, Radarr, Prowlarr, Bazarr, qBittorrent and Gluetun. Test each one's connection.
    - Add a widget that uses one (Calendar with Sonarr, or Downloads with qBittorrent) to a board, and see it show data.
    - Management → Tools → API lists the key the kit made (the install sends people who set Homarr up by hand there).
24. **Run the install again:** every Homarr line says "(already there)" and the Tailscale lines are the same.

### Health (milestone 5)

Needs a Healthchecks.io check and an ntfy topic just for testing: healthchecks.io → your project → Add Check (Period 5 minutes, Grace 15 minutes), then its ping URL (note where the page shows it); and in the ntfy app, + → a hard-to-guess topic. Put both in `~/server/secrets.conf` as `HEALTHCHECK_URL` and `NTFY_TOPIC` before installing.

25. **The install's "Health and jobs" section:** the runtime scripts, then `Job log-health: every 5 min`. Under "Connecting the apps": `Healthchecks.io: pinged`, `ntfy: test message sent` (and the message on your phone), and `Homarr: Server health widget`. The second install: `(already loaded)`, `Healthchecks.io: pinged (HEALTHCHECK_URL still works)` without a ✓, `test message sent before`, `(already there)`.
26. **The job runs:**

    ```bash
    launchctl list | grep mac-server-kit
    ```

    shows `io.github.andy327.mac-server-kit.log-health` with status 0. After 5 minutes, `check-health` gives a full report ending in a diagnosis, `./kit status` ends with "Healthy at …", and `show-health-history` lists the samples. On Healthchecks.io the check is green.
27. **The widget.** In Homarr, Management → Custom widgets lists Server health. Add it to a board: it shows Healthy, the uptime numbers and "No incident zips yet".
28. **An outage:** `docker stop sonarr`. Within 5 minutes your phone gets "something's broken" and Healthchecks.io shows the check down; `check-health` says what's wrong and how to fix it. Then `docker start sonarr`: within 5 minutes, "recovered". The widget lists the outage and offers the incident zip, which downloads from the `kit-dashboard` address.
29. **A maintenance window:** `start-maintenance test`, `docker stop sonarr`, wait 6 minutes: no alert. Then `docker start sonarr` and `end-maintenance`.

### Backups and updates (milestone 6)

A USB stick helps for check 36 (any format; APFS is what a real server should use). Without one, skip that check.

30. **The install.** "Health and jobs" lists the new scripts and `Job backup-all: weekly, Sunday 05:30`, and no update-all job (`UPDATE_SCHEDULE` is off). `grep homarr ~/server/media-stack/images.lock` ends in `v2.*`. The Server health widget line says `(already there)`.
31. **The weekly backup, run by launchd now** (this also checks that launchd's jobs find Docker):

    ```bash
    launchctl kickstart gui/$(id -u)/io.github.andy327.mac-server-kit.backup-all
    ```

    Wait a minute or two, then `tail -n 30 ~/server/logs/backup-all.log` ends in "Everything backed up". `ls ~/server/backups/*/` shows a `media-stack-<date>` and a `config-<date>` folder, and `cat ~/server/backups/media-stack/media-stack-*/manifest.txt` lists the pins and sizes. No ntfy alert arrives, though the apps stopped for the copy.
32. **A restore after breaking something.** Wipe Sonarr's database:

    ```bash
    docker stop sonarr && rm ~/server/appdata/media-stack/sonarr/sonarr.db* && docker start sonarr
    ```

    In http://localhost:8989, Settings → Media Management has no root folder and Settings → Download Clients is empty. Then run `restore-media-stack`, type `restore` when asked, and wait for it to finish with the media stack's check. Both are back (`/tv` and qBittorrent), and so is Sonarr's login if you had made one (without one it shows "Authentication Required", as before). The folder it set aside is in `~/server/backups/media-stack/pre-restore-<date>`.
33. **An update:** `update-all`. Each project either says it's up to date with nothing restarted, or lists the new pins, restarts and prints the restore command that would undo it. It ends with a check-health report.
34. **The widget update.** Change the kit's copy of the widget, then install:

    ```bash
    sed -i '' 's/Recent outages/Recent outages (kit test)/' ~/mac-server-kit/modules/health/homarr-widget.jsx && ./kit install
    ```

    It says the kit has a newer Server health widget and asks `Update it in Homarr?`. Answer y: `Server health widget updated`, and the board's widget shows the new heading.
35. **A widget changed in Homarr.** In Homarr, Management → Custom widgets → Server health → edit, change anything and save. Then change the kit's copy again and install:

    ```bash
    sed -i '' 's/(kit test)/(kit test 2)/' ~/mac-server-kit/modules/health/homarr-widget.jsx && ./kit install
    ```

    It says the one in Homarr was changed there since and asks to replace it. Answer n (the default): `kept as you have it`, and your edit is still there. A third install doesn't ask.
36. **The external copy** (with a USB stick plugged in, named for example KITTEST): set `BACKUP_DRIVE="/Volumes/KITTEST/kit-backups"` in `~/server/answers.conf`, run `./kit install`, then `copy-backups`. If macOS asks whether Terminal may access a removable volume, allow it. `ls /Volumes/KITTEST/kit-backups/*/` shows the same backups, without the `pre-restore-` folder. Eject the stick and run `copy-backups` again: "isn't plugged in; nothing copied", no error.

### Native apps: Plex and Glances (milestone 7)

Needs your Plex account. kit-test is a standard account, so first set `APPS_DIR="~/Applications"` in `~/server/answers.conf` (add the line if it isn't there): apps go into kit-test's own Applications folder. Your Homebrew belongs to your account, so the install falls back to Plex's download and to uv for Glances; that's part of the test.

37. **The install.** "Mac settings" says `Power settings: left alone (MACHINE_ROLE=laptop)`. "Native apps" downloads Plex (after "Homebrew couldn't install it", or straight away) and installs uv, then Glances. "Health and jobs" lists `Job plex` and `Job glances`, both `always running`. `ls ~/Applications` shows Plex Media Server.app, and `~/.local/bin/glances --version` answers. On a Mac whose own account already has Plex in /Applications and Glances in its Homebrew, both say "already installed" instead, and the kit uses those.
38. **They run.** Plex's icon is in the menu bar, http://localhost:32400/web opens, and `check-health`'s "Apps running on macOS" shows Plex and Glances answering. `launchctl list | grep mac-server-kit` lists plex and glances with a process ID.
39. **Plex wiring.** In http://localhost:32400/web, sign in. Before adding libraries, `./kit install` notes `Sonarr: Plex has no TV library yet` and the same for Radarr (no warnings), and adds the Homarr Plex tile. Add two libraries: Movies (`~/Media/Movies`) and TV Shows (`~/Media/TV Shows`). Run `./kit install` again: `Sonarr: Plex library updates`, `Radarr: Plex library updates`, `Homarr: Plex tile` and `widget connection`. In Sonarr, Settings → Connect → Plex → Test passes.
40. **Seerr, at last.** Open http://localhost:5055, sign in with Plex, and when its setup asks for the server, enter `plex-proxy`, port 32400, no SSL; pick the libraries and finish. Run `./kit install` again: the Seerr lines connect it to Sonarr and Radarr, Homarr gets its widget connection, and the Tailscale section no longer says "Seerr stays tailnet-only" (Funnel is on). From your phone, off Wi-Fi, `https://kit-media.<your-tailnet>.ts.net` opens Seerr.
41. **The Mac Host Info widget.** In Homarr, add it to a board: CPU, memory and disk rings, the CPU and memory charts, and the network row labelled `(en0)` on the Air.
42. **Restarts.** `pkill -9 -f "Plex Media Server.app/Contents/MacOS/Plex Media Server"`: within a minute Plex is back, and `check-health` lists the plex job as "running again (launchd restarted it after it exited with status -9)", not as a failure. Quit Plex from its menu bar icon instead: it stays stopped, and `check-health` says to run `launchctl kickstart -k gui/$(id -u)/io.github.andy327.mac-server-kit.plex`, which brings it back.
43. **Plex backup and restore.** `backup-plex`, then rename the Movies library in Plex, then `restore-plex` and type `restore`. The first time, macOS asks whether Terminal may control Plex Media Server: allow it. Plex quits, comes back, and the library has its old name. The replaced data is in `~/server/backups/plex/pre-restore-<date>`.
44. **In the weekly jobs.** `backup-all` has a `==== plex` part, and `update-all` a `==== glances` part ("up to date" or a new version and a restart; a Glances from another account's Homebrew is left to that account, without failing update-all).
45. **Power settings (optional).** Set `MACHINE_ROLE=server` in `~/server/answers.conf` and run `./kit install`: "Mac settings" lists the power settings it would change and asks to apply them. Answer n (kit-test can't use sudo), check that it prints the `sudo pmset -a ...` command, then set `MACHINE_ROLE=laptop` back.

Send back the output of both installs and of the checks, especially anything in red.

### Jellyfin, and the apps' logins (milestone 8)

Switch kit-test to both media servers: `MEDIA_SERVER=both` in `~/server/answers.conf`, and `APPS_DIR="~/Applications"` (kit-test can't write /Applications, and your Homebrew belongs to your account, so Jellyfin comes from its .dmg: that's part of the test). The install asks two new questions: Jellyfin's Tailscale machine name (answer `kit-jellyfin`) and whether it's public (funnel).

46. **The install.** "Native apps": `Jellyfin: downloading it from jellyfin.org`, then `✓ Jellyfin: ~/Applications/Jellyfin.app`. "Health and jobs" (now before "Connecting the apps") lists `Job jellyfin: always running`. "Connecting the apps": `Jellyfin: set up, with its admin account`, `an API key for the kit`, the Movies and TV Shows libraries, `Sonarr: Jellyfin library updates`, `Radarr: ...`, `Homarr: Jellyfin tile` and `widget connection`, then `Jellyfin: public now (Funnel)`. "Open" lists Jellyfin with its kit-jellyfin address. A second install changes nothing.
47. **Jellyfin itself.** http://localhost:8096: sign in as admin with `JELLYFIN_ADMIN_PASSWORD` from `~/server/kit/generated-secrets.conf`. No setup wizard; your account (top right) → Dashboard → Libraries shows Movies and TV Shows on `~/Media`; Dashboard → API Keys shows mac-server-kit. No Jellyfin icon in the menu bar (the kit runs its server directly). `check-health` shows Jellyfin answering.
48. **Connections.** In Sonarr, Settings → Connect → Jellyfin → Test passes; the same in Radarr. In Homarr, the Jellyfin tile opens it.
49. **From outside.** On your phone, off Wi-Fi, `https://kit-jellyfin.<your-tailnet>.ts.net` opens Jellyfin's sign-in page.
50. **Logins.** kit-test's Sonarr, Radarr and Prowlarr already have the login you made, so the install says `login (already set)` for each. To see the kit make one, remove Prowlarr's: `cd ~/server/media-stack && docker compose stop prowlarr && sqlite3 ~/server/appdata/media-stack/prowlarr/prowlarr.db 'delete from Users' && docker compose start prowlarr`, then `./kit install`: `✓ Prowlarr: login (admin, with ARR_PASSWORD)`. Prowlarr (http://localhost:9696) now takes admin with `ARR_PASSWORD` from `~/server/kit/generated-secrets.conf`.
51. **Restarts.** `pkill -9 -f "Jellyfin.app/Contents/MacOS/jellyfin"`: within a minute it's back (`check-health`).
52. **Backup and restore.** `backup-jellyfin`, rename the Movies library in Jellyfin, `restore-jellyfin` and type `restore`: Jellyfin stops, comes back, and the library has its old name.
53. **Weekly jobs.** `backup-all` has `==== plex` and `==== jellyfin` parts; `update-all` a `==== jellyfin` part ("up to date (12.x)").

### Tracearr and What's Up Docker (milestone 9)

Add both to kit-test with `./kit add tracearr wud`. It asks one new question: Tracearr's Tailscale machine name (answer `kit-tracearr`).

54. **The install.** "Compose projects" pins tracearr, tracearr-db, tracearr-redis, tracearr-tailscale and wud. Tailscale lists `kit-tracearr`. "Connecting the apps": `Homarr: WUD tile` and `widget connection`, `Homarr: Tracearr tile`, and a note that Tracearr's widget connection waits for `TRACEARR_API_KEY`. "Open" lists Tracearr at its kit-tracearr address and WUD at the media address's port 3030. A second install changes nothing.
55. **Tracearr's setup.** https://kit-tracearr.<your-tailnet>.ts.net (or http://localhost:3000) asks for a claim code: `TRACEARR_CLAIM_CODE` from `~/server/kit/generated-secrets.conf`. Create the owner account, then add Plex (sign in with Plex; if it asks for an address, `http://plex-proxy:32400`) and Jellyfin (`http://jellyfin-proxy:8096` and a Jellyfin API key). Note where Tracearr shows its API key.
56. **Tracearr's widget.** Put that key in `~/server/secrets.conf` as `TRACEARR_API_KEY` and run `./kit install`: `✓ Homarr: Tracearr widget connection`. In Homarr, a Tracearr widget on a board shows its data.
57. **WUD.** http://localhost:3030 (and https://kit-media.<your-tailnet>.ts.net:3030): sign in as admin with `WUD_ADMIN_PASSWORD`. It lists every container; after a check (its watch button), none shows an update it shouldn't: Homarr is only offered v2 releases, and the others only a newer image of the same tag. In Homarr, a What's Up Docker widget shows the same.
58. **Backups.** `backup-media-stack`: tracearr, tracearr-db, tracearr-redis and wud stop for the copy and start again, with no `nothing at` warning. `restore-media-stack` and type `restore`: Tracearr comes back with its owner account and servers.
59. **check-health** lists the kit-tracearr node as connected and its URL answering; `update-all` goes through with the new services.

### Ollama and Open WebUI (milestone 10)

Add both with `./kit add ollama open-webui`. It asks three new questions: the Ollama model, from a numbered list with download sizes (press Return for the one marked suggested; on a 32 GB Mac, 3, `qwen3.5:9b`, a 6.6 GB download), Open WebUI's Tailscale machine name (answer `kit-chat`) and whether it's public (funnel). kit-test can't use your Homebrew, so Ollama comes from its GitHub release.

60. **The install.** "Native apps": `Ollama: downloading it from its GitHub release`, then `✓ Ollama: ~/server/apps/ollama/ollama`. "Compose projects" pins open-webui to a `v0.` release and starts the open-webui project. "Health and jobs" lists `Job ollama: always running`. "Connecting the apps": `Ollama: downloading qwen3.5:9b`, then `✓ Ollama: qwen3.5:9b`, `✓ Open WebUI: its admin is the kit's, and sign-ups are off`, and `Homarr: Open WebUI tile`. "Open" lists Open WebUI at its kit-chat address. A second install changes nothing (`(already downloaded)`).
61. **Ollama.** `ollama list` (from `~/server/bin`) shows the model. `check-health` shows Ollama answering on port 11434. No Ollama icon in the menu bar.
62. **Open WebUI.** http://localhost:3020: sign in as `admin@localhost` with `OPENWEBUI_ADMIN_PASSWORD` (`show-logins webui`). No sign-up page. The model is in the model list; a question gets an answer. Turn on two-factor sign-in (the checklist names where; tell me if that's wrong).
63. **From outside.** On your phone, off Wi-Fi: `https://kit-chat.<your-tailnet>.ts.net` opens Open WebUI's sign-in page.
64. **Restarts.** `pkill -9 -f "ollama serve"`: within a minute it's back (`check-health` says `ollama: running again`).
65. **Backups and updates.** `backup-all` has a `==== open-webui` part without `nothing at` warnings; `restore-open-webui` (type `restore`) brings it back with your chat. `update-all` has `==== ollama` ("up to date") and updates open-webui only to a newer release.
66. **show-logins** lists every app, Open WebUI included.

### Karakeep and RomM (milestone 11)

Add both with `./kit add karakeep romm`. The new questions: Karakeep's Tailscale name (`kit-karakeep`) and exposure (Return: tailnet), whether to tag bookmarks with Ollama's model (Return: on), RomM's name (`kit-romm`) and exposure (Return: tailnet), where games live (Return: `~/Games`), which platforms get folders (Return for the default list), and six optional metadata keys (Return skips each; an IGDB pair if you made one).

67. **The install.** "App settings": `✓ Games: ~/Games (new platform folders: gb gbc gba nes snes n64 genesis psx)`. "Compose projects" pins karakeep, karakeep-chrome, karakeep-meilisearch (`v1.55`), romm (`rommapp/romm:5`) and romm-db (`mariadb:11.8`), and starts both projects. "Connecting the apps": `✓ Karakeep: made its admin account (admin@karakeep.local)`, `Restarting karakeep with its new settings`, `✓ Karakeep: its admin is the kit's, and sign-ups are off`, `✓ Karakeep: an API key for Homarr's widget`, `✓ Karakeep: AI tags from qwen3.5:9b`, `✓ RomM: made its admin account (admin)`, `✓ RomM: its admin is the kit's`, and Homarr's Karakeep and RomM tiles and widget connections (or a warning that this Homarr has no such integration yet). A second install changes nothing and restarts nothing.
68. **Karakeep.** https://kit-karakeep.<your-tailnet>.ts.net: sign in as `admin@karakeep.local` (`show-logins karakeep`). In a private window, the sign-up page says sign-ups are disabled. Save a link: its page and picture appear, then AI tags within a minute (`~/server/logs/ollama.log` shows `POST "/v1/chat/completions"` taking a second or two, not a minute). Search finds a word from the page.
69. **RomM.** https://kit-romm.<your-tailnet>.ts.net: sign in as `admin` (`show-logins romm`); no setup wizard. A game file in `~/Games/roms/gba`, then Scan finds it, and Play runs it in the browser.
70. **Platforms.** Add `ps2` to `ROMM_PLATFORMS` in `~/server/answers.conf`, run `./kit install`: `new platform folders: ps2`. Taking a platform off the list leaves its folders.
71. **Homarr.** Both tiles are green; a Statistics widget on a board (+ → Add widget → Statistics), with the Karakeep or the RomM integration, shows its numbers.
72. **Backups and updates.** `backup-all` has `==== karakeep` and `==== romm` parts without `nothing at` warnings, and romm's has no `resources`. Delete the bookmark and `restore-karakeep` (type `restore`): it's back. The same for the game with `restore-romm`. `update-all` keeps RomM on 5.x.
73. **Disable and add again.** `./kit disable karakeep`, then `./kit add karakeep`: the bookmarks are there, and no second admin is made.

### Install output

74. **The summary and the to-dos.** Any `./kit install` ends with a box: the time it took, how many new things, restarts, warnings (repeated in yellow), and the counts of apps to open and to-dos. Colors only in Terminal. "Still to do" lists only the steps not done yet: in kit-test, with Prowlarr's indexers, Seerr, Homarr's setup page, Plex and its libraries done, those lines are gone; automatic login stays unless kit-test logs in by itself; RomM's line is gone once a scan found a game. "Good to know" shows only on a run that adds a module. `./kit status` shows the same to-dos.

### One media mount and external drives (milestone 12)

Run on the M11 account as it is (its Sonarr and Radarr still use `/tv` and `/movies`), with a
series in Sonarr and a movie in Radarr added before the new repo goes in. The drive is a disk
image (`hdiutil create -fs HFS+`), which mounts under `/Volumes` like a real one and can be
"unplugged" with `hdiutil detach`. The steps are in `/Users/Shared/kit-test-m12.md`.

75. **The move to /data.** `./kit install` says Sonarr and Radarr are moving their library from `/tv` and `/movies` (the files stay), that the series and the movie are under `/data/TV Shows` and `/data/Movies`, that the old root folders are removed, and that qBittorrent's folders are `/data/Downloads/...`. In Sonarr and Radarr, Settings → Media Management lists only the `/data` root folder, the series' and the movie's paths start with `/data/`, and System → Status has no missing-root-folder warning. Seerr → Settings → Services shows `/data/...` for both. `docker inspect sonarr --format '{{range .Mounts}}{{.Destination}} {{end}}'` lists only `/config` and `/data`. A second install moves nothing.
76. **Hardlinks.** `check-health` has `✓ Hardlinks: Downloads and Movies are one disk to the apps`.
77. **A drive.** With `~/Media` moved onto the disk image and linked back (docs/external-drive.md), `./kit install` shows `Folders: ~/server, ~/Media (→ /Volumes/KitDrive/Media)`, `runtime.conf` has `VOLUMES_media_stack='/Volumes/KitDrive'`, `check-health` has `KitDrive NN% free`, `~/server/kit/glances.conf` still has only `show=/System/Volumes/Data`, and the Mac Host Info widget still shows one disk (DISK).
78. **The drive missing.** With the image detached: restarting sonarr fails (the bind source is missing) and nothing appears under `/Volumes`; `check-health` fails with `KitDrive not mounted`; `update-project media-stack` refuses. After `orb restart docker`, the media stack's containers stay stopped; attaching the image again and running `wait-volumes` starts them.
80. **A real restart.** A disk image doesn't come back by itself after a restart, so this step uses a real USB drive (APFS or Mac OS Extended): move `~/Media` onto it in place of the image, as in step 77, and run `./kit install`. (a) Restart the Mac with the drive plugged in and log in to kit-test, typing nothing else. Within a few minutes `check-health` is all green: the media stack's containers are running, and `~/server/logs/wait-volumes.log` says `Started media-stack (its drive is mounted)` (or nothing at all, if OrbStack started the containers after the drive mounted). Plex and Jellyfin show their libraries. (b) Unplug the drive, restart, and log in. The media stack's drive containers stay stopped. `~/server/logs/plex.log` and `jellyfin.log` end with `Waiting for /Volumes/<drive> to be mounted before starting`, and `check-health` says Plex and Jellyfin are waiting for their library's drive, with no kickstart advice. Plug the drive in: within a minute those containers are running, Plex and Jellyfin start and show their full libraries, and `check-health` is green.
81. **Backup copies.** `./kit status` has an "External backup copies" section saying they're off, then (with `BACKUP_DRIVE=/Volumes/KitDrive` and a `backup-all`) the last copy and that it worked, into `/Volumes/KitDrive/<this-mac>-backups`.
82. **The forwarded port** (ProtonVPN). `check-health` has `✓ qBittorrent listens on Gluetun's forwarded port (N)`. (a) Set qBittorrent's listening port to something else in Settings → Connection, run `check-health`: it fails with `qBittorrent listened on port M, not Gluetun's forwarded port N: set it to N`, qBittorrent shows N again, and `~/server/logs/health/fixes.log` has the change. At the next `log-health` sample an ntfy alert names both ports, and the one after says recovered. (b) `docker restart gluetun qbittorrent` (both, in that order: qBittorrent runs on Gluetun's network): Gluetun's log shows the up command's wget retrying until qBittorrent answers (or giving up after about 3 minutes), the port keeps being renewed meanwhile (no `port forwarding` errors in Gluetun's log), and `check-health` is green within 10 minutes, with no alert. (c) `docker restart gluetun` alone (as when Gluetun crashes): qBittorrent stays on Gluetun's old network, so its web UI on this Mac drops the connection. The next `check-health` fails with `qbittorrent was cut off: gluetun restarted … ago and qbittorrent stayed on its old network. Restarted qbittorrent`, `fixes.log` has it, the web UI answers again, and within 10 minutes the port is in sync.

### The plan (`--plan`)

The test account's install, now looked at before anything changes, plus a stand-in for an older
stack. Step by step in `/Users/Shared/kit-test-plan.md`.

83. **The plan.** (a) On the installed account, `./kit install --plan` ends with `Plan · N to do · nothing to check first` and `Plan only: nothing was changed. (macOS's sandbox kept it from writing any file.)`; the Start section lists every service as Unchanged, and Connecting the apps has only "(already set)" and "(already there)" lines. `find ~/server ~/Library/LaunchAgents -newer <a file touched just before> | wc -l` says 0, and no container's Created time changed (`docker ps --format '{{.Names}} {{.CreatedAt}}'` before and after). (b) With `TIMEZONE=Europe/London` added to answers.conf and sonarr's line deleted from `~/server/media-stack/images.lock`, the plan shows `.env`'s TIMEZONE line changing, `Pull lscr.io/linuxserver/sonarr:latest for sonarr`, `Recreate sonarr (pinned to ...)` and the services using TIMEZONE as recreated, and either "is the image it runs now" or "is newer" for sonarr. Undo both edits. (c) `./kit add romm --plan` says `MODULES=romm for this plan only`, `Create romm (rommapp/romm:5)` and `Create romm-db`, and answers.conf's `MODULES=` hasn't changed. (d) An older stack: `docker run -d --name oldsonarr -p 127.0.0.1:8990:8989 -v ~/old-sonarr:/config lscr.io/linuxserver/sonarr:latest`, then `docker rename sonarr sonarr-kit && docker rename oldsonarr sonarr` (so the old one has the kit's name): the plan flags `a container named sonarr already exists (not made by Compose ...)` and that `/config would come from ~/server/appdata/media-stack/sonarr ... instead of ~/old-sonarr`. Rename back and remove the old one. (e) `mkdir -p ~/Games/gba/roms` with `romm` in MODULES (or `./kit add romm --plan`): the plan flags RomM's Structure B, and `~/Games/roms` doesn't appear.

## When you're done testing

Between milestones, keep the account: in kit-test, quit Plex (`osascript -e 'quit app id "com.plexapp.plexmediaserver"'`; stopping its job alone leaves Plex's helper processes behind), then stop the kit's jobs, so stopping the stack doesn't alert and Jellyfin and Glances stop too (`launchctl bootout gui/$(id -u)/io.github.andy327.mac-server-kit.log-health`, and the same for `.backup-all`, `.plex`, `.jellyfin`, `.ollama` and `.glances`; the next `./kit install` loads them again), then stop the stacks (`cd ~/server/media-stack && docker compose down`, and the same in `~/server/open-webui`) and quit OrbStack once it has finished (quitting OrbStack during `down` leaves some containers behind, and they start again with OrbStack: run `docker compose down` again next time). Pause the test check on Healthchecks.io, or it alerts once it stops hearing from the Mac. For a fresh run next time, also `rm -rf ~/server ~/Media` there, and remove the `kit-media`, `kit-dashboard`, `kit-jellyfin`, `kit-tracearr` and `kit-chat` machines in the Tailscale admin console (a fresh run logs them in again).

For good:

- In kit-test: OrbStack → Quit, then log out.
- In your own account: System Settings → Users & Groups → select kit-test → Delete User → **Delete the home folder**. That removes everything the kit made. Once you're done testing for good (not between milestones: each run reuses them), revoke the test WireGuard configuration in your ProtonVPN account and the test auth key in Tailscale (Settings → Keys), remove the `kit-media`, `kit-dashboard`, `kit-jellyfin`, `kit-tracearr` and `kit-chat` machines, and delete the test check on Healthchecks.io.
- Remove the shared copy:

  ```bash
  rm -rf /Users/Shared/mac-server-kit
  ```
