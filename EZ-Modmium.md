# EZ-Modmium

> **The complete, friendly, start‑to‑finish guide to Modmium — written for humans, verified against the real source code.**
>
| Field | Value |
|---|---|
| Based on | Modmium `stable` branch — `docs/*.md` + actual repo source (`modmium.sh`, `build-image.sh`, `libmosh.sh`, `update-modmium.sh`, `features.sh`, `common_modmium.sh`) |
| Minimum supported ChromeOS | **131** (issues about 130‑ and below are closed by upstream) |
| Official upstream docs | <https://github.com/PlanetDogeCodes/EZ-Modmium/tree/stable/docs> |
| Support | [crosbreaker Discord](https://discord.crosbreaker.com) |
| Created by | [CrOSmium](https://crosmium.dev) & [crosbreaker](https://crosbreaker.com) |

---

## Table of Contents

- [Part 0 — What is Modmium? (Read this first)](#part-0--what-is-modmium-read-this-first)
- [Part 1 — Concepts & Vocabulary](#part-1--concepts--vocabulary)
- [Part 2 — Prerequisites & Hardware Prep](#part-2--prerequisites--hardware-prep)
- [Part 3 — Choosing Your Install Path](#part-3--choosing-your-install-path)
- [Part 4 — Path A: VT2 Installation (no build required)](#part-4--path-a-vt2-installation-no-build-required)
- [Part 5 — Path B: Building a Recovery Image](#part-5--path-b-building-a-recovery-image)
- [Part 6 — Path B: Installing from a Recovery Image](#part-6--path-b-installing-from-a-recovery-image)
- [Part 7 — Post‑Install: Using MOSH](#part-7--postinstall-using-mosh)
- [Part 8 — Policy Editors (Device & User)](#part-8--policy-editors-device--user)
- [Part 9 — Troubleshooting & Unbricking](#part-9--troubleshooting--unbricking)
- [Part 10 — Maintenance, Updates & Branches](#part-10--maintenance-updates--branches)
- [Part 11 — Glossary](#part-11--glossary)
- [Part 12 — Suggested Source‑Code Improvements](#part-12--suggested-source-code-improvements)

---

## Part 0 — What is Modmium? (Read this first)

**Modmium is a ChromeOS modification that lets you turn a *managed* (school/work‑enrolled) Chromebook into an effectively unrestricted device, while still *reporting as verified* in the Google Admin Console (GAC).**

In plain terms: your device looks perfectly normal to whoever manages it, but *you* get full control — you can edit any policy, install Linux containers, enable Steam, add local accounts, install packages with Nix, swap the ChromeOS version, and more.

### What it actually does (from the README + source)

| Feature | What it means for you |
|---|---|
| **Reports as verified in the GAC** | The admin console sees a healthy, enrolled device. |
| **Modify all policies** | Edit device *and* user policies via built‑in editors. |
| **Convenient git updater** | `Update Modmium` in MOSH pulls the latest `stable`/`nightly` from GitHub. |
| **ChromeOS version changer** | Switch milestone versions (e.g. 131 ↔ 138) without re‑enrolling. |
| **Branches** | `stable` (recommended) and `nightly` (new features, public beta). |
| **Custom bootsplashes** | Replace the boot logo with one of the bundled SVGs (Casper1051, Moonstone, pilgorr) or your own. |
| **Nix installer** | Install developer packages with Nix — use `mix` for APT‑like syntax. |

### Two ways it gets onto your device

1. **VT2 install** — run a one‑liner from ChromeOS's VT2 console. No build step, but needs internet *every* time and doesn't bundle bootsplashes/policies.
2. **Recovery image** — build a modified recovery `.bin` on a Linux box, flash it to USB, recover the Chromebook from it. Offline‑friendly and fully customizable.

Both paths share the same first stage: **flashing "DevFW"** (developer firmware) so the device will accept resigned kernels and an unverified root filesystem.

### ⚠️ The honest warnings

- **This modifies your device's firmware.** If something goes wrong and you have no backup, recovery can be hard. *Always keep a firmware backup on a USB stick AND in the cloud.*
- **WP (Write Protect) and — on Ti50‑based devices — APROV (AP RO Verification) MUST be disabled before install.** The script refuses to run with WP on. Rebooting with APROV still on *after* WP is off **will brick the device**.
- **Minimum ChromeOS version is 131.** Below that is unsupported and bug reports will be closed.
- **Ethics:** Modmium exists to give device owners freedom over hardware they own. Using it to evade legitimate oversight on devices you don't own or are contractually responsible for may violate policies/laws. You are responsible for how you use it.
- The Modmium devs are volunteers. Be kind in the Discord.

---

## Part 1 — Concepts & Vocabulary

If you're new to ChromeOS internals, read this once. It makes every later step make sense.

| Term | Meaning |
|---|---|
| **Developer Mode** | A boot mode that relaxes ChromeOS's verified‑boot checks. Required before Modmium can do anything. |
| **VT2** | "Virtual Terminal 2" — a full‑screen Linux login shell reachable with `Ctrl+Alt+F2`. Login as `root`. |
| **VT1** | The normal ChromeOS GUI. |
| **MOSH** | "**Mo**dium **Sh**ell" — Modmium's menu‑driven terminal UI, opened with `Ctrl+Alt+T` from a user session. |
| **VT‑MOSH** | The same MOSH, but reachable from VT2. Extensions *cannot* see it (they can see regular MOSH). |
| **WP (Write Protect)** | Hardware + software protection that prevents flashing the firmware ROM. Must be disabled. |
| **HWWP / SWWP** | Hardware WP (physical switch / battery disconnect / CCD) vs Software WP (a flashrom bit). |
| **APROV (AP RO Verification)** | A Ti50‑specific feature that verifies the AP (Application Processor) RO firmware. On Ti50 devices it must be disabled *in addition* to WP. |
| **DevFW (developer firmware)** | A reflashed firmware that uses developer keys and sets GBB flags so resigned kernels boot. Modmium's stage 1. |
| **GBB flags** | "Google Binary Block" flags stored in the firmware. Modmium sets `0xa0b1` to enable dev boot features. |
| **FWMP** | "Firmware Management Parameters" — a TPM‑stored block set during enterprise enrollment that can block developer boots. Must be cleared (Modmium does this automatically during install, but it can come back). |
| **kernver** | A version number baked into the kernel partition and TPM. Modmium reads the current value from TPM index `0x1008` and re‑signs the new kernel with the same version, so upgrades/downgrades don't trip version checks. |
| **rootfs verification (verity)** | A hash tree that makes the root filesystem read‑only. Modmium removes this so files can be modified. |
| **`cros_debug`** | A kernel cmdline flag that enables developer features. Modmium injects it into the kernel config. |
| **cgpt** | The ChromeOS GPT partition editor. Modmium uses it to flip which kernel/root partition (A=2/3 or B=4/5) is active. |
| **Board** | Your Chromebook's codename (e.g. `corsola`, `nissa`, `dedede`, `geralt`). Found in `chrome://system` → `CHROMEOS_RELEASE_BOARD` or `lsb-release`. |
| **Milestone** | The ChromeOS major version number (e.g. 138). |
| **policy‑test‑tool / fake_dmserver** | Google's own tools that Modmium repurposes to serve custom user policies to a logged‑in account. |
| **`mod-files/`** | A rootfs overlay in the repo — every file here is copied onto the ChromeOS rootfs at build/install time. |

---

## Part 2 — Prerequisites & Hardware Prep

### 2.1 What you'll need

| Item | Why | Notes |
|---|---|---|
| A Chromebook on ChromeOS **≥ 131** | Modmium only supports 131+ | Check `chrome://version` |
| Your board name | For building/downloading the right image | `chrome://system` → `CHROMEOS_RELEASE_BOARD` |
| A **USB stick** (≥ 8 GB, disposable) | Firmware backup + (optionally) recovery image | **Everything on it will be wiped.** Don't use one with data you care about. |
| Internet connection on the Chromebook | VT2 install needs it; recovery path only needs it to download the image once | — |
| (Recovery path) A Linux machine | To run `build-image.sh` | Ubuntu/Debian/Arch/WSL all work |
| (Optional) A second USB stick | To hold the built recovery image | — |

### 2.2 Disable Write Protection (WP)

WP **must** be off before running `modmium.sh`. The script checks and refuses to proceed if it's on.

**How WP is disabled depends on your device generation:**

| Generation | How to disable WP |
|---|---|
| **Older devices** (physical WP screw / battery disconnect) | Open the case, remove the WP screw **or** disconnect the main battery, then boot on AC power. |
| **Ti50 / GSC devices** (most Chromebooks from ~2022+) | Open **CCD** (Closed Case Debugging) via the Google Security Chip (gsctool), then disable WP. See [CrOSmium's HWWP guide](https://crosmium.dev/HWWP). |

**The script's own WP logic** (so you know what it's doing):

```
checkWP():
  1. flashrom --wp-status  → if "disabled", OK.
  2. Else, check WP range. If range length is 0x00000000, OK (range allows flashing).
  3. Else, check hardware WP (crossystem wpsw_cur == 0). If HWWP off, try `flashrom --wp-disable` (SWWP).
     - Known issue on ARM boards (corsola, geralt): SWWP disable can fail.
       The script warns and lets you continue since HWWP is off.
  4. If HWWP and SWWP both on with non‑zero range → fail with the HWWP guide link.
```

> 💡 **If you're on a Ti50 board:** after WP is off, also confirm **APROV** is disabled. The script's `checkAPROV()` runs `gsctool -a -I | grep AllowUnverifiedRo` and expects the value to be `Always`. If it's `Never`, **do not reboot** — disable it immediately with:
> ```bash
> gsctool -a -I AllowUnverifiedRo:always
> ```
> Rebooting with APROV on after WP is off **bricks the device**.

### 2.3 Enter Developer Mode

Follow [crosbreaker's developer mode guide](https://docs.crosbreaker.com/quickstart/exploits/misc/developer-mode/). Summary:

1. `Esc+Refresh+Power` → recovery screen.
2. `Ctrl+D` → enable developer mode.
3. Wait for the "OS verification is OFF" screen; press `Ctrl+D` to boot.

You'll see the "OS verification is OFF" warning on every boot — that's normal for developer mode.

### 2.4 (Recovery path only) Prepare your Linux build box

You need the build dependencies. Pick your distro:

**Arch Linux:**
```bash
yay -S --needed acpica coreutils curl jq libarchive pv util-linux vboot-utils wget
yay -S inkscape   # only needed for custom bootsplashes
```

**Debian (requires the `sid` repo for `vboot-utils`):**
```bash
sudo apt update
sudo apt install -y acpica-tools coreutils curl jq libarchive-tools pv sed util-linux vboot-utils wget
sudo apt install -y inkscape   # optional, for bootsplashes
# If bsdtar isn't found (older Debian), alias it:
alias bsdtar=tar
```

**Other distros / WSL:** use the Debian list. If your distro's `vboot-utils` is missing or outdated, compile it from source (next section).

### 2.5 (If needed) Compile `vboot-utils` from source

Only if your distro doesn't ship it, ships an ancient version, or you hit a "manual intervention" error installing it on WSL.

```bash
git clone https://chromium.googlesource.com/chromiumos/platform/vboot_reference --depth 1
cd vboot_reference
make all WERROR=        # WERROR= suppresses intentional warnings on newer compilers
sudo make install
sudo cp -r tests/devkeys /usr/share/vboot/devkeys
```

> ℹ️ The build only really needs `futility` and `vbutil_kernel`. The full test suite will fail unless you install every dependency, but you don't need the tests for Modmium.

---

## Part 3 — Choosing Your Install Path

| | **Path A — VT2** | **Path B — Recovery Image** |
|---|---|---|
| Needs a Linux build box? | ❌ No | ✅ Yes (WSL is fine) |
| Needs internet *at install time*? | ✅ Yes, every time | ❌ No (only at build time) |
| Comes with bootsplashes preinstalled? | ❌ No | ✅ Yes (if built with `-s`) |
| Comes with `policy.json` preinstalled? | ❌ No | ✅ Yes (if built with `-j`) |
| Allows custom modifications? | Limited | ✅ Full control via `mod-files/` |
| Difficulty | Easier | More involved |
| Best for | Quick install, "just make it work" | Power users, offline installs, reproducible builds |

**Recommendation:** If you've never done this before and you have a working internet connection on the Chromebook, **start with Path A (VT2)**. Move to Path B once you're comfortable and want bootsplashes/policy bundling or offline installs.

> ⚠️ **Both paths share stage 1 — flashing DevFW.** Whichever path you pick, the very first thing `modmium.sh` does is flash developer firmware and reboot. Only *after* that reboot does it install Modmium to disk (which is what makes the rootfs writable). Don't skip the reboot.

---

## Part 4 — Path A: VT2 Installation (no build required)

### 4.1 One‑command install

From the ChromeOS **developer mode** boot screen:

1. **Connect to Wi‑Fi** — tap the Wi‑Fi icon in the bottom‑right. Do **not** press "Get Started".
2. Open **VT2** with `Ctrl+Alt+F2`.
   > 💡 `F2` is usually the key **to the right of** the `←` (Back/Left) arrow — typically `→` (Right) or `↻` (Refresh). It varies by device.
3. Log in as `root` (no password by default).
4. Run:
   ```bash
   cd /usr/local; curl -LOsk modmium.dev/modmium.sh && bash modmium.sh <flags>
   ```

### 4.2 What happens on the first run (stage 1 — DevFW)

The script:

1. Clears `FWMP` from the TPM (so developer boots aren't blocked).
2. **Backs up your current firmware** to your chosen USB drive (or a directory).
   - It will *wipe* the USB. Pick "Drive" unless you really know what you're doing.
   - Requires ≥ 16 MB free (it checks).
3. Flashes **DevFW**: replaces firmware keys with developer keys, sets GBB flags `0xa0b1`, writes `dev_firmware=1` to VPD so it won't re‑flash accidentally.
4. Tells you to **reboot**.

> 🔑 **Save that backup in two places.** The script even reminds you: copy the `backup_YYYYMMDD.rom` file off the USB to cloud storage. This is your unbrick lifeline.

### 4.3 Reboot, then run it again (stage 2 — Modmium to disk)

After the reboot you're running DevFW. Run the **same command again**:

```bash
cd /usr/local; curl -LOsk modmium.dev/modmium.sh && bash modmium.sh <flags>
```

This time the script detects `dev_firmware=1` in VPD and runs `modmiumInstall` instead:

1. Asks which **ChromeOS version** to install (numeric milestone, e.g. `138`).
   - Below 131 → warning, must confirm.
2. Asks which **branch** (`stable` or `nightly`). Press Enter for `stable`.
3. Finds the recovery image URL from `crosbreaker/chromeos-releases-data` on jsDelivr.
4. Installs ChromeOS to the *inactive* kernel/root partitions (A↔B), preserving your current boot.
5. Removes rootfs verification, injects `cros_debug`, re‑signs the kernel with the **current kernver** read from TPM index `0x1008` (so no version‑mismatch boot loops).
6. Clones the Modmium repo (`--depth 1 -b <branch>`), copies `mod-files/` onto the new rootfs, drops the architecture‑correct `minioverride.so` into `/lib`.
7. Optionally powerwashes (recommended — prevents blackscreen on first boot).
8. Optionally uninstalls dev packages (`dev_install --uninstall`) for cross‑version compatibility.
9. Flips the active kernel via `cgpt` and reboots.

### 4.4 Return to secure mode & enroll

1. After the final reboot, go through **OOBE** (Out‑Of‑Box Experience) as normal.
2. Enroll into your enterprise domain.
3. That's it — the device reports as verified in the GAC, and you have MOSH available.

### 4.5 Flags

| Flag | Meaning |
|---|---|
| `-u` / `--userkeys` | Use your **own** signing keys (from a USB) instead of the bundled devkeys. Plug the USB in *before* running, **both** times. `--backup` is ignored when this is set. |
| `-b` / `--backup` | Default `true`. Pass `--nobackup` to skip the firmware backup. **Don't** — unless you absolutely know what you're doing. |

> ⚠️ If you run `modmium.sh` while signed into a user session, **eject any USB you're backing up to before running** — otherwise you may hit issues.

---

## Part 5 — Path B: Building a Recovery Image

### 5.1 Clone the repo

```bash
git clone https://github.com/PlanetDogeCodes/EZ-Modmium -b <branch>   # branch = stable or nightly
cd modmium
```

> 📁 **Repo layout** (so you know where things live):
> ```
> modmium/
> ├── bootsplash/        # default bootsplash SVGs (Casper1051, Moonstone, pilgorr)
> ├── build-utils/       # build scripts, signing keys (devkeys + generated userkeys), libs
> │   ├── common_minimal.sh
> │   ├── common_modmium.sh   # color vars, board list, keydir selection
> │   ├── ssd_util.sh         # used to remove verity
> │   ├── keygeneration/      # scripts to create your own signing keys
> │   ├── keys/devkeys/       # the standard developer signing keys
> │   └── lib/                # minioverride.so (x86‑64 + aarch64)
> ├── mod-files/         # ★ rootfs overlay — everything here is copied onto ChromeOS
> │   ├── sbin/chromeos_startup
> │   ├── usr/bin/crosh        # ← this IS MOSH
> │   ├── usr/bin/*‑editor.sh  # policy editors, feature toggles, etc.
> │   ├── usr/lib/libmosh.sh   # shared MOSH TUI library
> │   └── usr/share/.policy-test-tool/   # Google's policy tools, repurposed
> ├── build-image.sh     # the builder
> ├── modmium.sh         # the on‑device installer (also served from modmium.dev)
> └── docs/              # upstream docs
> ```

### 5.2 Run the builder

```bash
# Option 1 — autobuild (downloads the image for you):
sudo ./build-image.sh -b <board> -v <version> [flags]
#   -b   board name (e.g. corsola) — lowercase
#   -v   ChromeOS milestone (e.g. 138)

# Option 2 — use a local image you already have:
sudo ./build-image.sh -i /path/to/image.bin [flags]
```

Run `./build-image.sh --help` (or with no args) to see every flag. The important ones:

| Flag | Meaning |
|---|---|
| `-b <board>` | Board to autobuild for. |
| `-v <version>` | ChromeOS milestone (must be a positive integer; <131 warns). |
| `-i <path>` | Use a local recovery `.bin` instead of downloading. |
| `-k <hex>` | Override kernver (hex, no `0x` prefix, max 2 digits, e.g. `7`). Use if your device is on a higher kernver than the version you're installing. |
| `-u` / `--userkeys` | Generate fresh random signing keys (saved to `build-utils/keys/userkeys/`). **Back these up — if you lose them you can't update/sign again.** If passed alone (no `-b`/`-v`/`-i`), it *only* generates + backs up keys without building an image. |
| `-j <path>` | Path to a `chrome://policy`‑exported JSON — used to install your enterprise's extensions / `OpenNetworkConfiguration` (user, not device). |
| `-s` / `--bootsplash` | Convert SVGs in `bootsplash/<branch>/` to PNGs and bundle them. Requires `inkscape`. You'll be prompted for your screen resolution. |
| `--nobackup` | (With `-u`) skip backing up the generated keys to USB. Don't. |

### 5.3 What the builder actually does

1. **Validates flags** — checks the board is in the known list, version is numeric, kernver is valid hex, json file exists, inkscape is present if `-s`, etc.
2. **Checks dependencies** (`bsdtar file futility jq pv wget`).
3. (If `-u`) **Generates user keys** via `build-utils/keygeneration/*.sh` and backs them up to a USB you select.
4. (If `-s`) **Converts bootsplashes** SVG → PNG at your resolution.
5. (If `-b`/`-v`) **Downloads** the recovery image from `dl.google.com` (URL resolved via jsDelivr‑hosted board data) and unzips it.
6. **Removes verity** — sets up a loop device, runs `ssd_util.sh` to remove rootfs verification on kernel partitions 2 and 4 (and re‑signs miniOS partitions 9/10 on supported boards), injects `cros_debug`, re‑signs kernels with the chosen keys + kernver.
7. **Enables RW mount** on partition 3 and **drops `mod-files/`** onto the rootfs (moving any replaced files to `.old` so they can still be called).
8. Copies the architecture‑correct `minioverride.so`, removes `cr50`/`ti50`/`force_update_firmware` markers (recovery would fail otherwise), writes `.branch`.
9. **Unmounts, detaches the loop device, moves the final image to your CWD.**

Output: a file named `modmium.bin` (or `modmium-<originalname>.bin` if you used `-i`).

### 5.4 Custom modifications (the whole point of Path B)

Anything you drop in `mod-files/` is copied 1:1 onto the ChromeOS rootfs, preserving the path. Examples:

- **Add your GitHub SSH key for root:** put `mod-files/root/.ssh/authorized_keys`.
- **Ship a custom bootsplash:** drop the PNG into `mod-files/bootsplash/` (or build with `-s`).
- **Preinstall enterprise extensions:** build with `-j /path/to/policy.json` (or name it `policy.json` and put it in `mod-files/root/`).
- **Replace a system script:** drop your version at the matching path; the builder moves the original to `.old` so your replacement can still call it (e.g. `mod-files/sbin/chromeos_startup` calls `/sbin/chromeos_startup.old`).

> 💡 The builder already handles `.old` renaming, so you don't need to worry about clobbering originals.

### 5.5 Choosing keys

| | Bundled devkeys (default) | User keys (`-u`) |
|---|---|---|
| Convenience | ✅ Zero setup | ❌ Must generate + back up |
| Security | Shared with everyone using Modmium | ✅ Unique to you |
| Update risk | A future Modmium update can re‑sign with devkeys | You must keep your keys forever; losing them = can't re‑sign |
| Recommended for | Most users | Power users who want a unique trust chain |

If you go with user keys, the builder writes them to `build-utils/keys/userkeys/` **and** backs them up to a USB. Keep that USB safe — you'll need it for every future re‑sign.

---

## Part 6 — Path B: Installing from a Recovery Image

### 6.1 Disable FWMP first (critical)

> ⚠️ **Before flashing the recovery image, FWMP must be disabled.** If it isn't, the Modmium recovery image won't boot.

Boot developer mode (not enrolled — powerwash if needed), open VT2 (`Ctrl+Alt+F2`), log in as `root`, and run:

```bash
cd /usr/local; curl -LOsk modmium.dev/fwmp.sh && bash fwmp.sh
```

### 6.2 Flash the image to USB

Use [crosbreaker's flashing guide](https://docs.crosbreaker.com/quickstart/exploits/misc/flashing-guide/). Quick version (on your Linux box):

```bash
# Identify your USB (carefully!):
lsblk
# Flash (replace /dev/sdX):
sudo dd if=modmium.bin of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

### 6.3 Install DevFW + back up firmware (stage 1)

On the Chromebook, in developer mode, connected to Wi‑Fi, open VT2 and run:

```bash
cd /usr/local; curl -LOsk modmium.dev/modmium.sh && bash modmium.sh <flags>
```

This is the same DevFW stage as Path A. The script:

1. Checks WP and APROV.
2. Asks for a backup destination — **pick the USB drive** (it will be wiped). This is your firmware backup.
3. Flashes DevFW, sets `dev_firmware=1` in VPD.
4. Reboots.

> 🔑 Same rule as Path A: **back up `backup_YYYYMMDD.rom` to the cloud.**

### 6.4 Recover from the Modmium image (stage 2)

After the DevFW reboot:

1. Enter recovery: `Esc+Refresh+Power`.
2. Plug in the **USB that has your `modmium.bin`** on it.
3. Let it recover, then reboot.

### 6.5 Return to secure mode & enroll

1. After the recovery reboot, return to secure mode.
2. Go through OOBE and enroll as normal.
3. You're now running Modmium, reporting verified in the GAC.

> ℹ️ Even in verified (secure) mode, you still have access to VTs and rootfs verification is disabled — DevFW allows resigned kernels and unverified root filesystems.

---

## Part 7 — Post‑Install: Using MOSH

### 7.1 Opening MOSH

From a signed‑in user session: `Ctrl+Alt+T`.

MOSH ("Modmium Shell") is a menu‑driven TUI similar to [Cr3nroll](https://github.com/crosmium/cr3nroll).

| Action | Keys |
|---|---|
| Navigate | Arrow keys **or** number keys |
| Select | `Enter` |
| Back to main menu | `Exit` option **or** `Ctrl+C` |
| New tab | `Ctrl+Shift+T` |
| Close current tab | `Exit` from main menu |
| Close all tabs | `Ctrl+Shift+W` |

> ⚠️ **Extensions can see regular MOSH.** They **cannot** see VT‑MOSH. If you need to do something sensitive, use VT‑MOSH (next section) or disable enterprise extensions via the user policy editor.

### 7.2 VT‑MOSH (extension‑invisible)

From any screen: `Ctrl+Alt+F2`, log in as `root` or `chronos`. Identical menu to regular MOSH but invisible to extensions.

> 💡 `F2` is the key to the right of `←` (usually `→` or `↻`), varies by device.

### 7.3 Set a password (recommended)

By default `root` has no password. Set one to lock down MOSH, VT‑MOSH, and all VTs:

```bash
chromeos-setdevpasswd
```

### 7.4 MOSH menu highlights

| Menu item | What it does |
|---|---|
| **Update Modmium** | Pulls the latest `stable`/`nightly` from GitHub and refreshes `mod-files/`. |
| **Change ChromeOS Version** | Installs a different milestone to the inactive partition, then swaps boot priority. Downgrades warn about data loss. |
| **Swap Boot Priority** | Flips between kernel A and kernel B (use after a version change). |
| **Toggle Enrollment** | Enroll/unenroll. |
| **Add Local Account** | Create a local (non‑managed) user. |
| **Feature Toggles** | See §7.6. |
| **Exit** | Leave MOSH. |

### 7.5 Revert MOSH to plain crosh

If you dislike MOSH or need the stock `crosh`:

```bash
touch ~/.givemecrosh     # run as root
```

Remove the file to restore MOSH.

### 7.6 Feature toggles (`Feature Toggles`)

These flip capabilities the device's policy would normally block. From the source (`features.sh`):

| Toggle | What it does |
|---|---|
| **Chromebook Plus features** | Spoofs the feature‑management device info (`CAMQAg==`) so the full Chromebook Plus feature set (Desks, Borealis, Conch GenAI, Mahi, Orca, Live Caption, etc.) unlocks. Writes `/etc/init/feature-plus.conf` + `chrome_dev.conf` entries, then `restart ui`. |
| **Studio Mic** | Spoofs `lsb-release` to `octopus` (x86_64) or `jacuzzi` (aarch64) so the Studio Microphone feature installs. Backs up `lsb-release` to `.bak` and a timestamped copy first. |
| **System Blur** | Installs `libfakephysmem.so` and adds it to `chrome_dev.conf` to enable the system‑wide blur effect. |

These are reversible — run the toggle again to disable.

### 7.7 Nix & `mix`

Modmium ships a Nix installer so you can pull developer packages. Use `mix` for an APT‑like syntax:

```bash
mix install <pkg>      # install
mix search <pkg>       # search
```

### 7.8 Custom bootsplash

If you built with `-s` (or want to change it later), MOSH's bootsplash modifier (`modify-bootsplash.sh`) converts SVGs from `bootsplash/` into PNGs and installs them. You need `inkscape`.

### 7.9 Disabling VT‑MOSH / critical‑update warnings

| Want to… | Run as `root` |
|---|---|
| Disable VT‑MOSH (force regular MOSH only) | `touch /usr/local/.defaultvt` |
| Completely disable the critical‑update checker (e.g. you're somewhere that flags Modmium URLs) | `touch /root/.iamsecure` |

---

## Part 8 — Policy Editors (Device & User)

Modmium ships **two** policy editors. Both rely on Modmium auto‑injecting `--disable-policy-key-verification` into `/etc/chrome_dev.conf`, which lets us serve modified policies without needing Google's private signing keys.

### 8.1 Device Policy Editor

**How it works:** device policies are signed by a private key and verified with a matching public key. With key verification disabled, we can dump the current device policy to JSON, edit it, and re‑serve the modified JSON.

**Steps:**

0. **Enroll first** — this creates the initial device policies to edit.
1. Open MOSH (`Ctrl+Alt+T`).
2. Find the policy you want (search the [Google policy list](https://chromeenterprise.google/policies) for exact names).
3. Edit it. The editor groups policies into *Restrictions*, *Reporting*, *Enterprise Settings*, *Misc* — these categories are Modmium's own organization, not official.
4. When done: `Ctrl+C` to return to MOSH, then **`Apply Policies`**.

**The policies most people care about** (under *Restrictions* unless noted):

| Policy | Effect |
|---|---|
| `DeviceAllowNewUsers` | Allow adding new accounts (on). |
| `DeviceUserAllowlist` | More specific than above. `*@gmail.com` is usually enough. |
| `DeviceUnaffiliatedCrostiniAllowed` | Enable Crostini (the Linux container/VM). |
| `DeviceBorealisAllowed` | Enable Steam for Chromebook beta (also needs `chrome://flags`). |
| `VirtualMachinesAllowed` | **Required** for Borealis/Crostini. |
| `UnaffiliatedArcAllowed` | Enable Play Store. Works better if you also set user policies. |
| `DeviceOpenNetworkConfiguration` (Enterprise Settings) | May contain `"DisableNetworkTypes": ["VPN"]` and/or `["Cellular"]`. Empty the array (`[]`) to use VPN/mobile data. |

> ⚠️ **Modifying *any* device policy stops new reports to the GAC** — the device will show as offline. Use **`Reset All Changes`** to resume reporting. (The device still reports as *verified*; it just stops sending fresh telemetry.)

### 8.2 User Policy Editor

**How it works:** uses Google's own `policy-test-tool` + `fake_dmserver` to serve custom user policies to a specific account on login. Modmium hardcodes them to be as unrestrictive as possible, but you can edit `mod-files/usr/bin/mosh-upol.sh`.

**Pre‑install (optional, recommended if you want enterprise extensions):**

1. Before installing Modmium, enroll and sign in to your enterprise account.
2. Go to `chrome://policy` (or `chrome://network/#logs`) and **Export** the JSON to your Downloads folder.
3. Either:
   - build with `-j /path/to/policies.json`, **or**
   - name it `policy.json` and place it in `mod-files/root/`.

Extensions installed this way are **not force‑installed** — you can toggle them on/off in `chrome://extensions` like any normal extension. Great if your enterprise has monitoring software that would look suspicious if absent.

**Post‑install steps:**

1. Install and boot Modmium in verified mode, then enroll.
2. *(Optional)* Obtain your policy file after install — see below.
3. Open VT2 at the "Enrollment is complete" screen. **Do not sign in.** (If you did, powerwash and retry.)
4. Navigate to **`Edit User Policies`**.
5. Select **`Run Policy Editor`** and enter your enterprise email when prompted.
6. When the fake device management server starts, go **back to VT1** and **sign in with the same email**.
7. After login, return to VT2 and press `Ctrl+C`.

> Only run **`Reinstall`** if you want to edit policies for a *different* account, or update them for the same account with a new file.

**Obtaining your policy file *after* install (if you skipped the pre‑install step):**

1. Enroll and sign in to your enterprise account.
2. Open `chrome://policy` and **Export** the policy JSON to Downloads (don't rename it).
3. Open VT2 → `Edit User Policies` → `Grab policy.json from Downloads`.
4. If the `Install` menu doesn't appear, double‑check the file is in Downloads and the name is unchanged.
5. Remove the user account completely (or powerwash), then continue with the post‑install steps above.

---

## Part 9 — Troubleshooting & Unbricking

### 9.1 The bricking risk

If you enroll with Modmium and later Modmium gets corrupted to the point it can't boot, **a Modmium recovery image won't boot anymore** because `FWMP` blocks developer images. The fix is to clear FWMP — straightforward *if you have code execution*.

### 9.2 Getting code execution (when bricked)

Thanks to the GBB flags Modmium sets (`0xa0b1`), **shims can be booted with `Ctrl+U`** on the developer‑mode boot screen, regardless of the recovery key — so they work even on keyrolled boards.

1. Download the **shim** for your board from [crosbreaker's DL site](https://dl.crosbreaker.com/).
2. Flash it to a USB ([flashing guide](https://docs.crosbreaker.com/quickstart/exploits/misc/flashing-guide/)).
3. Plug it in, then `Ctrl+U` to boot it.

### 9.3 Clearing FWMP

Once you have a shell, run:

```bash
tpm_manager_client take_ownership
cryptohome --action=set_firmware_management_parameters --flags=0
```

After that, the Modmium recovery image should boot as usual.

### 9.4 Restoring firmware (last resort)

> 🛑 Only if clearing FWMP fails. This restores your **original** firmware backup, returning the device to a "stock" state you can recover normally.

1. Follow §9.2 to get code execution.
2. Plug in a USB containing your `backup_YYYYMMDD.rom` (or `bios*.fd`) firmware dump.
3. Identify the USBs:
   ```bash
   lsblk | grep sd        # usually shim = /dev/sda, backup USB = /dev/sdb
   ```
4. Mount and flash:
   ```bash
   mkdir -p /mnt
   mount /dev/sdX /mnt                 # replace sdX with the backup USB
   flashrom -w /mnt/bios*.fd           # adjust filename if you renamed it
   ```

### 9.5 Emergency Revert (from MOSH)

If you still have MOSH access but need to undo Modmium, use the **Emergency Revert** option in MOSH (`/usr/bin/emergency-revert.sh`). This is the cleanest way to back out without a full recovery.

### 9.6 Common issues & fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Black screen on first boot after install | Stateful partition has stale state | Powerwash (the installer offers this — say `y`). |
| Modmium recovery image won't boot | FWMP still set | §9.3. |
| `Recovery URL not found or invalid` | Board/version not in the releases data, or no internet | Check board name (lowercase), check the milestone exists at [dl.crosbreaker.com/recovery-images](https://dl.crosbreaker.com/recovery-images), check connectivity. |
| `FWWP is currently ENABLED` | WP not disabled | §2.2. |
| `APROV is currently ENABLED` (Ti50) | APROV not disabled | **Do not reboot.** Run `gsctool -a -I AllowUnverifiedRo:always` immediately. |
| `NOT ENOUGH EMPTY SPACE ON DRIVE` | Backup USB too small / wrong device | Use a USB with ≥ 16 MB free (the script checks `df`). |
| Boot loop after version change | kernver mismatch / verity not removed | Re‑sign with `-k` matching your device's kernver; ensure verity removal succeeded. |
| SWWP failed to disable (ARM boards: corsola, geralt) | Known flashrom issue on ARM | HWWP is off, so install can proceed; re‑disable WP when reverting. |
| MOSH visible to extensions | Using regular MOSH | Use VT‑MOSH (`Ctrl+Alt+F2`) or disable extensions via user policy editor. |
| `bsdtar: command not found` (Debian) | Old Debian / missing libarchive-tools | `alias bsdtar=tar` or `sudo apt install libarchive-tools`. |
| Downgrade warning / account sign‑in issues | Downgrading past 140 with accounts present | Remove and re‑sign into accounts after downgrading. |

### 9.7 "I want to fully undo Modmium"

1. Boot a shim (§9.2) or use Emergency Revert from MOSH.
2. Restore your firmware backup (§9.4).
3. Recover with a stock ChromeOS recovery image.
4. The device is back to factory behavior.

---

## Part 10 — Maintenance, Updates & Branches

### 10.1 Updating Modmium

From MOSH: **`Update Modmium`**. It:

1. Asks for the branch (defaults to your current one, read from `/.branch`).
2. Clones `--depth 1 -b <branch>` from GitHub (SSH if `/root/.ssh` exists, else HTTPS).
3. Refreshes `mod-files/` and the policy‑test‑tool files.
4. Updates `/.branch` and syncs.

> ℹ️ Updating Modmium does **not** change your ChromeOS version — use **`Change ChromeOS Version`** for that.

### 10.2 Switching branches (stable ↔ nightly)

Just run `Update Modmium` and pick the other branch. `nightly` gets new features first; `stable` is what most people should run.

### 10.3 Critical‑update warnings

Modmium periodically checks for critical updates and warns you. To **completely disable** the checker (e.g. on a network that flags Modmium URLs):

```bash
touch /root/.iamsecure     # as root, in MOSH
```

### 10.4 Backups — the golden rule

Keep **two** copies of your firmware backup (`backup_YYYYMMDD.rom`):

1. On the original USB (don't overwrite it).
2. In cloud storage / a second USB.

If you used user keys (`-u`), keep **two** copies of the `userkeys/` folder too. Losing them means you can never re‑sign that device's kernels.

### 10.5 Contributing

Modmium accepts PRs — but **never PR into `stable`**. Everything goes through `nightly` first. See [contributing.md](https://github.com/PlanetDogeCodes/EZ-Modmium/blob/stable/docs/contributing.md).

---

## Part 11 — Glossary

| Term | Definition |
|---|---|
| **APROV** | AP RO Verification — Ti50 feature verifying the AP RO firmware. Must be disabled on Ti50 boards. |
| **Board** | Chromebook codename (corsola, nissa, dedede, geralt, octopus, …). |
| **CCD** | Closed Case Debugging — Ti50 debug access used to disable WP/HWWP. |
| **cgpt** | ChromeOS GPT partition tool; flips active A/B kernel. |
| **cros_debug** | Kernel cmdline flag enabling developer features. |
| **DevFW** | Developer firmware — Modmium's stage 1 firmware reflash. |
| **FWMP** | Firmware Management Parameters — TPM‑stored block that can prevent developer boots. |
| **GBB** | Google Binary Block — firmware flags. Modmium sets `0xa0b1`. |
| **GAC** | Google Admin Console. |
| **HWWP / SWWP** | Hardware / Software Write Protect. |
| **kernver** | Kernel version stored in TPM index `0x1008`. |
| **MOSH** | Modium Shell — the TUI, opened with `Ctrl+Alt+T`. |
| **OOBE** | Out‑Of‑Box Experience — the first‑boot setup. |
| **policy‑test‑tool** | Google's tool for testing device/user policies locally. |
| **rootfs verity** | Hash‑tree verification making the root filesystem read‑only. |
| **VPD** | Vital Product Data — firmware‑stored key/value (Modmium uses `dev_firmware`). |
| **VT1 / VT2** | Virtual terminal 1 (GUI) / 2 (root shell, `Ctrl+Alt+F2`). |
| **WP** | Write Protect. |

---

## Part 12 — Suggested Source‑Code Improvements

This section is the second deliverable: **concrete, file‑referenced ways to modify Modmium's source so it's easier to install and use, without losing features or stability.**

Each suggestion notes **what**, **why**, **where** (file + roughly what to change), **effort**, and **risk**. They're grouped by theme. Items marked 🟢 are low‑risk, high‑value "do‑first" wins; 🟡 are medium; 🔴 need careful design.

> All line references are to the `stable` branch as of writing. The goal throughout is **no behavior change for existing users** unless explicitly noted — these are refactor + UX + safety improvements.

---

### Theme A — Kill the duplication (maintainability)

The single biggest source of bugs and "I fixed it in one place but not the other" issues is that the same logic is copy‑pasted across 3–4 files.

#### A1. 🟢 Extract a shared `libmodmium.sh` for common helpers

**What:** Create `build-utils/libmodmium.sh` containing the helpers currently duplicated everywhere, and `source` it from `modmium.sh`, `build-image.sh`, `update-modmium.sh`, `libmosh.sh`, `features.sh`.

**Duplicated today:**
- The **color‑variable block** (`B/G/Y/R/P/N/D/UN/RUN`) — defined in `modmium.sh:24-32`, `common_modmium.sh:4-12`, `libmosh.sh:19-27`, `features.sh` (via tput). 4 copies.
- `get_largest_cros_blockdev()` — in `modmium.sh:319-338` **and** `libmosh.sh:31-50`. Near‑identical.
- `get_booted_kernnum()` / `get_booted_rootnum()` / `opposite_num()` — in `modmium.sh:77-95` **and** `update-modmium.sh:126-144`. Identical.
- `getImageLink()` — in `modmium.sh:37-56` **and** `update-modmium.sh:38-57`. Identical.
- `askBranch()` — in `modmium.sh:58-75` **and** `update-modmium.sh:59-81`. Almost identical (the latter reads `/.branch` for the default).
- The **`dropModFiles` loop** (`find mod-files … cp … chown 0:0 … chmod 777`) — in `modmium.sh:180-194`, `build-image.sh:248-264`, `update-modmium.sh:243-257`. Three copies, each with tiny drift.
- The **dev_install dependency‑install block** — in `modmium.sh:375-385` **and** `update-modmium.sh:17-27`. Identical.
- `fail()` — defined separately in `modmium.sh:9-17`, `build-image.sh:50-54`, `update-modmium.sh:4-11` with *different* cleanup behavior.

**Why:** Today, a fix to e.g. `getImageLink` has to be applied in two files. The `dropModFiles` drift is actively dangerous — the three copies already differ subtly (the build‑image one handles `policy.json`; the install one handles `userkeys`; the update one preserves `/etc/chrome_dev.conf` and `/bootsplash`/`/.branch`). A single parameterized `drop_mod_files <rootmnt> [keydir]` eliminates this.

**Where:** New file `build-utils/libmodmium.sh`. Source it at the top of each script that needs it. For on‑device scripts, install it to `/usr/lib/libmodmium.sh` (it's already a rootfs‑overlay‑friendly path).

**Effort:** ~1 day. **Risk:** Low — pure refactor; add a `--selftest` subcommand that diffs behavior before/after.

---

#### A2. 🟢 Add a `confirm()` helper and replace the ad‑hoc y/N prompts

**What:** A single `confirm "prompt?" [default]` function. Today the codebase has ~15 inline `read -rep ""; [[ $REPLY =~ ^[Yy]$ ]]` blocks.

**Examples to replace:**
- `modmium.sh:108-112`, `modmium.sh:210-217`, `modmium.sh:219-227`, `modmium.sh:235-237`
- `build-image.sh:121-128`, `build-image.sh:233-242`
- `update-modmium.sh:156-163`, `164-173`, `269-277`, `288-298`, `300-308`, `315-317`

**Why:** Inconsistent defaults (some are `y/N`, some `Y/n`), inconsistent matching (some accept `Yy`, some `Yy` + empty), and the double‑tap `askConfirmation` (`modmium.sh:310-317`) confuses users with no explanation.

**Bonus:** Make `askConfirmation` print a one‑line hint ("double‑tap Y to confirm") and accept a `--single` flag for low‑stakes prompts.

**Effort:** ~2 hours. **Risk:** Very low.

---

#### A3. 🟢 Centralize configuration (URLs, board lists, version thresholds)

**What:** A single `modmium.conf` (sourced) holding every magic value.

**Currently scattered:**
- `cdn.jsdelivr.net/gh/crosbreaker/chromeos-releases-data/data.json` — hardcoded in `modmium.sh:38` and `update-modmium.sh:39` and `build-image.sh:377`.
- `modmium.dev/modmium.sh`, `modmium.dev/fwmp.sh`, `modmium.dev/tools/stream.py` — hardcoded.
- The giant `boards="…"` list — in `common_modmium.sh:14`.
- `minios_boards="…"` — `common_modmium.sh:15`.
- Version threshold `131` — hardcoded in `modmium.sh:104`, `build-image.sh:120`, and `libmosh.sh:132`.
- GBB flags `0xa0b1` — `modmium.sh:477, 482`.
- TPM kernver index `0x1008` — `modmium.sh:142`, `update-modmium.sh:200`.

**Why:** Letting users/enterprise admins override the CDN mirror (e.g. to a self‑hosted copy on networks that block jsDelivr) is currently impossible without editing multiple files. Centralizing also makes future changes one‑line edits.

**Effort:** ~3 hours. **Risk:** Low.

---

### Theme B — Installation UX & safety

#### B1. 🟢 Add `--dry-run` and a pre‑flight report

**What:** `modmium.sh --dry-run` runs every check (`checkWP`, `checkAPROV`, disk‑space, board detection, URL resolution) and prints a human‑readable report — but flashes nothing.

**Why:** Right now the first *action* happens after `askConfirmation`, but the user has no structured preview of "here's what I detected, here's what I'll do, here's where your backup will go." A dry‑run report builds confidence and catches mistakes (wrong USB, APROV still on, etc.) before any irreversible step.

**Where:** `modmium.sh` `main()` — split into `preflight()` (checks only) and `execute()` (actions); `--dry-run` stops after preflight.

**Effort:** ~4 hours. **Risk:** Low (read‑only).

---

#### B2. 🟢 Verify the firmware backup after writing it

**What:** After `flashrom -r $BACKUP/backup_$(date).rom` (`modmium.sh:472`), compute a SHA‑256, write it next to the file (`backup.sha256`), and **re‑read + verify** the backup by comparing sizes and a partial hash.

**Why:** A silently‑corrupt backup is worse than no backup — the user trusts it and then can't unbrick. Flashing to a flaky USB is a real failure mode.

**Where:** `flashDevFW()` in `modmium.sh:470-492`.

**Effort:** ~1 hour. **Risk:** Very low.

---

#### B3. 🟡 Make the installer resumable / idempotent

**What:** Today, if the install dies midway (e.g. network drops during `stream.py`), the user is in a half‑written state with no clear recovery path except starting over. Add a state file (`/tmp/.modmium-state`) recording completed phases, and have `modmium.sh` detect + offer to resume.

**Phases** (from `modmiumInstall`/`installCros`):
1. `deps_installed`
2. `image_downloaded`
3. `chromeos_written` (kernel + root to inactive partition)
4. `verity_removed`
5. `modfiles_dropped`
6. `boot_switched`

**Why:** A dropped connection at phase 3 currently means re‑downloading the whole recovery image. Resumability turns a 30‑minute redo into a 2‑minute one.

**Where:** `modmium.sh` `installCros()` — add `save_state`/`load_state` calls at each phase boundary; clear on success.

**Effort:** ~1 day. **Risk:** Medium — must carefully validate that each phase is actually resumable (e.g. the venv + `requests` install is safe to re‑run; the kernel repack is *not* safe to re‑run on a half‑written partition without re‑streaming).

---

#### B4. 🟢 Non‑interactive mode + config file

**What:** `modmium.sh --config /path/to/modmium.conf --yes` reads all answers (branch, version, backup target, powerwash, uninstall‑devpkgs) from a file and skips every prompt.

**Why:** Two huge wins:
1. **Reproducible installs** — fleet operators / anyone installing on multiple devices wants this.
2. The current script can't be automated at all because of `read -rep` prompts scattered throughout.

**Where:** New `getFlags` additions in `modmium.sh`; a `load_config()` that overrides the interactive prompts.

**Effort:** ~4 hours. **Risk:** Low.

---

#### B5. 🟢 Real progress reporting

**What:** Replace the `echo -e "${G}Installing ChromeOS to disk...${N}"` + silent `python stream.py` with a progress indicator. `stream.py` already knows byte counts — pipe them through `pv` (already a dependency!) or emit `\r`‑based percentage updates.

**Where:** `modmium.sh:131` and `update-modmium.sh:185`.

**Why:** "Installing ChromeOS to disk..." with no progress for 10+ minutes looks like a hang. Users power off mid‑install → brick.

**Effort:** ~2 hours. **Risk:** Low.

---

#### B6. 🟢 Don't `chmod 777` every modfile

**What:** Replace `chmod 777 $oldFile` (`modmium.sh:192`, `build-image.sh:262`, `update-modmium.sh:93` *and* `:255` — four places) with mode‑aware logic:
- Files in `bin/`/`sbin/` → `755`
- Files in `etc/` → `644` (config) unless executable
- Libraries (`*.so`) → `755`
- Everything else → `644`, with an opt‑in `+x` marker in the repo (e.g. a `.modmium-exec` sidecar or a `+x` suffix convention).

**Why:** `chmod 777` on system binaries and config files is a security smell — any process can rewrite them. On a device whose entire premise is "looks verified to the admin," world‑writable system files are a needless risk. This is also flagged by every static analyzer.

**Effort:** ~3 hours. **Risk:** Low — but test every modfile still works (some may rely on the 777; audit first).

---

### Theme C — Robustness & error handling

#### C1. 🟢 Add `set -uo pipefail` (not `-e`) and `trap` cleanup everywhere

**What:** None of the scripts use `set -e`/`-u`/`pipefail`. Unset variables silently expand to empty; failed commands in pipes are swallowed. Add at minimum `set -uo pipefail` (avoid bare `-e` because the scripts intentionally check exit codes inline).

**Why:** Several latent bugs:
- `modmium.sh:279`: `crossystem wpsw_cur || grep "0"` — the `|| grep "0"` always succeeds (grep finds "0" in its own output? no — grep with no input returns 1), so the `|| fail` never fires. This is a real logic bug masking WP‑check failures.
- `modmium.sh:272, 280, 286`: the `|| echo "WARNING..." && read -p ...` chain has operator‑precedence issues — the `read` runs even on success.
- `build-image.sh:30-32`: cleanup glob can match unintended dirs.

**Where:** Top of every script + `libmodmium.sh`.

**Effort:** ~1 day (incl. fixing the bugs surfaced). **Risk:** Medium — `set -u` will surface previously‑silent unset vars; fix them as they appear.

---

#### C2. 🟢 Quote all variable expansions; replace `for f in $(find …)` with `find … -exec` or `while read`

**What:** `for file in $(find mod-files -mindepth 1 -name "*")` (`modmium.sh:180`, `build-image.sh:248`, `update-modmium.sh:243`) breaks on any filename with spaces. `cp $file $oldFile` (unquoted) has the same issue.

**Why:** Today, `mod-files/` paths are controlled by the repo, so it "works" — but the moment a user adds `mod-files/root/My Documents/foo` (or a bootsplash with a space), install breaks silently. A `while IFS= read -r -d '' file` loop is strictly safer.

**Where:** The three `dropModFiles` loops (also fixed by A1).

**Effort:** ~2 hours (folded into A1). **Risk:** Very low.

---

#### C3. 🟢 Add structured logging

**What:** Every script writes a timestamped log to `/var/log/modmium/install-<timestamp>.log` (teed to stdout). `fail()` automatically appends the last 20 log lines + phase to the error message.

**Why:** Post‑mortem debugging is currently impossible — users paste a screenshot of the last `echo` to Discord and devs guess. A log file changes "it didn't work" into a fixable bug report.

**Where:** `libmodmium.sh` `log()` + `fail()` wrappers; `modmium.sh`/`build-image.sh` init.

**Effort:** ~3 hours. **Risk:** Low.

---

#### C4. 🟡 Verify downloaded artifacts (image + `data.json` + `stream.py`)

**What:** Three downloads happen with zero integrity checks:
- `data.json` (board→URL map) from jsDelivr — `modmium.sh:40`.
- The recovery image from `dl.google.com` — `build-image.sh:396`.
- `stream.py` from `modmium.dev/tools` — `modmium.sh:130`.

Add:
- A pinned SHA‑256 for `data.json` (or better: a signed manifest the script verifies against a baked‑in public key).
- `wget --checksum` / post‑download `sha256sum` for the recovery image (Google publishes these).
- Ship `stream.py` **in the repo** (it already lives at `mod-files/usr/bin/stream.py`!) instead of re‑downloading it at install time. This removes one network dependency entirely.

**Why:** A compromised CDN or MITM could serve a malicious image/script. The user is running it as root on a device they're about to enroll. Integrity checks are basic hygiene.

**Where:** `modmium.sh:130` (drop the `curl stream.py` — use the bundled copy after the repo is cloned; for the *first* stage before cloning, bundle a minimal copy in the installer itself), `build-image.sh:396`, `modmium.sh:40`.

**Effort:** ~4 hours. **Risk:** Low for image/hash checks; medium for the signed‑manifest design.

---

### Theme D — Dependencies & packaging

#### D1. 🟢 Ship a self‑contained vboot‑utils fallback

**What:** When `vboot-utils`/`futility` is missing on the build host, `build-image.sh` could auto‑compile it from the documented source (§2.5 of this guide) into a local prefix, instead of failing.

**Why:** The #1 build‑setup pain point is the Debian `sid` repo requirement and the WSL "manual intervention" error. A `--bootstrap-vboot` flag that runs the clone‑make‑install automatically removes a whole class of "I can't build it" reports.

**Where:** New `build-utils/bootstrap_vboot.sh` + `checkDependencies()` fallback in `build-image.sh:14-24`.

**Effort:** ~3 hours. **Risk:** Low (only triggers on missing dep).

---

#### D2. 🟢 Drop the runtime `pip install requests`

**What:** `modmium.sh:127-129` and `update-modmium.sh:182-184` create a Python venv and `pip install requests` at install time, just to run `stream.py`.

**Why this is bad:**
1. Slow (venv creation + pip fetch on every install).
2. Needs internet *again* (on top of the image download).
3. `requests` is unnecessary — Python's stdlib `urllib.request` does HTTP range requests fine.
4. Fails on networks that block PyPI.

**Fix:** Rewrite `stream.py` to use `urllib.request` (no external deps) and run it with the system Python directly. Delete the venv code entirely.

**Where:** `mod-files/usr/bin/stream.py` + `modmium.sh:127-132` + `update-modmium.sh:182-186`.

**Effort:** ~2 hours. **Risk:** Low (pure stdlib replacement; test on ChromeOS's bundled Python).

---

#### D3. 🟡 Provide prebuilt recovery images via CI

**What:** A GitHub Actions workflow that, on each `stable` tag, builds `modmium.bin` for the top ~20 boards (corsola, nissa, dedede, geralt, brya, etc.) and publishes them as release artifacts with SHA‑256 manifests.

**Why:** Most users don't want to set up a Linux build box. Today the only "no build" path is VT2, which needs internet at install time and can't bundle bootsplashes/policies. Prebuilt images give the best of both worlds.

**Risk note:** This doesn't change Modmium's behavior — it just distributes the existing build output. User‑keys can't be prebuilt (by design), so `-u` users still build locally.

**Effort:** ~1 day to set up CI; ongoing per‑release. **Risk:** Low (artifacts are reproducible from the same repo+flags).

---

#### D4. 🟢 Package the build dependencies

**What:** Provide an AUR package (`modmium-build-deps`), a Debian `.deb`, and a Fedora `.rpm` that pull in `acpica coreutils curl jq libarchive pv util-linux vboot-utils wget` (+ optional `inkscape`).

**Why:** Turns the multi‑command dependency install (§2.4) into `sudo apt install modmium-build-deps`. Especially helps WSL users.

**Effort:** ~1 day. **Risk:** Very low.

---

### Theme E — MOSH & policy editor UX

#### E1. 🟢 Add policy search to the device policy editor

**What:** `devpolicy-editor.sh` (413 lines) currently groups policies into categories the user must scroll through. Add a `/`‑triggered fuzzy search (by policy name or description) that filters the list live.

**Why:** The Google policy list has *hundreds* of entries. Users today Ctrl+F the web docs, find the name, then hunt for it in MOSH. In‑menu search removes a context switch.

**Where:** `mod-files/usr/bin/devpolicy-editor.sh` + `libmosh.sh` (add a generic `search_filter` helper reusable by other menus).

**Effort:** ~4 hours. **Risk:** Low.

---

#### E2. 🟢 Policy presets

**What:** Ship a `presets/` directory with named JSON presets the user can apply in one action, e.g.:
- `presets/unlock-developer.json` → enables Crostini, Borealis, Play Store, VPN, new users, allowlist `*@gmail.com`.
- `presets/max-privacy.json` → disables reporting, telemetry, etc.
- `presets/gac-friendly.json` → minimal changes that keep GAC reporting alive.

**Why:** The "recommended policies" list in §8.1 of this guide exists because the raw editor is overwhelming. Presets encode that knowledge in the tool itself.

**Where:** New `mod-files/usr/share/modmium/presets/` + a "Load Preset" menu item in `devpolicy-editor.sh`.

**Effort:** ~3 hours. **Risk:** Low.

---

#### E3. 🟢 Auto‑detect screen resolution for bootsplash

**What:** `build-image.sh:297-320` asks the user to type their resolution. Read it instead: on the Chromebook, `crossystem` / `ectool` / `/sys/class/drm/*` expose it; on the build host, accept a `--resolution WxH` flag or read from a board database.

**Why:** Users frequently typo the resolution (the script validates numeric but not plausibility), producing stretched bootsplashes.

**Where:** `bootsplash()` in `build-image.sh`.

**Effort:** ~2 hours. **Risk:** Low.

---

#### E4. 🟢 Add `--help` everywhere with examples

**What:** `modmium.sh` has no `--help` (shflags provides a bare usage but no examples). `build-image.sh` has `FLAGS_HELP` but it's minimal.

Add real help text like:
```
EXAMPLES:
  # First run (flash DevFW + back up to /dev/sdb):
  bash modmium.sh

  # Second run (install Modmium stable, ChromeOS 138):
  bash modmium.sh   # then answer prompts, or:
  bash modmium.sh --branch stable --version 138 --yes

  # Use your own signing keys:
  bash modmium.sh -u
```

**Where:** `modmium.sh` `main()` + a `usage()` function; `build-image.sh` `getFlags()`.

**Effort:** ~2 hours. **Risk:** Zero.

---

### Theme F — Testing & CI

#### F1. 🟡 Add ShellCheck + `shunit2` CI

**What:** A `.github/workflows/lint.yml` that runs ShellCheck on every `.sh` with `-x` (allow exported vars) and fails on warnings. Plus `shunit2` tests for the pure functions (`opposite_num`, `get_booted_kernnum` logic, the kernver‑from‑TPM byte parser in `modmium.sh:145-157`, URL resolution).

**Why:** The byte‑parsing block at `modmium.sh:145-157` (inspired by Aurora) is exactly the kind of code that silently breaks on an edge case. A unit test with known TPM byte sequences would have caught the `bytes[0]` branching logic regressions.

**Where:** New `.github/workflows/` + `tests/` directory.

**Effort:** ~1 day to set up + write initial tests. **Risk:** Zero (CI only).

---

#### F2. 🟢 Add a `modmium.sh --selftest`

**What:** A mode that exercises every pure helper (color output, `opposite_num`, the byte parser, `get_largest_cros_blockdev` against fixture `/sys/block` trees) and prints PASS/FAIL. Users run it post‑install to confirm their build is healthy.

**Why:** Turns "is my install okay?" from a guess into a command.

**Effort:** ~3 hours (depends on F1). **Risk:** Zero.

---

### Theme G — Documentation

#### G1. 🟢 Generate docs from the scripts

**What:** Each script gains a `## HELP` heredoc; a `tools/gen-docs.sh` extracts them into `docs/` Markdown. The `--help` output and the docs are then guaranteed in sync.

**Why:** Today, `docs/` and the scripts drift (e.g. `docs/building.md` doesn't mention `-s`/`--bootsplash` or `-j`/`--json`; you have to read the source). Generation removes the drift.

**Effort:** ~4 hours. **Risk:** Zero.

---

#### G2. 🟢 Add a `docs/quickstart.md` (this guide, condensed)

**What:** A 1‑page "I just want it working" quickstart that mirrors Part 4 of this guide, linked prominently from the README.

**Why:** The current README links to `building.md` and `installation.md` but a new user has to read 4 files to piece together the flow. A single quickstart is the #1 documentation ask for tools like this.

**Effort:** ~2 hours. **Risk:** Zero.

---

### Theme H — Summary: the "if you only do 5 things" list

If the Modmium team had a single weekend, the highest leverage changes are:

1. **A1** — extract `libmodmium.sh` (kills the 3‑way `dropModFiles` drift, the #1 bug source).
2. **B6** — stop `chmod 777`‑ing system files (security).
3. **C4 + D2** — verify downloads + drop `pip install requests` (security + reliability + offline‑friendliness).
4. **B1 + B4** — `--dry-run` + non‑interactive config mode (UX + fleet use).
5. **F1** — ShellCheck CI (prevents regressions forever).

All five are low‑to‑medium risk, preserve 100% of existing features, and materially improve installability and stability.

---

### Closing note on stability

Every suggestion above is **additive or refactor‑only** — none change what Modmium *does* to the device, only how the code is organized and how the user interacts with it. The two behavior‑adjacent changes (`--dry-run`, resumable install, non‑interactive mode) are all *opt‑in* via flags, so existing users running `bash modmium.sh` get byte‑identical behavior. That's the bar: **easier to install, easier to use, no feature loss, no stability regression.**

---

*End of EZ‑Modmium. If anything here conflicts with upstream behaviour, the upstream `docs/` and source code at the `stable` branch are authoritative. Please file inaccuracies as issues on the Modmium repo or ask in the [crosbreaker Discord](https://discord.crosbreaker.com).*
