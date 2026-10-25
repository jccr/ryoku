# installation/asahi/

The first boot of an Apple Silicon Mac. A Mac cannot boot an ISO first: the
Asahi installer runs in macOS, makes room, sets up the boot chain and lays down
an OS image. Ryoku's entry in the installer's OS list uses the official Fedora
Asahi Remix 44 Minimal image, unchanged, plus one extra package. Ryoku ships no
Fedora image of its own, which keeps it clear of the Fedora Remix trademark
conditions that retired the Fedora ISO.

## How a first boot goes

1. The Asahi installer copies the entry's `extras` to the EFI partition
   (`/boot/efi/asahi/extras/`).
2. On first boot Fedora's `asahi-extras-firstboot.service` installs every RPM
   there, offline: `ryoku-asahi-firstboot`
   (`fedora/packages/rpm/ryoku-asahi-firstboot.spec`).
3. Its `%post` disables `initial-setup` and starts `ryoku-firstboot.service`,
   which runs `ryoku-firstboot-session` on tty1.
4. The session starts `ryoku-tui` in its `asahi` variant on the kernel console:
   keyboard, locale, time zone, network, desktop choices, hostname and the
   accounts, then Review (`installation/tui/README.md`).
5. The wizard hands its answers to `ryoku-firstboot-install`, which sets the
   running system up and installs the desktop with `ryoku-shell-install` as the
   administrator, from the branch in `/usr/share/ryoku-asahi/ref`.
6. Setup disables the service and the wizard reboots into SDDM.

Leaving the wizard before setup finishes brings it back: until then the Mac has
no account to log in with.

## Files

| File | Job |
| --- | --- |
| `ryoku-firstboot.service` | Takes tty1 from `initial-setup` and `getty@tty1` until setup is done. |
| `ryoku-firstboot-session` | Starts the wizard with this backend and restarts it until setup finishes. |
| `ryoku-firstboot-install` | The backend: system settings, accounts, desktop, finish. |
| `installer-data` | Writes the Asahi installer OS list: the Asahi project's Minimal entry, renamed, with the first-boot RPM as its extra. |
| `bootstrap.sh` | The macOS entry point: Asahi's `bootstrap-prod.sh` with Ryoku's OS list, a pinned and checked installer release, and no install report. |

## Publishing

The Fedora publish workflow builds `ryoku-asahi-firstboot` on its aarch64 leg.
After the Fedora 44 aarch64 repository publishes, it writes
`asahi/<channel>/installer_data.json`, pointing the extra at that release's
frozen repository, and uploads `asahi/bootstrap.sh` beside it. A Mac then
installs with:

```sh
curl -fsSL https://repo.ryoku.dev/stable/asahi/bootstrap.sh | RYOKU_CHANNEL=testing sh
```

To review it first, download `bootstrap.sh`, read it, then run `sh bootstrap.sh`.
A new Asahi installer release needs `PKG_VER` and `PKG_SHA256` bumped there.

`tests/asahi-firstboot-dryrun.sh` dry-runs the backend and checks its package
stages every library it sources.

## Limits of this first pass

- The wizard runs on the console, not in `cage`: the extras install before the
  network is up, so the package needs nothing Minimal lacks.
- Apps & tools is left out until the shell installer can remove single apps.
- The OS list is rebuilt each publish, so the bootstrap cannot pin its checksum;
  the installer it runs is pinned.
- `initial-setup` may already be on tty1 when the extras land; the service
  conflicts with it and takes the console over. This needs a real Mac to prove.
