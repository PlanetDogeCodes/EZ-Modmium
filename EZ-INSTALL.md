# EZ-Modmium — Quickstart

The fastest path from zero to a Modmium-equipped Chromebook. Pick **A** or **B**.

---

## Option A — Build a recovery image (~20 min)

### Prerequisites
- A Linux machine (Ubuntu/Debian/Arch/Fedora/WSL all work)
- A Chromebook on ChromeOS ≥ 131
- A USB stick (≥ 8 GB) — **everything on it will be wiped**
- Your board name: `chrome://system` → `CHROMEOS_RELEASE_BOARD`

### Steps

```bash
# 1. Clone EZ-Modmium
git clone <this-repo> -b stable && cd ez-modmium

# 2. Install build deps (one command):
./tools/install-deps.sh --with-bootsplash --bootstrap-vboot

# 3. Pre-flight check (validates flags + deps, builds nothing):
sudo ./build-image.sh -b <your-board> -v <version> --dryrun

# 4. Build the image:
sudo ./build-image.sh -b <your-board> -v <version>
#    Optional: -s --resolution 1920x1080 for custom bootsplash
#    Optional: -j /path/to/policies.json to bundle enterprise policies

# 5. Flash to USB:
sudo dd if=modmium.bin of=/dev/sdX bs=4M status=progress conv=fsync && sync

# 6. On the Chromebook (developer mode, Wi-Fi connected), disable FWMP:
#    Ctrl+Alt+F2 → login as root →
cd /usr/local; curl -LOsk modmium.dev/fwmp.sh && bash fwmp.sh

# 7. Flash DevFW + back up firmware:
cd /usr/local; curl -LOsk modmium.dev/modmium.sh && bash modmium.sh
#    Pick the USB drive when prompted. Reboot when told.

# 8. Recover from the Modmium image:
#    Esc+Refresh+Power → insert modmium.bin USB → recover → reboot

# 9. Return to secure mode, go through OOBE, enroll. Done.
```

---

## Option B — VT2 install (~15 min)

### Prerequisites
- A Chromebook on ChromeOS ≥ 131 in developer mode
- Internet connection on the Chromebook
- A USB stick for the firmware backup (≥ 8 GB, will be wiped)

### Steps

```bash
# On the Chromebook, developer mode, connected to Wi-Fi:
# (do NOT press "Get Started" — just connect Wi-Fi)

# 1. Open VT2:  Ctrl+Alt+F2  (F2 = key to the right of ←, usually → or ↻)
#    Login as root.

# 2. Stage 1 — flash DevFW + back up firmware:
cd /usr/local; curl -LOsk modmium.dev/modmium.sh && bash modmium.sh
#    Pick the USB when prompted. Reboot when told.

# 3. Stage 2 — install Modmium to disk (same command, second run):
cd /usr/local; bash modmium.sh
#    Enter the ChromeOS version (e.g. 138), pick branch (stable), wait.

# 4. Return to secure mode, go through OOBE, enroll. Done.
```

---

## After install: using MOSH

| Action | Keys |
|---|---|
| Open MOSH | `Ctrl+Alt+T` (from a user session) |
| Open VT-MOSH (invisible to extensions) | `Ctrl+Alt+F2` |
| Navigate | Arrow keys or number keys |
| Select | `Enter` |
| Back to main menu | `Exit` or `Ctrl+C` |
| Set a root password | run `chromeos-setdevpasswd` as root |

---

## EZ-Modmium extras (when using the fork's scripts)

```bash
bash modmium.sh --dryrun     # pre-flight: run all checks, change nothing
bash modmium.sh --selftest   # validate helper functions (14 tests)
bash modmium.sh --yes        # non-interactive (auto-accept all prompts)
bash modmium.sh --config /path/to/modmium.conf   # load overrides
bash modmium.sh --help       # full usage + examples
```

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| `FWWP is currently ENABLED` | Disable Write Protect (see [crosmium.dev/HWWP](https://crosmium.dev/HWWP)) |
| `APROV is currently ENABLED` (Ti50) | **Do not reboot.** Run `gsctool -a -I AllowUnverifiedRo:always` |
| Modmium recovery image won't boot | FWMP still set → clear it (see [docs/unbricking.md](docs/unbricking.md)) |
| `bsdtar: command not found` | `sudo apt install libarchive-tools` |
| Black screen on first boot | Powerwash (the installer offers this — say `y`) |
| `Recovery URL not found` | Check board name (lowercase) + version |

**Full troubleshooting + unbricking:** [docs/unbricking.md](docs/unbricking.md) and [EZ-Modmium.md](EZ-Modmium.md).

**Support:** [crosbreaker Discord](https://discord.crosbreaker.com) (upstream).
