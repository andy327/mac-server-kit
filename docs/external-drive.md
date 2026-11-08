# Media and games on an external drive

The kit keeps media in `MEDIA_ROOT` (default `~/Media`) and RomM's games in `GAMES_ROOT` (default
`~/Games`). Either can live on an external drive. This page covers choosing and preparing the
drive, the two layouts the kit accepts, what the kit does when the drive is missing, and moving an
existing library onto a drive by hand. (A later version of the kit will do the move itself.)

## Formatting the drive

- **A spinning hard drive: Mac OS Extended (Journaled), GUID Partition Map.** Not the
  case-sensitive or encrypted variants: some apps assume case-insensitive names, and an encrypted
  drive won't mount by itself after a restart without someone typing its password.
- **An SSD: APFS.**
- **Never exFAT (or MS-DOS FAT).** It can't hardlink, so every import is a full copy, and it has
  no journal, so an unplugged cable or a power cut can corrupt it.

Why not APFS on a hard drive: APFS spreads a file's pieces and its own metadata around the disk,
which an SSD doesn't mind but a spinning disk does. Listing big folders (what Plex, Jellyfin and
the *arr apps do all day) gets many times slower, and it gets worse as the drive fills, because
APFS can't be defragmented. See Bombich's measurements:
<https://bombich.com/blog/2019/09/12/analysis-apfs-enumeration-performance-on-rotational-hard-drives>
and The Eclectic Light Company's explainer:
<https://eclecticlight.co/2021/11/20/explainer-defragmentation/>.

To format: open **Disk Utility**, choose **View → Show All Devices**, select the drive itself
(the top line, not a volume under it), click **Erase**, and pick the name, **Mac OS Extended
(Journaled)** (or **APFS** for an SSD) and **GUID Partition Map**. Erasing deletes everything on
the drive.

## Before copying anything onto it

1. Turn off Spotlight on the drive, so it doesn't index terabytes of video while you copy:

   ```bash
   sudo mdutil -i off "/Volumes/<Drive>"
   ```

2. Keep the drive spinning: **System Settings → Energy** (or **Battery → Options** on a laptop),
   turn off **Put hard disks to sleep when possible**. A drive that sleeps makes every first
   playback wait, and some apps time out.
3. **Grant access to removable volumes.** macOS asks each app the first time it reads an
   external drive: OrbStack (the containers), Plex, Jellyfin, and Terminal for your own
   commands. On a server without a screen, that question sits unanswered on its display and the
   app simply can't see the files (Plex playback spinning forever while Jellyfin works is the
   typical sign). During setup, keep Screen Sharing open and click **Allow** on every prompt, or
   grant it ahead of time: **System Settings → Privacy & Security → Files & Folders**, and turn
   on **Removable Volumes** for each of those apps.
4. In Plex: **Settings → Library**, turn off **Empty trash automatically after every scan**.
   Otherwise a scan while the drive is missing finds an empty library and removes it all, with its
   watch history. In Jellyfin, don't run library scans while the drive is unmounted.

## Two layouts

Both work; the kit follows whichever it finds.

- **Point the answers at the drive.** `MEDIA_ROOT=/Volumes/<Drive>/Media` (and
  `GAMES_ROOT=/Volumes/<Drive>/Games`) in `~/server/answers.conf`. Simple for a new install.
- **Keep `~/Media` and `~/Games` as symlinks to the drive** (recommended when moving an
  existing install): `~/Media → /Volumes/<Drive>/Media`. The answers stay `~/Media` and
  `~/Games`, so Plex's and Jellyfin's library paths don't change and they don't rescan
  everything. The kit never replaces the links; its containers mount the folder the link leads to.

Either way, the containers that handle downloads and the library mount the media folder once,
at `/data`, so imports on the same drive are hardlinks (instant, no extra space).

## When the drive is missing

- **The install** stops before making anything, and says the drive isn't mounted (or the link
  leads nowhere). It never makes folders under `/Volumes` itself: a folder there would hide the
  drive's mount point and fill the internal disk.
- **Containers** that use the drive won't start without it, rather than starting with an empty
  library. After a restart, the kit's `wait-volumes` job waits up to 30 minutes for the drive,
  then starts them.
- **update-all and restore-*** refuse for a project whose drive is missing; **copy-backups** skips
  a backup drive that isn't plugged in.
- **check-health** fails with "<Drive> not mounted" and how to mount it, and warns as the drive
  fills (under 10% free; a failure under 5%).
- **Plex and Jellyfin** are native apps that the kit's jobs start at login. When the media library
  is on a drive, they wait for it first, with no time limit, so neither starts with empty library
  folders. While one waits, check-health says it's waiting for the drive rather than telling you to
  start it. Once the drive mounts, it starts by itself.

To mount a drive that didn't come up: check its power and cable, then

```bash
diskutil list external
```

```bash
diskutil mount "<Drive>"
```

## Moving an existing library onto the drive (by hand, for now)

1. Open a maintenance window, then stop the stack and the native apps:

   ```bash
   start-maintenance --hours 8 moving media to the drive
   ```

   ```bash
   cd ~/server/media-stack && docker compose stop
   ```

   Quit Plex (or Jellyfin) from its menu-bar icon. With RomM, also
   `cd ~/server/romm && docker compose stop`.
2. Copy everything in Media in one run, so hardlinks between Downloads and the library survive
   (`-H`), then the games:

   ```bash
   rsync -aH ~/Media/ "/Volumes/<Drive>/Media/"
   ```

   ```bash
   rsync -aH ~/Games/ "/Volumes/<Drive>/Games/"
   ```

3. Check the copy: sizes and file counts should match, and a dry run should list nothing left to
   copy:

   ```bash
   du -sh ~/Media "/Volumes/<Drive>/Media"; find ~/Media -type f | wc -l; find "/Volumes/<Drive>/Media" -type f | wc -l
   ```

   ```bash
   rsync -aHn --itemize-changes ~/Media/ "/Volumes/<Drive>/Media/"
   ```

4. Set the originals aside and put the links in their place:

   ```bash
   mv ~/Media ~/Media.old && ln -s "/Volumes/<Drive>/Media" ~/Media
   ```

   ```bash
   mv ~/Games ~/Games.old && ln -s "/Volumes/<Drive>/Games" ~/Games
   ```

   (With the other layout, change `MEDIA_ROOT` and `GAMES_ROOT` in `~/server/answers.conf`
   instead.)
5. Run the install, which mounts the drive's folders and starts everything:

   ```bash
   cd ~/mac-server-kit && ./kit install
   ```

   Open Plex or Jellyfin and play something; run `check-health` (it checks the drive and that
   hardlinks work). Then close the window:

   ```bash
   end-maintenance
   ```

6. After about a week of everything working, delete `~/Media.old` and `~/Games.old`.
