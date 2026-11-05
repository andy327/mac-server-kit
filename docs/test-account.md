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

25. **The install's "Health and jobs" section:** the runtime scripts, then `Job log-health: every 5 min`. Under "Connecting the apps": `Healthchecks.io: checked in`, `ntfy: test message sent` (and the message on your phone), and `Homarr: Server health widget`. The second install: `(already loaded)`, `test message sent before`, `(already there)`.
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

Send back the output of both installs and of the checks, especially anything in red.

## When you're done testing

Between milestones, keep the account: in kit-test, stop the health and backup jobs first, so stopping the stack doesn't alert (`launchctl bootout gui/$(id -u)/io.github.andy327.mac-server-kit.log-health` and the same for `.backup-all`; the next `./kit install` loads them again), then stop the stack (`cd ~/server/media-stack && docker compose down`) and quit OrbStack. Pause the test check on Healthchecks.io, or it alerts once it stops hearing from the Mac. For a fresh run next time, also `rm -rf ~/server ~/Media` there, and remove the `kit-media` and `kit-dashboard` machines in the Tailscale admin console (a fresh run logs them in again).

For good:

- In kit-test: OrbStack → Quit, then log out.
- In your own account: System Settings → Users & Groups → select kit-test → Delete User → **Delete the home folder**. That removes everything the kit made. Once you're done testing for good (not between milestones: each run reuses them), revoke the test WireGuard configuration in your ProtonVPN account and the test auth key in Tailscale (Settings → Keys), remove the `kit-media` and `kit-dashboard` machines, and delete the test check on Healthchecks.io.
- Remove the shared copy:

  ```bash
  rm -rf /Users/Shared/mac-server-kit
  ```
