<img src="https://www.modmium.dev/modmiumoutline.png" alt="EZ-Modmium" width="700">

*EZ-Modmium — a community fork of [Modmium](https://github.com/CrOSmium/modmium) by [CrOSmium](https://crosmium.dev) and [crosbreaker](https://crosbreaker.com), focused on ease-of-use, stability, and safety. All credit for the original project goes to the Modmium team.*

**Modmium** is a ChromeOS modification built to allow the freedom of an unrestricted device on a managed device.

**EZ-Modmium** is a drop-in fork that keeps 100% of Modmium's features and adds quality-of-life improvements plus a thorough bug-fix pass (34 bugs fixed, including 8 critical).

## Features (unchanged from Modmium)
* Reports as verified in the Google Admin Console (GAC)
* Allows modification of all policies
* Convenient git updater
* ChromeOS version changer
* Different branches (stable / nightly)
* Custom bootsplashes
* Nix installer (`mix` for APT-like syntax)

## What's new in EZ-Modmium

| Improvement | What it does |
|---|---|
| **Shared library** (`build-utils/libmodmium.sh`) | Single source of truth for colors, helpers, config — eliminates 3-4x duplication. |
| **Centralized config** (`modmium.conf`) | Override URLs, version thresholds, GBB flags, board lists without editing scripts. |
| **`--dryrun`** | Run every check (WP, APROV, disk space, URL resolution) and flash nothing. |
| **`--yes` / `--config`** | Non-interactive mode for fleets/CI. |
| **`--selftest`** | Built-in unit tests for pure helpers (14 tests). |
| **`--help` with examples** | Real usage docs in every script. |
| **SHA-256 backup verification** | Re-reads firmware backup and verifies hash matches. Catches faulty USBs. |
| **Mode-aware permissions** | Replaces blanket `chmod 777` with per-path modes. |
| **stdlib-only `stream.py`** | No more `pip install requests` / venv — uses `urllib.request`. |
| **Structured logging** | Every run logs to `/var/log/modmium/` or `./ez-modmium-build-<ts>.log`. |
| **`tools/install-deps.sh`** | One-command deps for Arch/Debian/Fedora/WSL + `--bootstrap-vboot`. |
| **34 bug fixes** | See [CHANGELOG-EZ.md](CHANGELOG-EZ.md) — 8 critical, 9 high, 9 medium, 8 minor. |

## Critical bugs fixed (highlights)

| Bug | Impact | Fix |
|---|---|---|
| `rm -rf /tmp` in cleanup | Deletes all temp files | Guard with `[[ "$_parent" == /tmp/tmp.* ]]` |
| `flashrom -w` unchecked + `vpd -s` marks DevFW on failure | **Brick on reboot** | Added `\|\| fail` to every flash step |
| `*.v.*` find pattern misses all signing keys | Userkeys backup empty | Fixed to `*.vbpubk`/`*.vbprivk`/`*.vbprik2` |
| `selUserBackup()` called twice | `--userkeys` install always fails | Removed duplicate call |
| `cgpt add` unchecked | Reports "Done!" on failure → won't boot | Added `\|\| fail "DO NOT REBOOT"` |
| `mount` unchecked | Writes to host rootfs on failure | Added `\|\| fail` before file drop |
| kernver hex parsing `$(( 0a<<8 ))` | "value too great for base" → kernver=0 | Use `16#` prefix for base-16 |
| `futility vbutil_kernel --repack` unchecked | Corrupt kernel, build continues | Added `\|\| fail` |

## Getting started

### Option A — Build a recovery image (recommended)

```bash
git clone <this-repo> -b stable && cd ez-modmium
./tools/install-deps.sh --with-bootsplash --bootstrap-vboot
sudo ./build-image.sh -b <your-board> -v <version> --dryrun   # pre-flight
sudo ./build-image.sh -b <your-board> -v <version>             # build
sudo dd if=modmium.bin of=/dev/sdX bs=4M status=progress conv=fsync && sync
```

### Option B — VT2 install (no build required)

```bash
# On the Chromebook (developer mode, connected to Wi-Fi):
cd /usr/local; curl -LOsk modmium.dev/modmium.sh && bash modmium.sh   # stage 1
# ... reboot ...
cd /usr/local; bash modmium.sh                                         # stage 2
```

See **[EZ-INSTALL.md](EZ-INSTALL.md)** for the full quickstart, or **[EZ-Modmium.md](EZ-Modmium.md)** for the comprehensive 12-part guide.

## Documentation

| File | Content |
|---|---|
| [EZ-INSTALL.md](EZ-INSTALL.md) | 1-page quickstart |
| [EZ-Modmium.md](EZ-Modmium.md) | Full guide (12 parts) + source-code improvement suggestions |
| [CHANGELOG-EZ.md](CHANGELOG-EZ.md) | Every change + all 34 bug fixes |
| [BUGFIX-REPORT.md](BUGFIX-REPORT.md) | Full audit report with every bug, root cause, and fix |
| [docs/](docs/) | Original upstream Modmium docs |

## Configuration

Copy `modmium.conf` to `/etc/modmium/modmium.conf`, `~/.config/modmium.conf`, or `./modmium.conf` to override defaults.

## Support

* **EZ-Modmium issues:** open an issue on this fork's repo.
* **Upstream Modmium support:** [crosbreaker Discord](https://discord.crosbreaker.com).
* **Do not** report EZ-Modmium-specific behavior to the upstream team.

## License

Same as upstream Modmium — see [LICENSE](LICENSE).

------------
