#!/bin/bash
# =============================================================================
# EZ-Modmium — modmium.sh (on-device installer / DevFW flasher)
# =============================================================================
# Forked from Modmium (https://github.com/CrOSmium/modmium) by CrOSmium/crosbreaker.
#
# EZ-Modmium improvements over upstream:
#   * Sources build-utils/libmodmium.sh (single source of truth for helpers)
#   * Reads centralized config from modmium.conf (URLs, thresholds, flags)
#   * --dryrun : run all checks, flash nothing
#   * --yes / --config : non-interactive mode for fleets/CI
#   * --selftest : validate pure helper functions
#   * --help : real usage with examples
#   * Structured logging to /var/log/modmium/
#   * SHA-256 verification of firmware backup after writing it
#   * Mode-aware file permissions (no more blanket chmod 777)
#   * Fixed WP-check bug (crossystem || grep "0" no longer masks failures)
#   * Drops runtime `pip install requests` — uses bundled stdlib stream.py
#   * Safe `find -print0` loops (handles spaces in paths)
#   * All variables quoted; set -uo pipefail
#
# Original behavior is preserved when run with no flags.
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Locate and source the shared library + config
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

EZ_LIB_PATH=""
for _p in \
  "/usr/lib/libmodmium.sh" \
  "${SCRIPT_DIR}/build-utils/libmodmium.sh" \
  "${SCRIPT_DIR}/libmodmium.sh" \
  "/usr/local/lib/libmodmium.sh"; do
  if [[ -f "$_p" ]]; then
    EZ_LIB_PATH="$_p"
    break
  fi
done
if [[ -z "$EZ_LIB_PATH" ]]; then
  echo "ERROR: libmodmium.sh not found. Reinstall EZ-Modmium or run from the repo root." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$EZ_LIB_PATH"
unset _p

log "INFO" "EZ-Modmium modmium.sh starting (lib=$EZ_LIB_PATH)"

# ---------------------------------------------------------------------------
# shflags
# ---------------------------------------------------------------------------
_shflags=""
for _p in /usr/share/misc/shflags "${SCRIPT_DIR}/build-utils/lib/shflags/shflags"; do
  if [[ -f "$_p" ]]; then _shflags="$_p"; break; fi
done
if [[ -z "$_shflags" ]]; then
  echo "ERROR: shflags not found." >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$_shflags"
unset _p

# ---------------------------------------------------------------------------
# Usage (defined early so --help works)
# ---------------------------------------------------------------------------
ez_usage() {
  cat <<'EOF'
EZ-Modmium — on-device installer & DevFW flasher

USAGE:
  bash modmium.sh [options]

WHAT IT DOES (two stages):
  1. First run (no DevFW yet): flashes developer firmware (DevFW) + backs up
     your stock firmware, then asks you to reboot.
  2. Second run (after reboot, DevFW active): installs ChromeOS + Modmium to
     the inactive partition, removes rootfs verification, switches boot, reboots.

OPTIONS:
  -u, --userkeys        Use your own signing keys from a plugged-in USB
  -b, --backup          Create a firmware backup (default: true; use --nobackup to skip)
  -n, --dryrun          Run every check (WP, APROV, disk space, URL resolution)
                        but flash/write nothing. Safe to run anytime.
                        (alias: --dry-run)
  -T, --selftest        Run built-in unit tests for the helper functions and exit.
  -y, --yes             Auto-accept all confirmations (non-interactive / CI / fleet).
  -c, --config <file>   Load a modmium.conf overriding defaults.
  -s, --status          Show device status (version, branch, DevFW, WP, APROV,
                        kernver, backups, install state) and exit. Read-only.
  -U, --uninstall       Clean revert: restore stock firmware backup + clear
                        FWMP + clear dev_firmware VPD. Requires a firmware
                        backup. Add -f/--force to skip firmware restore.
  -r, --resume          Resume an interrupted install (skips completed phases
                        recorded in the state file).
  -h, --help            Show this help.

EXAMPLES:
  # First run (flash DevFW + back up to USB):
  cd /usr/local; curl -LOsk modmium.dev/modmium.sh && bash modmium.sh

  # Second run (install Modmium stable):
  bash modmium.sh

  # Pre-flight check without touching anything:
  bash modmium.sh --dryrun

  # Fully non-interactive (answers all prompts with yes):
  bash modmium.sh --yes

  # Validate the install:
  bash modmium.sh --selftest

  # Show device status (read-only):
  bash modmium.sh --status

  # Clean uninstall (restore stock firmware):
  bash modmium.sh --uninstall

  # Resume an interrupted install:
  bash modmium.sh --resume

  # Use your own signing keys (USB must be plugged in):
  bash modmium.sh -u

CONFIGURATION:
  See modmium.conf for overridable URLs, version thresholds, GBB flags, etc.
  Place at /etc/modmium/modmium.conf, ~/.config/modmium.conf, or ./modmium.conf

HELP:
  Discord: https://discord.crosbreaker.com
  Docs:    https://github.com/CrOSmium/modmium/tree/stable/docs
EOF
}

# Catch --help/-h before shflags parsing
for _a in "$@"; do
  case "$_a" in
    --help|-h) ez_usage; exit 0 ;;
  esac
done
unset _a

# ---------------------------------------------------------------------------
# Define flags
# ---------------------------------------------------------------------------
DEFINE_boolean userkeys "$FLAGS_FALSE" "Whether or not to use user-generated signing keys." "u"
DEFINE_boolean backup "$FLAGS_TRUE" "Whether or not to backup firmware from flashing devkeys." "b"
DEFINE_boolean dryrun "$FLAGS_FALSE" "Run all checks but do not flash or write anything." "n"
DEFINE_boolean selftest "$FLAGS_FALSE" "Run built-in self-test and exit." "T"
DEFINE_boolean yes "$FLAGS_FALSE" "Auto-accept all prompts (non-interactive / CI / fleet)." "y"
DEFINE_string config "" "Path to a modmium.conf config file to load." "c"
DEFINE_boolean status "$FLAGS_FALSE" "Show device status and exit (read-only)." "s"
DEFINE_boolean uninstall "$FLAGS_FALSE" "Clean revert: restore stock firmware + clear FWMP/VPD." "U"
DEFINE_boolean resume "$FLAGS_FALSE" "Resume an interrupted install." "r"
DEFINE_boolean force "$FLAGS_FALSE" "Force uninstall: skip firmware restore (only clear FWMP+VPD)." "f"

# Translate hyphenated aliases (shflags derives long name from var name)
EZ_ARGS=()
for _a in "$@"; do
  case "$_a" in
    --dry-run) EZ_ARGS+=("--dryrun") ;;
    --self-test) EZ_ARGS+=("--selftest") ;;
    *) EZ_ARGS+=("$_a") ;;
  esac
done
unset _a

FLAGS "${EZ_ARGS[@]}" || exit $?
unset EZ_ARGS

# Apply EZ flags
[[ "$FLAGS_yes" == "$FLAGS_TRUE" ]] && export EZ_YES=1
if [[ -n "$FLAGS_config" ]]; then
  if [[ -f "$FLAGS_config" ]]; then
    # shellcheck disable=SC1090
    source "$FLAGS_config"
    log "INFO" "Loaded config: $FLAGS_config"
  else
    fail "${R}Config file not found: $FLAGS_config${N}"
  fi
fi

# Selftest short-circuit
if [[ "$FLAGS_selftest" == "$FLAGS_TRUE" ]]; then
  ez_selftest
  exit $?
fi

# Status short-circuit (read-only)
if [[ "$FLAGS_status" == "$FLAGS_TRUE" ]]; then
  ez_status
  exit $?
fi

# Uninstall short-circuit
if [[ "$FLAGS_uninstall" == "$FLAGS_TRUE" ]]; then
  _force_arg=""
  [[ "$FLAGS_force" == "$FLAGS_TRUE" ]] && _force_arg="--force"
  ez_uninstall "$_force_arg"
  exit $?
fi

# ---------------------------------------------------------------------------
# Logo
# ---------------------------------------------------------------------------
logo() {
  echo -e "
 ██████   ██████              █████                  ███
▒▒██████ ██████              ▒▒███                  ▒▒▒
 ▒███▒█████▒███   ██████   ███████  █████████████   ████  █████ ████ █████████████
 ▒███▒▒███ ▒███  ███▒▒███ ███▒▒███ ▒▒███▒▒███▒▒███ ▒▒███ ▒▒███ ▒███ ▒▒███▒▒███▒▒███
 ▒███ ▒▒▒  ▒███ ▒███ ▒███▒███ ▒███  ▒███ ▒███ ▒███  ▒███  ▒███ ▒███  ▒███ ▒███ ▒███
 ▒███      ▒███ ▒███ ▒███▒███ ▒███  ▒███ ▒███ ▒███  ▒███  ▒███ ▒███  ▒███ ▒███ ▒███
 █████     █████▒▒██████ ▒▒████████ █████▒███ █████ █████ ▒▒████████ █████▒███ █████
▒▒▒▒▒     ▒▒▒▒▒  ▒▒▒▒▒▒   ▒▒▒▒▒▒▒▒ ▒▒▒▒▒ ▒▒▒ ▒▒▒▒▒ ▒▒▒▒▒   ▒▒▒▒▒▒▒▒ ▒▒▒▒▒ ▒▒▒ ▒▒▒▒▒
"
  echo -e "${B}EZ-Modmium${N} install script"
}

# ---------------------------------------------------------------------------
# Backup destination selection
# ---------------------------------------------------------------------------
selectBackup() {
  BACKUP=/tmp/backupdir
  mkdir -p "$BACKUP"
  if [[ "$FLAGS_backup" == "$FLAGS_FALSE" && "$FLAGS_userkeys" == "$FLAGS_FALSE" ]]; then
    return
  fi

  if [[ "$FLAGS_userkeys" == "$FLAGS_FALSE" ]]; then
    echo -e "Would you like to ${R}ERASE${N} an external (D)rive and backup to it, or backup to a directory? (D = drive, P = directory)"
    echo -e "Backing up to a (D)rive is highly recommended. [or already have a mount (P)oint -> directory]"
    ask "(d/p)" resp ""
    if [[ "$resp" =~ ^[Dd]$ ]]; then
      local drivelist
      drivelist=$(lsblk -dpno NAME,SIZE,MODEL 2>/dev/null | grep -Ev "$(get_largest_cros_blockdev)|loop|ram" || true)
      [[ -z "$drivelist" ]] && fail "${R}No connected drives, exiting...${N}"
      echo -e "These are the drives connected to your device:"
      echo "$drivelist"
      echo -e "What drive would you like write the backup onto? Type /dev/sdX or sdX ${R}(THIS WILL ERASE THE DRIVE!!!!)${N}"
      ask "Drive" driveloc ""
      driveloc="${driveloc%/}"
      local fulldev="$driveloc"
      [[ "$driveloc" != *"/dev/"* ]] && fulldev="/dev/$driveloc"

      if [[ "$FLAGS_dryrun" == "$FLAGS_TRUE" ]]; then
        log_info "[dry-run] Would mkfs.vfat + mount $fulldev"
        return
      fi
      mkfs.vfat -I -F 32 "$fulldev" || fail "${R}Unable to wipe device, exiting...${N}"
      mkdir -p "$BACKUP"
      mount "$fulldev" "$BACKUP" || fail "${R}Unable to mount device, exiting...${N}"

      if ! [[ -d "$BACKUP" && -w "$BACKUP" ]]; then
        fail "${R}Unable to write to backup, exiting...${N}"
      fi
      DRIVEBACKUP=1
    elif [[ "$resp" =~ ^[Pp]$ ]]; then
      ask "What directory would you like to backup to?" BACKUP ""
      if ! [[ -d "$BACKUP" && -w "$BACKUP" ]]; then
        fail "${R}Unable to write to backup, exiting...${N}"
      fi
      log_info "Valid directory!"
    else
      fail "Invalid response, exiting..."
    fi
  else
    # userkeys path — list vfat drives
    echo -e "These are the vfat drives/partitions connected to your device:"
    local drive
    for drive in $(lsblk -lo NAME,FSTYPE 2>/dev/null | grep vfat | awk '{print $1}'); do
      echo "/dev/$drive"
    done
    echo -e "Type the drive that the signing keys were backed up to (/dev/sdX or sdX)..."
    ask "Drive" driveloc ""
    driveloc="${driveloc%/}"
    local fulldev="$driveloc"
    [[ "$driveloc" != *"/dev/"* ]] && fulldev="/dev/$driveloc"
    mount "$fulldev" "$BACKUP" || fail "${R}Unable to mount device...${N}"
  fi

  # Verify free space (>=16MB)
  local free_kb
  free_kb=$(df "$BACKUP" 2>/dev/null | awk '{print $4}' | tail -n 1)
  if [[ -n "$free_kb" && "$free_kb" =~ ^[0-9]+$ && "$free_kb" -lt 16384 ]]; then
    fail "${R}NOT ENOUGH EMPTY SPACE ON DRIVE. Exiting...${N}"
  fi
}

selUserBackup() {
  # If $BACKUP is already a mountpoint (e.g., --resume re-run), don't re-mount
  if mountpoint -q "$BACKUP" 2>/dev/null; then
    log_info "Backup drive already mounted at $BACKUP (skipping re-mount)."
    return 0
  fi
  echo -e "These are the vfat drives/partitions connected to your device:"
  local drive
  for drive in $(lsblk -lo NAME,FSTYPE 2>/dev/null | grep vfat | awk '{print $1}'); do
    echo "/dev/$drive"
  done
  echo -e "Type the drive that the signing keys [userkeys] were backed up to (/dev/sdX or sdX)..."
  ask "Drive" driveloc ""
  driveloc="${driveloc%/}"
  local fulldev="$driveloc"
  [[ "$driveloc" != *"/dev/"* ]] && fulldev="/dev/$driveloc"
  mount "$fulldev" "$BACKUP" || fail "${R}Unable to mount device...${N}"
}

# ---------------------------------------------------------------------------
# DevFW flashing (stage 1)
# ---------------------------------------------------------------------------
flashDevFW() {
  local DEVFW
  DEVFW=$(vpd -i RO_VPD -g "dev_firmware" 2>&1 || echo "")

  # Clear FWMP (best-effort, with TPM fallback)
  log_step "Clearing FWMP..."
  (
    device_management_client --action=remove_firmware_management_parameters >/dev/null 2>&1 || \
    cryptohome --action=remove_firmware_management_parameters >/dev/null 2>&1
    device_management_client --action=set_firmware_management_parameters --flags=0x0 >/dev/null 2>&1 || \
    cryptohome --action=set_firmware_management_parameters --flags=0x0 >/dev/null 2>&1
  ) || (
    initctl stop tcsd >/dev/null 2>&1 || true
    initctl stop trunksd >/dev/null 2>&1 || true
    tpmc clear; tpmc def 0x100a 0x28 0x12000
    tpmc write 0x100a 76 28 10 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0
  )

  if [[ "$DEVFW" != 1 ]]; then
    log_step "Making firmware backup..."
    local backup_file
    backup_file="$BACKUP/backup_$(date +"%Y%m%d").rom"

    if [[ "$FLAGS_dryrun" == "$FLAGS_TRUE" ]]; then
      log_info "[dry-run] Would flashrom -r $backup_file"
      log_info "[dry-run] Would flash DevFW with GBB flags=$EZ_GBB_FLAGS"
      return
    fi

    flashrom -r "$backup_file" || fail "${R}Failed to read firmware for backup.${N}"
    log_info "Firmware backup written: $backup_file"

    # EZ improvement: SHA-256 the backup and verify it
    local sha
    sha=$(sha256_of "$backup_file")
    echo "$sha  $(basename "$backup_file")" > "$BACKUP/backup.sha256"
    log_info "Backup SHA-256: $sha"

    # Verify backup by re-reading and comparing size + hash
    local sz_actual sz_verify sha_verify
    sz_actual=$(stat -c %s "$backup_file" 2>/dev/null || echo 0)
    flashrom -r "$BACKUP/.verify.rom" >/dev/null 2>&1 || true
    if [[ -f "$BACKUP/.verify.rom" ]]; then
      sz_verify=$(stat -c %s "$BACKUP/.verify.rom" 2>/dev/null || echo 0)
      sha_verify=$(sha256_of "$BACKUP/.verify.rom")
      rm -f "$BACKUP/.verify.rom"
      if [[ "$sz_actual" != "$sz_verify" || "$sha" != "$sha_verify" ]]; then
        fail "${R}Firmware backup verification FAILED! Sizes or hashes differ. Aborting — your USB may be faulty.${N}"
      fi
      log_info "Backup verified (size + SHA-256 match)."
    else
      log_warn "Could not re-read firmware for verification (flashrom busy?). Proceeding without verify."
    fi

    log_step "Flashing DevFW..."
    if [[ "$FLAGS_userkeys" == "$FLAGS_FALSE" ]]; then
      /usr/share/vboot/bin/make_dev_ssd.sh --force -r \
        || fail "${R}make_dev_ssd.sh failed${N}" keepflag
      /usr/share/vboot/bin/make_dev_firmware.sh --nomod_gbb_flags --nomod_hwid "$BACKUP" --to /tmp/devfw.bin \
        || fail "${R}make_dev_firmware.sh failed${N}" keepflag
      futility gbb -s /tmp/devfw.bin --flags="$EZ_GBB_FLAGS" \
        || fail "${R}futility gbb failed${N}" keepflag
      flashrom -w /tmp/devfw.bin \
        || fail "${R}flashrom write failed — DO NOT REBOOT. Re-run with a valid backup.${N}" keepflag
    else
      /usr/share/vboot/bin/make_dev_ssd.sh --force -r --keys "${BACKUP}/userkeys" \
        || fail "${R}make_dev_ssd.sh (userkeys) failed${N}" keepflag
      /usr/share/vboot/bin/make_dev_firmware.sh --nomod_gbb_flags --nomod_hwid "$BACKUP" --keys "${BACKUP}/userkeys" --to /tmp/devfw.bin \
        || fail "${R}make_dev_firmware.sh (userkeys) failed${N}" keepflag
      futility gbb -s /tmp/devfw.bin --flags="$EZ_GBB_FLAGS" \
        || fail "${R}futility gbb (userkeys) failed${N}" keepflag
      flashrom -w /tmp/devfw.bin \
        || fail "${R}flashrom write (userkeys) failed — DO NOT REBOOT.${N}" keepflag
      sync
    fi
    vpd -i RO_VPD -s dev_firmware=1 \
      || fail "${R}vpd set dev_firmware=1 failed${N}" keepflag
    log_info "DevFW flashed."
  else
    fail "You are already using custom boot keys!" keepflag
  fi
  sleep 0.5
}

# ---------------------------------------------------------------------------
# ChromeOS + Modmium install (stage 2)
# ---------------------------------------------------------------------------
installCros() {
  stop powerd &>/dev/null || true
  ldconfig 2>/dev/null || true

  # --resume: if an interrupted install state exists, show it and offer to resume
  if [[ "$FLAGS_resume" == "$FLAGS_TRUE" ]]; then
    if [[ -f "$EZ_STATE_FILE" ]]; then
      log_info "Resuming interrupted install. Current state:"
      state_show
      echo
      if ! confirm "Resume from the last completed phase?" "Y"; then
        log_info "Resume declined. Clearing state and starting fresh."
        state_clear
      else
        log_info "Resuming — completed phases will be skipped where safe."
      fi
    else
      log_info "No interrupted install state found. Starting fresh."
    fi
  fi

  log_info "This script grabs the current kernver and signs the new version with it, so there's no issues with upgrading or downgrading."
  ask "Version of ChromeOS you want to install" VERSION ""
  [[ "$VERSION" =~ ^[0-9]+$ ]] || fail "${R}Version must be numeric, exiting...${N}" keepflag

  if [[ "$VERSION" -lt "$EZ_MIN_VERSION" ]]; then
    log_warn "WARNING: VERSIONS BELOW $EZ_MIN_VERSION ARE NOT SUPPORTED."
    log_warn "Do not make an issue report if you run into problems."
    if ! confirm "Continue anyway?" "N" --single; then
      fail "${R}Exiting...${N}" keepflag
    fi
  fi

  local branch
  askBranch branch "stable"

  # Phase: image_resolved
  if [[ "$FLAGS_resume" == "$FLAGS_TRUE" ]] && state_has "image_resolved"; then
    log_info "[resume] Re-resolving URL (URL not persisted across runs)..."
    getImageLink "$BOARD" "$VERSION" recoveryUrl
  else
    getImageLink "$BOARD" "$VERSION" recoveryUrl
    save_state "image_resolved"
  fi

  intdis=$(rootdev -d)
  if echo "$intdis" | grep -q '[0-9]$'; then
    intdis_prefix="${intdis}p"
  else
    intdis_prefix="$intdis"
  fi

  local installKern installRoot
  installKern="${intdis_prefix}$(opposite_num "$(get_booted_kernnum "$intdis")")"
  installRoot="${intdis_prefix}$(opposite_num "$(get_booted_rootnum "$intdis")")"

  # Phase: chromeos_written + verity_removed
  # NOTE: streaming is NOT safely resumable (partial writes corrupt the partition).
  if [[ "$FLAGS_resume" == "$FLAGS_TRUE" ]] && state_has "chromeos_written"; then
    log_info "[resume] Skipping ChromeOS streaming + verity removal (already written)."
  else
    log_step "Installing ChromeOS to disk..."
    cd /usr/local || fail "cd /usr/local failed"

    # EZ improvement: use the bundled stdlib-only stream.py — no pip/venv needed
    local stream_py=""
    for _p in /usr/bin/stream.py /usr/local/bin/stream.py "${SCRIPT_DIR}/mod-files/usr/bin/stream.py"; do
      if [[ -f "$_p" ]]; then stream_py="$_p"; break; fi
    done
    if [[ -z "$stream_py" ]]; then
      log_warn "Bundled stream.py not found; downloading from $EZ_STREAM_PY_URL"
      fetch_and_verify "$EZ_STREAM_PY_URL" /root/stream.py
      stream_py="/root/stream.py"
    fi
    unset _p

    if [[ "$FLAGS_dryrun" == "$FLAGS_TRUE" ]]; then
      log_info "[dry-run] Would run: python $stream_py --recovery-url $recoveryUrl --kern-output $installKern --root-output $installRoot"
      return
    fi

    python "$stream_py" --recovery-url "$recoveryUrl" --kern-output "$installKern" --root-output "$installRoot" \
      || fail "${R}Failed to install ChromeOS, refusing to change boot order, exiting...${N}" keepflag
    save_state "chromeos_written"

    log_step "Removing verity from ChromeOS..."
    /usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification --partitions "$(opposite_num "$(get_booted_kernnum "$intdis")")" --keys "${keydir}" &>/dev/null
    futility dump_kernel_config "$installKern" > config.txt \
      || fail "${R}futility dump_kernel_config failed for $installKern${N}" keepflag
    [[ -s config.txt ]] || fail "${R}dump_kernel_config produced empty config for $installKern${N}" keepflag
    sed -i "s|cros_secure|cros_secure cros_debug|g" config.txt
    sed -i 's/  */ /g; s/^ //; s/ $//' config.txt

    if ! stop trunksd &>/dev/null && ! stop tcsd &>/dev/null; then
      log_warn "Could not stop trunksd/tcsd; tpmc read may fail."
    fi
    local rawkv
    rawkv=$(tpmc read "$EZ_TPM_KERNVER_INDEX" 9) \
      || fail "${R}tpmc read $EZ_TPM_KERNVER_INDEX failed — cannot determine kernver${N}" keepflag
    [[ -n "$rawkv" ]] || fail "${R}tpmc read returned empty data${N}" keepflag
    start trunksd &>/dev/null || start tcsd &>/dev/null || true

    # Parse kernver from TPM bytes (Aurora-inspired)
    local -a bytes=()
    local byte
    for byte in $rawkv; do
      while [[ -n "$byte" ]]; do
        bytes+=("${byte:0:2}")
        byte="${byte:2}"
      done
    done
    local kernver=0
    if [[ "16#${bytes[0]:-0}" -eq 16 ]]; then
      kernver=$(( 16#${bytes[4]:-0} | 16#${bytes[5]:-0}<<8 ))
    elif [[ "16#${bytes[0]:-0}" -eq 2 ]]; then
      kernver=$(( 16#${bytes[5]:-0} | 16#${bytes[6]:-0}<<8 ))
    fi
    log_info "Detected kernver from TPM: $kernver"

    futility vbutil_kernel --repack "$installKern" \
      --keyblock "${keydir}/kernel.keyblock" \
      --signprivate "${keydir}/kernel_data_key.vbprivk" \
      --config config.txt \
      --version "$kernver" \
      --oldblob "$installKern" \
      || fail "${R}Failed to remove verity, exiting...${N}" keepflag
    rm -rf config.txt
    save_state "verity_removed"
  fi

  # Phase: modfiles_dropped
  if [[ "$FLAGS_resume" == "$FLAGS_TRUE" ]] && state_has "modfiles_dropped"; then
    log_info "[resume] Skipping mod-files drop (already done)."
  else
    log_step "Installing Modmium ($branch) to ChromeOS..."
    export PATH="${PATH}:/usr/local/libexec/git-core"
    mkdir -p /mnt/stateful_partition/git
    cd /mnt/stateful_partition/git || fail "cd failed"
    if [[ -d /root/.ssh ]]; then
      [[ ! -d /home/chronos/user/.ssh ]] && mkdir -p /home/chronos/user/.ssh
      git clone --depth 1 -b "$branch" --single-branch git@github.com:crosmium/modmium.git \
        || fail "${R}Failed to clone repository, exiting...${N}" keepflag
    else
      git clone --depth 1 -b "$branch" --single-branch https://github.com/crosmium/modmium.git \
        || fail "${R}Failed to clone repository, exiting...${N}" keepflag
    fi
    log_info "Successfully cloned repository! Dropping new files..."

    cd modmium || fail "cd modmium failed"
    mount "$installRoot" mnt --mkdir \
      || fail "${R}Failed to mount $installRoot on mnt — aborting before file drop.${N}" keepflag

    # EZ improvement: shared, mode-aware, space-safe mod-files drop
    drop_mod_files "$(pwd)/mod-files" "$(pwd)/mnt" "$(pwd)"

    [[ -d "${BACKUP}/userkeys" ]] && cp -r "${BACKUP}/userkeys" mnt/usr/share/vboot
    echo "$branch" > mnt/.branch

    log_step "Syncing filesystem (may take a while)..."
    sync
    umount mnt || fail "${R}Failed to umount mnt — files may not be fully written.${N}" keepflag
    cd .. && rm -rf modmium
    sync
    save_state "modfiles_dropped"
  fi

  if confirm "Would you like to powerwash? (Can prevent blackscreening on boot)" "N" --single; then
    echo -e "Your device ${R}will${N} powerwash on next boot."
    echo "fast safe keepimg" > /mnt/stateful_partition/factory_install_reset
    sleep 0.3
  else
    echo -e "Your device will ${R}NOT${N} powerwash on next boot."
    sleep 0.3
  fi

  echo -e "${Y}Remove developer packages for compatibility with other ChromeOS versions? [Y/n]${N}"
  read -r
  if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
    log_step "Uninstalling developer packages..."
    printf 'y\n' | dev_install --uninstall
    rm -f /mnt/stateful_partition/.devinstall_complete
  else
    log_info "Keeping packages installed."
  fi

  # Phase: boot_switched (final)
  log_step "Switching active kernel..."
  local activekern inactivekern
  activekern=$(get_booted_kernnum "$intdis")
  inactivekern=$(opposite_num "$activekern")
  cgpt add -P 1 -T 0 -S 1 -i "$activekern" "$intdis" \
    || fail "${R}cgpt: failed to demote active kernel $activekern — DO NOT REBOOT.${N}" keepflag
  cgpt add -P 15 -T 6 -S 0 -i "$inactivekern" "$intdis" \
    || fail "${R}cgpt: failed to promote inactive kernel $inactivekern — DO NOT REBOOT.${N}" keepflag
  sync
  save_state "boot_switched"
  state_clear  # Success — clear the state file
  log_info "Done!"

  if confirm "Would you like to reboot now?" "Y" --single; then
    log_info "Rebooting!"
    reboot
    sleep infinity
  else
    log_info "Reboot when ready! Exiting..."
    sleep 2
    start powerd &>/dev/null || true
    exit 0
  fi
}

# ---------------------------------------------------------------------------
# Modmium install entry (resolves keydir + deps, then installCros)
# ---------------------------------------------------------------------------
modmiumInstall() {
  if [[ "$FLAGS_userkeys" == "$FLAGS_TRUE" ]]; then
    BACKUP=/tmp/backupdir
    mkdir -p "$BACKUP"
    selUserBackup
    keydir="${BACKUP}/userkeys"
  else
    keydir=/usr/share/vboot/devkeys
  fi
  ensure_dev_tools
  installCros
}

# ---------------------------------------------------------------------------
# Stage-1 main (DevFW)
# ---------------------------------------------------------------------------
main() {
  clear
  logo
  echo -e "This requires write protection to be disabled, and it will be checked before this script attempts anything."
  echo -e "Checking for Firmware Write Protection..."

  checkWP
  checkAPROV

  if [[ "$FLAGS_dryrun" == "$FLAGS_TRUE" ]]; then
    log_info "${G}[DRY-RUN]${N} All preflight checks passed. No changes were made."
    log_info "Would now: confirm -> selectBackup -> flashDevFW -> reboot"
    exit 0
  fi

  echo -e "Are you sure you want to flash DevFW firmware?"
  if ! confirm "Flash DevFW?" "N"; then
    log_info "Aborted by user."
    exit 0
  fi

  log_step "Getting backup selection..."
  selectBackup

  log_step "Backup selection complete, flashing DevFW..."
  flashDevFW

  touch /tmp/.rebootpls
  cat <<EOF
If everything succeeded, you are now running DevFW!
It is highly recommended to back up the firmware now in your selected drive (or directory) to the cloud, or another safe place.
${B}Please reboot your chromebook${N}. After you reboot, either recover with a Modmium image OR run this script again to INSTALL Modmium. (If you used userkeys, make sure you also use that flag when trying to Install Modmium with this script)
EOF
  log_info "Exiting..."
  sleep 0.5
  exit 0
}

# ---------------------------------------------------------------------------
# Entry point — mirrors upstream's stage detection
# ---------------------------------------------------------------------------
BOARD="$(grep '^CHROMEOS_RELEASE_DESCRIPTION=' /etc/lsb-release 2>/dev/null | awk '{print $NF}')"

clear
DEVFW=$(vpd -i RO_VPD -g "dev_firmware" 2>&1 || echo "")
if [[ -f /tmp/.rebootpls ]]; then
  echo -e "Please reboot your device before running this script again!"
  exit 1
fi
if [[ "$DEVFW" == "1" ]]; then
  modmiumInstall
else
  main
fi
