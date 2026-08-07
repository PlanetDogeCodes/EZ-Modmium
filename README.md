# EZ-Modmium

A fork of [Modmium](https://github.com/CrOSmium/modmium) with a focus on making it easier to install, safer to run, and less painful to maintain. All credit for the original project goes to the [CrOSmium](https://crosmium.dev) and [crosbreaker](https://crosbreaker.com) teams — this is just a community fork that builds on their work.

Modmium itself is a ChromeOS modification that lets you run an unrestricted device on a managed Chromebook while still reporting as verified in the Google Admin Console. EZ-Modmium keeps all of that intact and adds quality-of-life improvements on top.

## What's different from upstream

- **Shared helper library** (`libmodmium.sh`) — kills the copy-pasted code across `modmium.sh`, `build-image.sh`, and `update-modmium.sh`. One source of truth for colors, prompts, logging, partition helpers, etc.
- **Centralized config** (`modmium.conf`) — override URLs, version thresholds, GBB flags, board lists without editing scripts.
- **`--dryrun`** — run every check (WP, APROV, disk space, URL resolution) without flashing anything.
- **`--yes`** — non-interactive mode for fleets and CI.
- **`--selftest`** — built-in unit tests for the helper functions.
- **`--status`** — read-only device status report (version, branch, DevFW, WP, kernver, backups, install state).
- **`--uninstall`** — guided clean revert (restores firmware backup, clears FWMP + VPD).
- **`--resume`** — resume an interrupted install from the last completed phase.
- **SHA-256 verification** of firmware backups after writing (catches faulty USBs).
- **Mode-aware file permissions** instead of blanket `chmod 777`.
- **stdlib-only `stream.py`** — no more `pip install requests` at install time.
- **Download integrity verification** — checks SHA-256 manifests for `data.json` and recovery images.
- **Policy presets** — one-click JSON presets for common configurations (unlock-developer, max-privacy, gac-friendly, gaming-steam).
- **Policy search** — fuzzy search across all device policies in the editor.
- **Auto-detect screen resolution** for bootsplash (`--resolution auto`).
- **Prebuilt recovery images via CI** — GitHub Actions builds images for 12 popular boards on every release tag.
- **3 rounds of bugfixes** — 54+ bugs found and fixed across the codebase, including 8 critical brick-prevention fixes.
- **SIGINT/SIGTERM traps** — Ctrl+C during flashing cleans up properly instead of leaving the device in a half-written state.
- **cgpt order reversal** — promotes the new kernel *before* demoting the old one, so a cgpt failure doesn't leave you with no bootable kernel.

## Getting started

### Option A — Build a recovery image

```bash
git clone https://github.com/PlanetDogeCodes/EZ-Modmium -b stable && cd EZ-Modmium
./tools/install-deps.sh --with-bootsplash --bootstrap-vboot
sudo ./build-image.sh -b <your-board> -v <version> --dryrun   # pre-flight
sudo ./build-image.sh -b <your-board> -v <version>
sudo dd if=modmium.bin of=/dev/sdX bs=4M status=progress conv=fsync && sync
```

### Option B — VT2 install (no build required)

```bash
# On the Chromebook, developer mode, connected to Wi-Fi:
cd /usr/local; curl -LOsk modmium.dev/modmium.sh && bash modmium.sh   # stage 1
# ... reboot ...
cd /usr/local; bash modmium.sh                                         # stage 2
```

See [EZ-INSTALL.md](EZ-INSTALL.md) for the full quickstart, or [EZ-Modmium.md](EZ-Modmium.md) for the comprehensive guide.

## All the flags

```
modmium.sh:
  -u, --userkeys        Use your own signing keys from a USB
  -b, --backup          Create a firmware backup (default: true)
  -n, --dryrun          Run all checks, flash nothing
  -T, --selftest        Run built-in unit tests and exit
  -y, --yes             Auto-accept all prompts (non-interactive)
  -c, --config <file>   Load a modmium.conf overriding defaults
  -s, --status          Show device status and exit (read-only)
  -U, --uninstall       Clean revert: restore stock firmware + clear FWMP/VPD
  -f, --force           With --uninstall: skip firmware restore
  -r, --resume          Resume an interrupted install
  -h, --help            Show this help

build-image.sh:
  -b <board> -v <version>   Autobuild (downloads image for you)
  -i <path>                 Use a local recovery image
  -u, --userkeys            Generate random signing keys
  -j <path>                 Bundle enterprise policy JSON
  -s, --bootsplash          Convert SVG bootsplashes to PNG (needs inkscape)
      --resolution WxH      Bootsplash resolution (or 'auto' to detect)
  -n, --dryrun              Validate without building
  -h, --help                Show help
```

## Configuration

Copy `modmium.conf` to any of these locations to override defaults:

| Location | Scope |
|---|---|
| `/etc/modmium/modmium.conf` | System-wide (on-device) |
| `~/.config/modmium.conf` | Per-user |
| `./modmium.conf` | Per-project |

## Documentation

| File | What's in it |
|---|---|
| [EZ-INSTALL.md](EZ-INSTALL.md) | Quickstart (1 page) |
| [EZ-Modmium.md](EZ-Modmium.md) | Full guide (12 parts) + source code improvement suggestions |
| [CHANGELOG-EZ.md](CHANGELOG-EZ.md) | Every change vs upstream |
| [BUGFIX-REPORT.md](BUGFIX-REPORT.md) | Full bug audit reports (54+ bugs with root causes) |
| [docs/](docs/) | Original upstream Modmium docs |

## Credits

EZ-Modmium is built on [Modmium](https://github.com/CrOSmium/modmium) by:
- **mariahscarycarey** — image builder, device policy editor, ChromeOS version switcher
- **dmd** — MOSH/libmosh, devfw, chromeos-setdevpasswd, ChromeOS updater
- **lxrd** — policy-test-tool, streaming ChromeOS updates, Nix integration
- **codenerd87** — MPkeys restoration, devfw on geralt, firmware manager
- **kxtzownsu** — code review
- **xz8f** — custom bootsplashes
- **con** — emotional support + minor bugs
- **Casper1051, Moonstone, pilgorr** — default bootsplashes
- **pers5124, dinonuget_, spacenerd1235, xmb9** — private beta testers

EZ-Modmium's refactor, hardening, and feature additions are by the community fork.

## Support

- **Issues:** [github.com/PlanetDogeCodes/EZ-Modmium/issues](https://github.com/PlanetDogeCodes/EZ-Modmium/issues)
- **Upstream Modmium support:** [crosbreaker Discord](https://discord.crosbreaker.com) (please don't report EZ-Modmium-specific issues there)

## License

Same as upstream Modmium — see [LICENSE](LICENSE).
