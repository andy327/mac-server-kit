# Security policy

## Supported versions

Only the latest commit on `main` is supported. Fixes land there; there are no release branches.

## Reporting a vulnerability

Please don't open a public issue for a security problem. Report it privately through GitHub:
[**Report a vulnerability**](https://github.com/andy327/mac-server-kit/security/advisories/new)
(the repository's Security tab → Advisories → Report a vulnerability).

Include what you found, how to reproduce it, and what an attacker could do with it. You should
hear back within a week. Once a fix is on `main`, the advisory is published with credit to you
unless you'd rather stay anonymous.

## Scope

In scope: the kit's own scripts and what they generate, for example

- secrets or logins written somewhere readable by other users, or leaked into logs or backups
- an app exposed through Tailscale Funnel before its login or sign-up settings are in place
- Funnel, serve or firewall settings that publish more than the docs say they do
- shell injection through answers, secrets, module files or API responses

Out of scope: vulnerabilities in the apps the kit installs (Plex, Jellyfin, the arrs, Homarr,
Tailscale, OrbStack and the rest). Report those to their own projects. If the kit pins or
configures one of them in a way that makes it worse, that is in scope.

## Before you share logs or files

Answers files, secrets files, `~/server/kit/generated-secrets.conf`, `show-logins` output and
backups hold passwords and keys. Leave them out of reports, or mask the values.
