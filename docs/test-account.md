# Testing in a separate account

Real installs are tested in a separate macOS user account, `kit-test`, on the M4 MacBook Air, because OrbStack can't run inside a macOS VM (see design.md, Testing). Everything the kit writes goes into that account's home folder, so deleting the account removes it all.

## In your own account

1. **Create the account.** System Settings → Users & Groups → Add User. Choose **Standard**, enter the account name `kit-test`, and give it any full name (for example "Kit Test") and a password.
2. **Quit OrbStack** (menu bar icon → Quit). The stack's ports listen on the whole Mac, and each account runs its own OrbStack.
3. **Copy the repo** to a folder both accounts can read (it brings this document along):

   ```bash
   cp -R ~/src/andy327/mac-server-kit /Users/Shared/
   ```

## In the kit-test account

4. **Log in** and finish the macOS welcome screens.
5. **Open OrbStack** from Applications and finish its first-run steps. If it asks for an admin password for its helper, use your own.
6. **Copy the repo into this account and check the Mac** (in Terminal):

   ```bash
   cp -R /Users/Shared/mac-server-kit ~/ && cd ~/mac-server-kit && ./kit check
   ```

   Everything should be ✓. Under "To do first" it says what's missing, if anything.

7. **Make the answers and secrets files:**

   ```bash
   ./kit prepare --answers-template answers.conf --secrets-template secrets.conf
   ```

   ```bash
   open -e secrets.conf
   ```

   - `WIREGUARD_PRIVATE_KEY`: a real key. Create a new ProtonVPN WireGuard configuration just for testing (account.protonvpn.com → Downloads → WireGuard configuration, NAT-PMP on, a P2P server), so you can revoke it afterwards. Copy the PrivateKey value under [Interface], not the PublicKey under [Peer].
   - `TS_AUTHKEY`: Tailscale isn't used yet, so any value of the right shape works for now: `tskey-auth-test-placeholder`.
   - The optional keys (`HEALTHCHECK_URL`, `NTFY_TOPIC`, `HOMARR_API_KEY`) are commented out, so install asks for them and Enter skips each. To skip them without being asked, uncomment them and leave them empty.

   Then open `answers.conf` (`open -e answers.conf`):

   - Change `MACHINE_ROLE=server` to `MACHINE_ROLE=laptop`, so a later milestone doesn't change the Mac's power settings during a test.
   - Add this line at the end, so native apps from a later milestone install into this account only (the kit ignores it until then):

     ```
     APPS_DIR=~/Applications
     ```

8. **Install:**

   ```bash
   ./kit install --answers answers.conf --secrets secrets.conf
   ```

9. **Run it again.** It should pull nothing, keep every seeded file and leave the containers running:

   ```bash
   ./kit install
   ```

## Checks

10. Open http://localhost:7575 (Homarr) and http://localhost:8080 (qBittorrent opens with **no login** on this Mac).
11. The VPN. The first command should print a VPN address, not your home IP. The second prints the forwarded port (ProtonVPN only):

    ```bash
    docker exec gluetun wget -qO- https://ipinfo.io/ip
    ```

    ```bash
    docker exec gluetun cat /tmp/gluetun/forwarded_port
    ```

12. Memory use, to set the kit's memory warning from a real figure:

    ```bash
    docker stats --no-stream
    ```

13. The containers' state:

    ```bash
    cd ~/server/media-stack && docker compose ps
    ```

Send back the output of both installs and of the checks, especially anything in red.

## When you're done testing

- In kit-test: OrbStack → Quit, then log out.
- In your own account: System Settings → Users & Groups → select kit-test → Delete User → **Delete the home folder**. That removes everything the kit made. Revoke the test WireGuard configuration in your ProtonVPN account.
- Remove the shared copy:

  ```bash
  rm -rf /Users/Shared/mac-server-kit
  ```
