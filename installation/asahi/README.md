# installation/asahi/

The first boot of an Apple Silicon Mac. A Mac cannot boot an ISO first: the
Asahi installer runs in macOS, makes room, sets up the boot chain and lays down
an OS image. Ryoku's OS list offers two entries:

- **Ryoku on Fedora Asahi Remix 44 Minimal** uses the official Fedora image,
  unchanged, plus one extra package. Ryoku ships no Fedora image of its own,
  which keeps it clear of the Fedora Remix trademark conditions that retired
  the Fedora ISO.
- **Ryoku on Arch Linux ARM** is Ryoku's own image (`image/`): the signed Arch
  Linux ARM tarball with the asahi-alarm kernel and boot chain on a btrfs root,
  and the same first-boot setup built in.

## How a first boot goes

1. Fedora: the Asahi installer copies the entry's `extras` to the EFI partition
   (`/boot/efi/asahi/extras/`), and Fedora's `asahi-extras-firstboot.service`
   installs every RPM there, offline: `ryoku-asahi-firstboot`
   (`fedora/packages/rpm/ryoku-asahi-firstboot.spec`). Its `%post` disables
   `initial-setup` and starts `ryoku-firstboot.service`.
   Arch Linux ARM: the image already has the package
   (`release/packages/ryoku-asahi-firstboot/`) and the service enabled.
2. `ryoku-firstboot.service` runs `ryoku-firstboot-session` on tty1.
3. The session starts `ryoku-tui` in its preinstalled variant (`asahi` or
   `asahi-alarm`) on the kernel console: keyboard, locale, time zone, network,
   desktop choices, Apps & tools, hostname and the accounts, then Review
   (`installation/tui/README.md`).
4. The wizard hands its answers to `ryoku-firstboot-install`, which sets the
   running system up and installs the desktop with `ryoku-shell-install` as the
   administrator, from the branch in `/usr/share/ryoku-asahi/ref`. Unticked
   apps reach it as `--without`, so it leaves them out, records them for the
   doctor and hides them, as an ISO install does.
5. Setup disables the service and the wizard reboots into SDDM.

Leaving the wizard before setup finishes brings it back: until then the Mac has
no account to log in with. The Arch Linux ARM image has no `alarm` account and
a locked root; the wizard creates the only logins.

## Files

| File | Job |
| --- | --- |
| `ryoku-firstboot.service` | Takes tty1 from `initial-setup` and `getty@tty1` until setup is done. |
| `ryoku-firstboot-session` | Starts the wizard with this backend and restarts it until setup finishes. |
| `ryoku-firstboot-install` | The backend: system settings, accounts, desktop, finish, with dnf or pacman by variant. |
| `image/build.sh` | Builds the Arch Linux ARM image: verifies the tarball, runs `setup.sh` in it, packs the btrfs root and the EFI tree into the installer's zip. |
| `image/setup.sh` | Runs inside the image root: asahi-alarm repository, kernel, m1n1, GRUB, fstab, accounts, the first-boot package. |
| `installer-data` | Writes each edition's OS list entry, and merges the entries into one `installer_data.json`. |
| `publish-os-list` | Uploads one edition's entry and rebuilds the channel's OS list from all of them. |
| `bootstrap.sh` | The macOS entry point: Asahi's `bootstrap-prod.sh` with Ryoku's OS list, a pinned and checked installer release, and no install report. |

## Publishing

Each edition publishes its own entry to `asahi/<channel>/os-list/`, and
`publish-os-list` rebuilds `asahi/<channel>/installer_data.json` from all of
them, so neither publish drops the other:

- The Fedora publish workflow builds `ryoku-asahi-firstboot` on its aarch64 leg
  and, after the Fedora 44 aarch64 repository publishes, writes the Fedora
  entry with the extra pointing at that release's frozen repository.
- `build-asahi-image.yml` builds the first-boot package and the image on an arm
  runner, uploads it to `asahi/<channel>/os/` with its `.sha256`, keeps the
  previous image for installs already under way, and writes the Arch Linux ARM
  entry.

Both upload the channel's bootstrap: stable to `asahi/bootstrap.sh`, testing to
`asahi/testing/bootstrap.sh`, so a testing push never replaces the script stable
runs. A Mac then installs with:

```sh
curl -fsSL https://ryoku-repo.jccr.dev/stable/asahi/bootstrap.sh | sh
curl -fsSL https://ryoku-repo.jccr.dev/stable/asahi/testing/bootstrap.sh | sh
```

To review it first, download `bootstrap.sh`, read it, then run `sh bootstrap.sh`.
A new Asahi installer release needs `PKG_VER` and `PKG_SHA256` bumped there.

`tests/asahi-firstboot-dryrun.sh` dry-runs the backend for both editions and
checks the package stages every library it sources.

## Limits of this first pass

- The wizard runs on the console, not in `cage`: the Fedora extra installs
  before the network is up, so the package needs nothing Minimal lacks.
- The OS list is rebuilt each publish, so the bootstrap cannot pin its checksum;
  the installer it runs is pinned. The image's `.sha256` is not signed yet.
- `initial-setup` may already be on tty1 when the Fedora extra lands; the
  service conflicts with it and takes the console over.
- The Arch Linux ARM image has no snapshot boot yet: GRUB boots `@` only.
