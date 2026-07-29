#!/bin/bash
# written by mariah carey and DMD
# EZ-Modmium: refactored to source /usr/lib/libmodmium.sh (shared helpers),
# drop pip/venv (uses bundled stdlib stream.py), and use the shared,
# mode-aware drop_mod_files.

set -uo pipefail

# Source the shared EZ-Modmium library (colors, helpers, config, logging)
if [[ -f /usr/lib/libmodmium.sh ]]; then
  # shellcheck disable=SC1091
  source /usr/lib/libmodmium.sh
else
  # Fallback inline definitions if libmodmium isn't installed yet
  B=$'\033[38;5;45m'; G=$'\033[38;5;46m'; Y=$'\033[38;5;220m'; R=$'\033[38;5;203m'
  P=$'\033[38;5;135m'; N=$'\033[0m'; D=$'\033[1;90m'; UN=$'\033[4m'; RUN=$'\033[24m'
  EZ_TPM_KERNVER_INDEX="0x1008"
  EZ_RELEASES_JSON_URL="https://cdn.jsdelivr.net/gh/crosbreaker/chromeos-releases-data/data.json"
  EZ_MIN_VERSION="131"
  log() { :; }
  log_info() { echo -e "${G}$1${N}"; }
  log_warn() { echo -e "${Y}$1${N}"; }
  log_step() { echo -e "${B}$1${N}"; }
  log_error() { echo -e "${R}$1${N}"; }
  sha256_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }
  ensure_dev_tools() {
    if ! which git &>/dev/null || ! which file &>/dev/null; then
      echo -e "${R}Dependencies not installed, installing...${N}"
      source /etc/profile 2>/dev/null || true
      if [[ ! -f /mnt/stateful_partition/.devinstall_complete ]]; then
        printf 'y\n\nn' | dev_install --reinstall || fail "Could not install dependencies."
        touch /mnt/stateful_partition/.devinstall_complete
      fi
      ldconfig 2>/dev/null || true
      emerge git file
      cp -r /usr/local/usr/share/git-core/templates /usr/share/git-core 2>/dev/null || true
    fi
  }
  # Fallback helpers (only used if libmodmium not yet installed)
  get_booted_kernnum() {
    if (( $(cgpt show -n "$intdis" -i 2 -P 2>/dev/null || echo 0) > $(cgpt show -n "$intdis" -i 4 -P 2>/dev/null || echo 0) )); then
      echo -n 2
    else
      echo -n 4
    fi
  }
  get_booted_rootnum() { echo $(( $(get_booted_kernnum) + 1 )); }
  opposite_num() {
    case "$1" in
      2) echo -n 4 ;; 3) echo -n 5 ;; 4) echo -n 2 ;; 5) echo -n 3 ;; *) echo -n "skid" ;;
    esac
  }
  format_part_number() {
    echo -n "$1"
    echo "$1" | grep -q '[0-9]$' && echo -n p
    echo -n "$2"
  }
  confirm() {
    local prompt="$1" default="${2:-N}" single=0
    [[ "${3:-}" == "--single" ]] && single=1
    local hint
    [[ "$default" == "Y" ]] && hint="[Y/n]" || hint="[y/N]"
    if [[ "$single" == "1" ]]; then
      echo -ne "${prompt} ${hint} "
      local ans; read -r -n 1 ans; echo
      [[ -z "$ans" ]] && ans="$default"
      [[ "$ans" =~ ^[Yy]$ ]]
    else
      echo -e "${prompt} ${hint}"
      echo -ne "(double-tap y to confirm, any other key to abort): "
      local ans; read -r -n 2 -s ans; echo
      [[ "$ans" == "yy" ]]
    fi
  }
  ask() {
    local prompt="$1" varname="$2" default="${3:-}" val
    if [[ -n "$default" ]]; then echo -ne "${prompt} [${default}]: "
    else echo -ne "${prompt}: "; fi
    read -r -e val; val="${val:-$default}"
    printf -v "$varname" '%s' "$val"
  }
  askBranch() {
    local outvar="$1" default="${2:-stable}" branchreq branch
    local branchfile="$(cat /.branch 2>/dev/null)"
    [[ -n "$branchfile" ]] && default="$branchfile"
    echo -e "[If you don't know what this means, just press enter]"
    echo -ne "Branch of Modmium to install (stable, nightly): "
    read -r -ep "" branchreq
    case "$branchreq" in
      nightly) branch="nightly" ;; stable) branch="stable" ;; *) branch="$default" ;;
    esac
    echo
    printf -v "$outvar" '%s' "$branch"
  }
  getImageLink() {
    local board="$1" ver="$2" outvar="$3"
    local recoveryUrl
    recoveryUrl=$(curl -sL "$EZ_RELEASES_JSON_URL" | jq -r --arg board "$board" --arg ver "$ver" '.[$board].images // [] | map(select(.channel == "stable-channel" and (.chrome_version | startswith($ver + ".")))) | sort_by(.last_modified) | last | .url // empty' 2>/dev/null)
    printf -v "$outvar" '%s' "$recoveryUrl"
  }
  drop_mod_files() {
    local modfiles="$1" mnt="$2" repo_root="${3:-}"
    while IFS= read -r -d '' file; do
      [[ -d "$file" || ! -f "$file" ]] && continue
      local rel oldFile
      rel="${file#"$modfiles"/}"
      oldFile="$mnt/$rel"
      [[ -f "$oldFile" ]] && mv "$oldFile" "$oldFile.old"
      mkdir -p "$(dirname "$oldFile")"
      cp "$file" "$oldFile"; chown 0:0 "$oldFile"
      local m=755
      case "/$rel" in /etc/*) [[ -x "$file" ]] && m=755 || m=644 ;; esac
      chmod "$m" "$oldFile"
    done < <(find "$modfiles" -mindepth 1 -print0 2>/dev/null)
    if [[ -n "$repo_root" ]]; then
      local arch archfile
      arch=$(file "$mnt/bin/bash" | awk -F', ' '{print $2}')
      [[ "$arch" == *"ARM"* ]] && arch=aarch64
      archfile="$repo_root/build-utils/lib/minioverride-${arch}.so"
      [[ -f "$archfile" ]] && { mkdir -p "$mnt/lib"; cp "$archfile" "$mnt/lib/minioverride.so"; chmod 755 "$mnt/lib/minioverride.so"; }
    fi
    rm -rf "$mnt/root/.force_update_firmware" "$mnt/opt/google/cr50" "$mnt/opt/google/ti50"
  }
fi

fail(){
  stty echo 2>/dev/null || true
  tput cnorm 2>/dev/null || true
  start powerd &>/dev/null || true
  echo -e "$1"
  sleep 2
  exit 1
}

# -- Pre TUI init --
stty -echo
# shellcheck disable=SC1091
source /usr/lib/libmosh.sh

# EZ improvement: use shared ensure_dev_tools (no more duplicated dev_install block)
ensure_dev_tools

intdis=$(rootdev -d)
if echo "$intdis" | grep -q '[0-9]$'; then
  intdis_prefix="$intdis"p
else
  intdis_prefix="$intdis"
fi

# -- FUNCTIONS --
BOARD="$(grep '^CHROMEOS_RELEASE_DESCRIPTION=' /etc/lsb-release 2>/dev/null | awk '{print $NF}')"

# EZ improvement: getImageLink/askBranch inline the libmodmium logic to avoid
# name collisions (the lib defines same-named functions with a different
# signature). These wrappers keep the upstream call signature (no args ->
# sets $recoveryUrl / $branch globals).
getImageLink(){
  log_step "Checking crosbreaker/chromeos-releases-data for recovery image URL..."
  recoveryUrl=$(curl -sL "$EZ_RELEASES_JSON_URL" 2>/dev/null | jq -r --arg board "$BOARD" --arg ver "$VERSION" '
    .[$board].images // []
    | map(select(
    .channel == "stable-channel" and
    (.chrome_version | startswith($ver + "."))
    ))
    | sort_by(.last_modified)
    | last
    | .url // empty
    ' 2>/dev/null)
  if [[ -n "$recoveryUrl" && "$recoveryUrl" =~ dl\.google\.com ]]; then
    log_info "Recovery URL found!"
    sleep 1
  else
    fail "${R}Recovery URL not found or invalid :(${N}"
  fi
}

askBranch(){
  local branchfile branchreq
  branchfile="$(cat /.branch 2>/dev/null)"
  [[ -n "$branchfile" ]] || branchfile="stable"
  echo -e "[If you don't know what this means, just press enter]"
  if [[ "$branchfile" == "stable" ]]; then
    echo -ne "Branch of Modmium to install (${UN}stable${RUN}, nightly): "
  else
    echo -ne "Branch of Modmium to install (stable, ${UN}nightly${RUN}): "
  fi
  read -r -ep "" branchreq
  case "$branchreq" in
    nightly) branch="nightly" ;;
    stable)  branch="stable" ;;
    *)       branch="$branchfile" ;;
  esac
  echo
  log "INFO" "askBranch: $branch"
}

dropModFiles() {
  # EZ improvement: use the shared, mode-aware, space-safe drop_mod_files
  drop_mod_files "/mnt/stateful_partition/git/modmium/mod-files" "/" ""
  if [[ -d /usr/local/share/policy-test-tool ]]; then
     cp -r /usr/share/.policy-test-tool/* /usr/local/share/policy-test-tool
  fi
}

updateModmium() {
  clear
  stty echo
  export PATH="${PATH}:/usr/local/libexec/git-core" # just in case, so we know git https will work
  askBranch
  mkdir -p /mnt/stateful_partition/git
  cd /mnt/stateful_partition/git
  [[ -d modmium ]] && rm -rf modmium
  if [[ -d /root/.ssh ]]; then
    [[ ! -d /home/chronos/user/.ssh ]] && mkdir /home/chronos/user/.ssh
    git clone --depth 1 -b $branch --single-branch git@github.com:crosmium/modmium.git || fail "${R}Failed to clone repository, exiting...${N}"
  else
    git clone --depth 1 -b $branch --single-branch https://github.com/crosmium/modmium.git || fail "${R}Failed to clone repository, exiting...${N}"
  fi
  echo -e "${G}Successfully cloned repository!${N} Dropping new files..."
  dropModFiles || fail "${R}Failed to drop updated files, please make an issue report on https://github.com/crosmium/modmium with details of changes you made, if any...${N}"
  echo -e "${G}Done! Cleaning up...${N}"
  rm -rf /mnt/stateful_partition/git/modmium
  echo "$branch" > /.branch # actually update branch
  sync # this is for all the times i changed stuff locally and didn't sync and suddenly it didn't boot - dmd
  sleep 3
  stty -echo
  exit
}

# get_booted_kernnum / get_booted_rootnum / opposite_num now come from
# libmodmium (which reads $intdis from the environment). No local overrides.

installCros() {
  stop powerd &>/dev/null
  ldconfig
  stty echo
  echo -e "${D}Note: this script grabs the current kernver and signs the new version with it, so there's no issues with upgrading or downgrading.${N}"
  echo -ne "Version of ChromeOS you want to install: "
  read -rep "" VERSION
  [[ $VERSION =~ ^[0-9]+$ ]] || fail "${R}Version must be numeric, exiting...${N}"
  if [[ $VERSION -lt $MILESTONE ]]; then
    echo -e "${R}WARNING: YOU ARE DOWNGRADING CHROMEOS ($MILESTONE -> $VERSION), THIS MAY CAUSE PROBLEMS OR WIPE USER DATA.${N}\nDo not make an issue report if you run into problems."
  echo -e "${B}Continue anyways? [y/N]${N}"
  read -rep ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${B}Continuing...\n${N}"
    else
      fail "${R}Exiting...${N}"
    fi
  fi
  if [[ $VERSION -lt 131 ]]; then
    echo -e "${R}WARNING: VERSIONS BELOW 131 ARE NOT SUPPORTED.${N}\nDo not make an issue report if you run into problems."
    echo -e "${B}Continue anyways? [y/N]${N}"
    read -rep ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      echo -e "${B}Continuing...${N}"
    else
      fail "${R}Exiting...${N}"
    fi
  fi
  [[ ( $MILESTONE -gt $VERSION ) && ( $MILESTONE -gt 140 ) ]] && echo -e "${Y}You may have to remove and sign back into your account(s) after downgrading. Continuing anyways...${N}"
  askBranch
  getImageLink

  installKern=${intdis_prefix}$(opposite_num "$(get_booted_kernnum)")
  installRoot=${intdis_prefix}$(opposite_num "$(get_booted_rootnum)")
  log_step "Installing ChromeOS to disk..."
  cd /usr/local || fail "cd /usr/local failed"
  # EZ improvement: stream.py is now stdlib-only (urllib). No venv, no pip.
  local stream_py=/usr/bin/stream.py
  [[ -f "$stream_py" ]] || stream_py=/usr/local/bin/stream.py
  python "$stream_py" --recovery-url "${recoveryUrl}" --kern-output "${installKern}" --root-output "${installRoot}" \
    || fail "${R}Failed to install ChromeOS, refusing to change boot order, exiting...${N}"

  log_step "Removing verity from ChromeOS..."
  if [[ -d /usr/share/vboot/userkeys ]]; then
    keydir=/usr/share/vboot/userkeys
  else
    keydir=/usr/share/vboot/devkeys
  fi
  /usr/share/vboot/bin/make_dev_ssd.sh --remove_rootfs_verification --partitions "$(opposite_num "$(get_booted_kernnum)")" --keys "${keydir}" &>/dev/null
  futility dump_kernel_config "${installKern}" > config.txt \
    || fail "${R}futility dump_kernel_config failed for ${installKern}${N}"
  [[ -s config.txt ]] || fail "${R}dump_kernel_config produced empty config for ${installKern}${N}"
  sed -i "s|cros_secure|cros_secure cros_debug|g" config.txt
  sed -i 's/  */ /g; s/^ //; s/ $//' config.txt
  if ! stop trunksd &>/dev/null && ! stop tcsd &>/dev/null; then
    log_warn "Could not stop trunksd/tcsd; tpmc read may fail."
  fi
  local rawkv
  rawkv=$(tpmc read "$EZ_TPM_KERNVER_INDEX" 9) \
    || fail "${R}tpmc read $EZ_TPM_KERNVER_INDEX failed — cannot determine kernver${N}"
  [[ -n "$rawkv" ]] || fail "${R}tpmc read returned empty data${N}"
  start trunksd &>/dev/null || start tcsd &>/dev/null || true
  # this part inspired by aurora (though obviously not copy pasted), thanks soap :3
  local -a bytes=()
  local byte
  for byte in $rawkv; do
    while [[ -n "$byte" ]]; do
      bytes+=( "${byte:0:2}" )
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
  futility vbutil_kernel --repack "${installKern}" \
    --keyblock "${keydir}/kernel.keyblock" \
    --signprivate "${keydir}/kernel_data_key.vbprivk" \
    --config config.txt \
    --version "$kernver" \
    --oldblob "${installKern}" || fail "${R}Failed to remove verity, exiting...${N}"
  rm -rf config.txt

  log_step "Installing Modmium ($branch) to ChromeOS..."
  export PATH="${PATH}:/usr/local/libexec/git-core"
  mkdir -p /mnt/stateful_partition/git
  cd /mnt/stateful_partition/git || fail "cd failed"
  [[ -d modmium ]] && rm -rf modmium
  if [[ -d /root/.ssh ]]; then
    [[ ! -d /home/chronos/user/.ssh ]] && mkdir /home/chronos/user/.ssh
    git clone --depth 1 -b "$branch" --single-branch git@github.com:crosmium/modmium.git || fail "${R}Failed to clone repository, exiting...${N}"
  else
    git clone --depth 1 -b "$branch" --single-branch https://github.com/crosmium/modmium.git || fail "${R}Failed to clone repository, exiting...${N}"
  fi
  log_info "Successfully cloned repository! Dropping new files..."

  cd modmium || fail "cd modmium failed"
  mount "${installRoot}" mnt --mkdir \
    || fail "${R}Failed to mount ${installRoot} on mnt — aborting before file drop.${N}"
  if [[ -f /etc/chrome_dev.conf ]]; then
    mkdir -p mnt/etc
    cp -a /etc/chrome_dev.conf mnt/etc/chrome_dev.conf
  fi
  # EZ improvement: shared, mode-aware, space-safe drop_mod_files
  drop_mod_files "$(pwd)/mod-files" "$(pwd)/mnt" "$(pwd)"
  arch=$(file mnt/bin/bash 2>/dev/null | awk -F', ' '{print $2}')
  [[ -z "$arch" ]] && fail "${R}Could not detect arch from mnt/bin/bash${N}"
  [[ "$arch" == *"ARM"* ]] && arch=aarch64
  local _mo="build-utils/lib/minioverride-${arch}.so"
  [[ -f "$_mo" ]] || fail "${R}minioverride missing: $_mo${N}"
  mkdir -p mnt/lib
  cp "$_mo" mnt/lib/minioverride.so || fail "${R}Failed to install minioverride.so${N}"
  rm -rf mnt/root/.force_update_firmware mnt/opt/google/cr50 mnt/opt/google/ti50
  [[ -d /usr/share/vboot/userkeys ]] && cp -r /usr/share/vboot/userkeys mnt/usr/share/vboot

  # now to copy relevant files to new root
  for file in /bootsplash /.branch; do
    [[ -d $file || -f $file ]] && cp -r $file mnt
  done
  [[ -d /nix ]] && mkdir mnt/nix # we don't copy contents because the actual contents are in stateful
  echo -e "${B}Copy root's files to new root? [Y/n]${N}"
  read -rep ""
  if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Continuing..."
  else
    while IFS= read -r -d '' file; do
      cp -r "$file" mnt/root
    done < <(find /root -mindepth 1 -maxdepth 1 -print0 2>/dev/null)
  fi
  mkdir -p /tmp/install_marker
  mount "${intdis_prefix}12" /tmp/install_marker \
    || fail "${R}Failed to mount ${intdis_prefix}12 (EFI)${N}"
  touch /tmp/install_marker/.install_complete
  umount /tmp/install_marker
  rmdir /tmp/install_marker
  echo -e "${G}Syncing filesystem (may take a while)...${N}"
  sync
  umount mnt
  cd .. && rm -rf modmium
  sync
  echo -e "Would you like to powerwash? (Can prevent Modmium from failing to boot the newly switched version)"
  echo -ne "[y/N]: "
  read pwr
  if [[ "$pwr" =~ ^[Yy]$ ]]; then
    echo -e "Your device ${R}will${N} powerwash on next boot."
    echo "fast safe keepimg" > /mnt/stateful_partition/factory_install_reset
    sleep 0.3
  else
    echo -e "Your device will ${R}NOT${N} powerwash on next boot."
    sleep 0.3
  fi
  # this is for compatability with other chromeos versions
echo -e "${Y}Remove developer packages for compatibility with other ChromeOS versions? [Y/n]${N}"
read -r
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  echo -e "${G}Uninstalling packages...${N}"
  printf 'y\n' | dev_install --uninstall
  rm -f /mnt/stateful_partition/.devinstall_complete
else
  echo -e "${B}Keeping packages installed.${N}"
fi
  echo -e "Switching active kernel..."
  activekern=$(get_booted_kernnum)
  inactivekern=$(opposite_num "${activekern}")
  cgpt add -P 1 -T 0 -S 1 -i ${activekern} ${intdis}
  cgpt add -P 15 -T 6 -S 0 -i ${inactivekern} ${intdis}
  sync
  echo -e "${G}Done! Would you like to reboot now? [Y/n]${N}"
  read -n1 -r
  [[ $REPLY =~ ^[Nn]$ ]] && ( echo -e "${B}Reboot when ready! Exiting...${N}"; sleep 2; start powerd &>/dev/null; exit 0 )
  echo -e "${B}Rebooting!${N}"
  reboot
  sleep infinity
}




# -- NON UPDATER FUNCTIONS --

toggleBootPriority(){
  clear
  mkdir -p /tmp/install_marker
  mount "${intdis_prefix}12" /tmp/install_marker \
    || fail "${R}Failed to mount ${intdis_prefix}12 (EFI)${N}"
  if [[ ! -f /tmp/install_marker/.install_complete ]]; then
    umount /tmp/install_marker
    rmdir /tmp/install_marker
    echo -e "${R}ChromeOS update has not completed yet.${N}"
    sleep 3
    exit 1
  fi
  umount /tmp/install_marker
  rmdir /tmp/install_marker
  if (( $(cgpt show -n "$intdis" -i 2 -P) > $(cgpt show -n "$intdis" -i 4 -P) )); then
    currentKern=2
    newKern=4
  else
    currentKern=4
    newKern=2
  fi
if [[ -f /etc/chrome_dev.conf ]]; then
  mkdir -p /tmp/opposite

  newRoot=$((newKern + 1))
  mount ${intdis_prefix}${newRoot} /tmp/opposite 2>/dev/null

  mkdir -p /tmp/opposite/etc
  cp -a /etc/chrome_dev.conf /tmp/opposite/etc/chrome_dev.conf

  sync
  umount /tmp/opposite 2>/dev/null
  rmdir /tmp/opposite 2>/dev/null
  fi
  sync
  echo -e "Would you like to powerwash? (Can prevent Modmium from failing to boot the newly switched version)"
  echo -ne "[y/N]: "
  read pwr
  if [[ "$pwr" =~ ^[Yy]$ ]]; then
    echo -e "Your device ${R}will${N} powerwash on next boot."
    echo "fast safe keepimg" > /mnt/stateful_partition/factory_install_reset
    sleep 0.3
  else
    echo -e "Your device will ${R}NOT${N} powerwash on next boot."
    sleep 0.3
  fi
  # this is for compatability with other chromeos versions
echo -e "${Y}Remove developer packages for compatibility with other ChromeOS versions? [Y/n]${N}"
read -r
if [[ ! $REPLY =~ ^[Nn]$ ]]; then
  echo -e "${G}Uninstalling packages...${N}"
  printf 'y\n' | dev_install --uninstall
  rm -f /mnt/stateful_partition/.devinstall_complete
else
  echo -e "${B}Keeping packages installed.${N}"
fi
  echo -e "Switching active kernel..."
  cgpt add "$intdis" -i "$currentKern" -P 1 -S 1 -T 0 \
    || fail "${R}cgpt: failed to demote kernel ${currentKern}${N}"
  cgpt add "$intdis" -i "$newKern" -P 15 -S 0 -T 15 \
    || fail "${R}cgpt: failed to promote kernel ${newKern}${N}"
  echo -e "${G}Done! Switched to kernel on ${intdis_prefix}${newKern}${N}"
  sync
  sleep 3
  reboot -f
  exit
}

toggleEnrollment(){
  runscript /usr/bin/toggle-enrollment.sh
}

localAcc() {
  runscriptnoroot /usr/bin/localacc.sh
}

features() {
  runscript /usr/bin/features.sh
}

# -- MAIN SCRIPT --

tput civis # :whale:

menu_reset() {
  menuText="\nModmium Manager\n"
  options=("Update Modmium" "Change ChromeOS Version" "Swap Boot Priority" "Toggle Enrollment" "Add Local Account" "Feature Toggles" "Exit")
  functions=("updateModmium" "installCros" "toggleBootPriority" "toggleEnrollment" "localAcc" "features" "quit")
  num_options=${#options[@]}
}

menu_reset
clear
full_menu
tput cnorm
