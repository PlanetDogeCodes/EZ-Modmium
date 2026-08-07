#!/bin/bash
# =============================================================================
# EZ-Modmium — build-image.sh (recovery image builder)
# =============================================================================
# Forked from Modmium (https://github.com/CrOSmium/modmium).
#
# EZ-Modmium improvements over upstream:
#   * Sources build-utils/libmodmium.sh (shared helpers, config, logging)
#   * --dryrun : validate flags + dependencies without building
#   * --help : real usage with examples
#   * Structured logging to ./ez-modmium-build-<ts>.log
#   * Mode-aware file permissions (no more blanket chmod 777)
#   * Safe find -print0 loops
#   * All variables quoted; set -uo pipefail
#   * SHA-256 of the final image written next to it
#   * --resolution WxH flag to skip the interactive bootsplash prompt
# =============================================================================

set -uo pipefail

# SIGINT/SIGTERM trap
_ez_sigint() {
  log_warn "Interrupted by user — cleaning up..."
  [[ -n "${loopDev:-}" ]] && losetup -d "$loopDev" 2>/dev/null || true
  umount mnt 2>/dev/null || true
  exit 1
}
trap _ez_sigint INT TERM

# ---------------------------------------------------------------------------
# Early --help/-h catch (before any sudo/dir checks)
# ---------------------------------------------------------------------------
ez_build_help() {
  cat <<'EOF'
EZ-Modmium — recovery image builder

USAGE:
  sudo ./build-image.sh -i <path/to/recovery.bin> [flags]
  sudo ./build-image.sh -b <board> -v <version> [flags]

REQUIRED (one of):
  -i, --image <path>      Path to a local recovery image .bin
  -b, --board <name>      Board to autobuild (e.g. corsola) — lowercase
  -v, --version <milestone> ChromeOS milestone (e.g. 138)

OPTIONAL:
  -k, --kernver <hex>     Override kernver (hex, no 0x, max 2 digits, e.g. 7)
  -u, --userkeys          Generate fresh random signing keys (saved to
                          build-utils/keys/userkeys/ — BACK THESE UP).
                          If passed alone, only generates + backs up keys.
  -ba,--backup            Back up generated user keys to USB (default: true)
  -j, --json <path>       Path to chrome://policy exported JSON for enterprise
                          extensions / OpenNetworkConfiguration
  -s, --bootsplash        Convert bootsplash/<branch>/*.svg to PNG and bundle
                          (requires inkscape)
      --resolution WxH    Bootsplash resolution (skip interactive prompt).
                          Use 'auto' to detect from the connected display.
  -n, --dryrun            Validate flags + dependencies, do not build
                          (alias: --dry-run)
  -h, --help              Show this help

EXAMPLES:
  # Autobuild for corsola, ChromeOS 138, stable branch:
  sudo ./build-image.sh -b corsola -v 138

  # Use a local image, install enterprise policies:
  sudo ./build-image.sh -i recovery.bin -j policies.json

  # Generate user keys only (no image):
  sudo ./build-image.sh -u

  # Build with custom bootsplash at known resolution:
  sudo ./build-image.sh -b brya -v 138 -s --resolution 1920x1080

  # Pre-flight check:
  sudo ./build-image.sh -b corsola -v 138 --dryrun
EOF
}

for _a in "$@"; do
  case "$_a" in
    --help|-h) ez_build_help; exit 0 ;;
  esac
done
unset _a

DEPENDENCIES="bsdtar curl file futility jq pv wget"

# Pre-flight: source common_minimal + common_modmium (which sources libmodmium)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/build-utils/common_minimal.sh"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/build-utils/common_modmium.sh"
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "stable")

# Redirect build log alongside the source
EZ_LOG_FILE="${EZ_LOG_FILE:-${PWD}/ez-modmium-build-$(date +%Y%m%d-%H%M%S).log}"
_log_init 2>/dev/null || true
log "INFO" "EZ-Modmium build-image.sh starting (branch=$branch)"

# Default loopDev so the cleanup trap doesn't trip set -u
loopDev=""

asUser() {
  silence su "$USER" -c "$1"
}

checkDependencies() {
  local dep shouldExit=false
  for dep in $DEPENDENCIES; do
    if ! silence command -v "$dep"; then
      log_error "${dep} not found."
      shouldExit=true
    fi
  done
  if [[ "$shouldExit" == "true" ]]; then
    fail "Exiting... (run tools/install-deps.sh to install missing deps)"
  fi
}

cleanup() {
  silence umount mnt 2>/dev/null || true
  [[ -n "${loopDev:-}" ]] && silence losetup -d "$loopDev" 2>/dev/null || true
  silence rm -rf mnt .realuser 2>/dev/null || true
  # Only remove mktemp-style dirs, never /tmp itself
  while IFS= read -r -d '' tempbin; do
    local _parent="${tempbin%/*}"
    [[ "$_parent" == /tmp/tmp.* ]] && silence rm -rf "$_parent"
  done < <(find /tmp -mindepth 2 -maxdepth 2 -name 'modmium*.bin' -print0 2>/dev/null)
}
trap cleanup EXIT

credits() {
  cat <<EOF
${R}mariahscarycarey${N}: Lead developer; image builder, device policy editor frontend, ChromeOS version switcher, most bugfixing.
${B}dmd${N}: Project lead; MOSH/libmosh, base devfw & MPkeys manager, chromeos-setdevpasswd, base ChromeOS updater.
${Y}lxrd${N}: policy-test-tool, streaming ChromeOS updates, Nix integration.
${P}codenerd87${N}: MPkeys restoration, devfw on geralt, firmware manager.
${P}kxtzownsu${N}: code review (until 2026-05-26).
${B}xz8f${N}: custom bootsplashes.
${B}con${N}: emotional support + minor bugs.
${B}Casper1051, Moonstone, pilgorr${N}: default bootsplashes.
${G}EZ-Modmium${N}: refactor, hardening, UX improvements (community fork).
EOF
}

fail() {
  log "ERROR" "$1"
  echo -e "$1"
  cleanup
  exit 1
}

silence() {
  "$@" >/dev/null 2>&1
}

if [[ "$(basename "$PWD")" != "modmium" && "${SKIP_DIRCHECK:-0}" != "1" ]]; then
  fail "Please run this script in the cloned directory (modmium/)"
fi
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root, elevating with sudo..."
  echo "$USER" > .realuser
  sudo "$0" "$@"
  exit $?
fi
if [[ -f .realuser ]]; then
  USER=$(cat .realuser)
fi

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------
getFlags() {
  load_shflags
  FLAGS_HELP="$(ez_build_help)"
  DEFINE_string image "" "Path to recovery image (use if not autobuilding)" "i"
  DEFINE_string board "" "Name of board to autobuild" "b"
  DEFINE_string version "" "MILESTONE of version to autobuild" "v"
  DEFINE_string kernver "" "Kernver to sign kernels with (hex, no 0x prefix, max 2 digits)" "k"
  DEFINE_boolean userkeys "$FLAGS_FALSE" "Generate user-made signing keys" "u"
  DEFINE_boolean backup "$FLAGS_TRUE" "Back up user keys to USB" "ba"
  DEFINE_string json "" "Path to chrome://policy exported json (optional)" "j"
  DEFINE_boolean bootsplash "$FLAGS_FALSE" "Install bootsplashes (requires inkscape)" "s"
  DEFINE_string resolution "" "Bootsplash resolution WxH or 'auto' (skip prompt)" ""
  DEFINE_boolean dryrun "$FLAGS_FALSE" "Validate without building" "n"

  # Translate hyphenated aliases (shflags derives long name from var name)
  local _ez_args=()
  for _a in "$@"; do
    case "$_a" in
      --dry-run) _ez_args+=("--dryrun") ;;
      *) _ez_args+=("$_a") ;;
    esac
  done
  unset _a
  FLAGS "${_ez_args[@]}" || exit $?
  unset _ez_args

  # Default FLAGS_minios (only set inside checkFlagValidity when -i or -b is used)
  : "${FLAGS_minios:=$FLAGS_FALSE}"

  if ! [[
    ( -z "$FLAGS_board" && -z "$FLAGS_version" && -n "$FLAGS_image" ) ||
    ( -n "$FLAGS_board" && -n "$FLAGS_version" && -z "$FLAGS_image" ) ||
    ( "$FLAGS_userkeys" -eq "$FLAGS_TRUE" )
    ]]; then
    flags_help
    exit 1
  fi
}

checkFlagValidity() {
  if [[ -n "$FLAGS_image" && ! -f "$FLAGS_image" ]]; then
    fail "${R}File not found: $FLAGS_image${N}"
  elif [[ -n "$FLAGS_image" ]]; then
    local localLoopDev board candidate
    localLoopDev=$(losetup -Pf --show "$FLAGS_image")
    mount -o ro "${localLoopDev}p3" mnt --mkdir
    board=$(grep CHROMEOS_RELEASE_DESCRIPTION mnt/etc/lsb-release | awk '{print $NF}')
    for candidate in $minios_boards; do
      if [[ "$board" == "$candidate" ]]; then FLAGS_minios=$FLAGS_TRUE; break; else FLAGS_minios=$FLAGS_FALSE; fi
    done
    umount mnt
    rm -rf mnt
    losetup -d "$localLoopDev"
  fi

  if [[ -n "$FLAGS_version" && ! "$FLAGS_version" =~ ^[0-9]+$ ]]; then
    fail "${R}Version not a natural number${N}, provide the ChromeOS MILESTONE."
  fi
  if [[ -n "$FLAGS_version" && "$FLAGS_version" -lt "$EZ_MIN_VERSION" ]]; then
    echo -e "${R}Versions below $EZ_MIN_VERSION are NOT supported.${B} Continue anyway? [y/N]${N}"
    read -rep ""
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
      echo -e "${B}Continuing...${N}"
    else
      fail "${R}Exiting...${N}"
    fi
  fi
  if [[ -n "$FLAGS_board" ]]; then
    FLAGS_board=$(echo "$FLAGS_board" | tr '[:upper:]' '[:lower:]')
    local boardInList=$FLAGS_FALSE
    local board
    for board in $boards; do
      [[ "$FLAGS_board" == "$board" ]] && boardInList=$FLAGS_TRUE
    done
    [[ "$boardInList" == "$FLAGS_TRUE" ]] || fail "${R}Invalid board name.${N} See ${B}https://dl.crosbreaker.com/recovery-images${N}"
    for board in $minios_boards; do
      if [[ "$FLAGS_board" == "$board" ]]; then FLAGS_minios=$FLAGS_TRUE; break; else FLAGS_minios=$FLAGS_FALSE; fi
    done
  fi
  if [[ -n "$FLAGS_kernver" ]]; then
    if ! [[ "$FLAGS_kernver" =~ ^[0-9A-Fa-f]{1,}$ && ${#FLAGS_kernver} -lt 3 ]]; then
      fail "${R}Kernver is not hex or contains leading \"0x\".${N}"
    fi
  fi
  if [[ -n "$FLAGS_json" && ! -f "$FLAGS_json" ]]; then
    fail "${R}Policy json file doesn't exist: $FLAGS_json${N}"
  fi
  if [[ "$FLAGS_bootsplash" == "$FLAGS_TRUE" ]]; then
    if ! silence inkscape --version; then
      fail "${R}Inkscape NOT installed. Run tools/install-deps.sh --with-bootsplash.${N}"
    fi
  fi
  if [[ "$FLAGS_bootsplash" == "$FLAGS_TRUE" && ! -d bootsplash/ ]]; then
    fail "${R}Bootsplash directory doesn't exist.${N}"
  elif [[ "$FLAGS_bootsplash" == "$FLAGS_TRUE" && -z "$(find "bootsplash/$branch" -mindepth 1 2>/dev/null)" ]]; then
    fail "${R}Bootsplash directory is empty or doesn't have $branch bootsplashes.${N}"
  fi
  if [[ -n "$FLAGS_resolution" ]]; then
    # Allow "auto" (detected at build time) or WxH format
    if [[ "$FLAGS_resolution" != "auto" ]] && ! [[ "$FLAGS_resolution" =~ ^[0-9]+x[0-9]+$ ]]; then
      fail "${R}Invalid --resolution format. Use WxH (e.g. 1920x1080) or 'auto'.${N}"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Build functions
# ---------------------------------------------------------------------------
removeVerity() {
  if [[ "$FLAGS_userkeys" == "$FLAGS_TRUE" ]]; then
    keydir=build-utils/keys/userkeys
  else
    keydir=build-utils/keys/devkeys
  fi

  if [[ -n "$FLAGS_image" ]]; then
    local tmp_free img_size
    tmp_free=$(($(df /tmp | awk '{print $4}' | tail -n 1) * 1024))
    img_size=$(du -b "$FLAGS_image" | awk '{print $1}')
    if [[ "$tmp_free" -gt "$img_size" ]]; then
      tempDir=$(mktemp -d)
    else
      echo -e "${B}/tmp is not large enough, using disk...${N}"
      mkdir -p tmp
      tempDir="tmp"
    fi
    newImage="$tempDir/modmium-$(basename "$FLAGS_image")"
    echo -e "${G}Copying image to tempdir, ${R}this may take a while...${N}"
    cp "$FLAGS_image" "$newImage"
    sync
  else
    newImage=modmium.bin
    mv "$downloadedImage" "$newImage"
  fi

  echo -e "${G}Setting up loop device...${N}"
  loopDev=$(losetup -Pf --show "$newImage" || fail "${R}Failed to set up loop device, exiting...${N}")
  echo -e "${G}Disabling verity...${N}"
  silence build-utils/ssd_util.sh -i "$loopDev" -r --partitions 2 --recovery_key --keys "$keydir" \
    || fail "${R}ssd_util.sh failed for partition 2${N}"
  silence build-utils/ssd_util.sh -i "$loopDev" -r --partitions 4 --keys "$keydir" \
    || fail "${R}ssd_util.sh failed for partition 4${N}"

  local rootUUID part kernver
  rootUUID=$(blkid -s PARTUUID -o value "${loopDev}p3")
  for part in 2 4; do
    echo -e "${G}Dumping and modifying kernel ${part} commandline...${N}"
    futility dump_kernel_config "${loopDev}p$part" > "config_${part}.txt"
    [[ "$part" -eq 2 ]] && sed -i "s|root=PARTUUID=[^ ]*|root=PARTUUID=$rootUUID|g" config_2.txt
    [[ "$part" -eq 4 ]] && sed -i "s|cros_secure|cros_debug|g" config_4.txt

    if [[ -n "$FLAGS_kernver" ]]; then
      kernver=$FLAGS_kernver
    else
      kernver=$(futility show "${loopDev}p$part" | grep "Kernel version" | sed 's/^.*:      //')
    fi

    echo -e "${G}Resigning kernel ${part} with modified commandline...${N}"
    futility vbutil_kernel --repack "${loopDev}p$part" \
      --keyblock "${keydir}/$([[ $part -eq 2 ]] && echo "recovery_kernel.keyblock" || echo "kernel.keyblock")" \
      --signprivate "${keydir}/$([[ $part -eq 2 ]] && echo "recovery_kernel_data_key.vbprivk" || echo "kernel_data_key.vbprivk")" \
      --config "config_${part}.txt" \
      --version "$kernver" \
      --oldblob "${loopDev}p$part" \
      || fail "${R}futility vbutil_kernel --repack failed for partition $part${N}"
  done

  if [[ "$FLAGS_minios" == "$FLAGS_TRUE" ]]; then
    for part in 9 10; do
      echo -e "${G}Resigning miniOS kernel ${part}...${N}"
      futility dump_kernel_config "${loopDev}p$part" > "config_${part}.txt"
      sed -i "s|cros_secure|cros_debug|g" "config_${part}.txt"
      futility vbutil_kernel --repack "${loopDev}p$part" \
        --keyblock "${keydir}/minios_kernel.keyblock" \
        --signprivate "${keydir}/minios_kernel_data_key.vbprivk" \
        --config "config_${part}.txt" \
        --oldblob "${loopDev}p$part" \
        || fail "${R}futility vbutil_kernel --repack failed for miniOS partition $part${N}"
    done
  fi

  echo -e "${G}Cleaning up kernel backups and configs...${N}"
  rm -rf cros_sign_backups config*
}

dropModFiles() {
  echo -e "${G}Mounting loop device...${N}"
  mount "${loopDev}p3" mnt --mkdir \
    || fail "${R}Failed to mount ${loopDev}p3 on mnt${N}"

  if [[ ! -f mod-files/root/policy.json ]]; then
    if [[ -z "$FLAGS_json" ]]; then
      echo -e "${B}Policy json not found — running policy editor will NOT install enterprise extensions. Continue anyway? (y/N)${N}"
      read -n 1 -r
      if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo
        fail "${R}Cleaning up and exiting...${N}"
      else
        echo
        echo -e "${G}Continuing...${N}"
      fi
    else
      echo -e "${B}Moving policy json to mod-files/root/policy.json...${N}"
      mv "$FLAGS_json" mod-files/root/policy.json
    fi
  fi

  # EZ improvement: shared, mode-aware, space-safe drop_mod_files
  drop_mod_files "$(pwd)/mod-files" "$(pwd)/mnt" "$(pwd)"

  [[ -d build-utils/keys/userkeys ]] && cp -r build-utils/keys/userkeys mnt/usr/share/vboot
  sleep 0.5

  echo -e "${G}Cleaning up...${N}"
  [[ "$FLAGS_bootsplash" == "$FLAGS_TRUE" ]] && rm -rf mod-files/bootsplash/*.png
  echo "$branch" > mnt/.branch

  local _tries=0
  while mountpoint -q mnt && [[ $_tries -lt 10 ]]; do
    silence umount mnt
    _tries=$((_tries + 1))
    sleep 1
  done
  if mountpoint -q mnt; then
    log_warn "Could not umount mnt after 10 attempts; forcing lazy umount"
    silence umount -l mnt
  fi

  losetup -d "$loopDev"
  if [[ -n "$FLAGS_image" ]]; then
    echo -e "${G}Moving image to $(basename "$newImage")...${N}"
    mv "$newImage" "$(basename "$newImage")"
    sync
    rm -rf "$tempDir" mnt
  else
    rm -rf mnt
  fi
  rm -rf .realuser

  # EZ improvement: write SHA-256 of the final image
  local final_image
  final_image="$(basename "$newImage")"
  if [[ -f "$final_image" ]]; then
    local final_sha
    final_sha=$(sha256_of "$final_image")
    echo "$final_sha  $final_image" > "${final_image}.sha256"
    log_info "Final image SHA-256: $final_sha"
    echo -e "${G}Wrote ${final_image}.sha256${N}"
  fi

  echo -e "${G}Finished!${N}"
}

# ---------------------------------------------------------------------------
# Optional build functions
# ---------------------------------------------------------------------------
bootsplash() {
  local width height
  if [[ -n "$FLAGS_resolution" ]]; then
    # EZ improvement: --resolution auto — detect from connected display
    if [[ "$FLAGS_resolution" == "auto" ]]; then
      local detected
      detected=$(detect_resolution 2>/dev/null || true)
      if [[ -n "$detected" ]]; then
        FLAGS_resolution="$detected"
        log_info "Auto-detected screen resolution: ${G}$detected${N}"
      else
        log_warn "Could not auto-detect resolution (no display connected or not a Chromebook)."
        FLAGS_resolution=""
      fi
    fi
    if [[ -n "$FLAGS_resolution" ]]; then
      width="${FLAGS_resolution%x*}"
      height="${FLAGS_resolution#*x}"
      log_info "Using --resolution $width x $height"
    fi
  fi
  if [[ -z "${width:-}" || -z "${height:-}" ]]; then
    echo -e "${G}Input your chromebook's resolution (W H, e.g. 1920 1200)${N}"
    local unresolved=$FLAGS_TRUE
    while [[ "$unresolved" == "$FLAGS_TRUE" ]]; do
      echo -ne "Resolution: "
      read -rep "" width height
      local dim valid_w=0 valid_h=0
      for dim in width height; do
        if [[ -n "${!dim:-}" && "${!dim}" =~ ^[0-9]+$ && "${!dim}" -lt 10000 ]]; then
          [[ "$dim" == "width" ]] && valid_w=1 || valid_h=1
        else
          echo -e "${R}Invalid $dim!${N}"
        fi
      done
      [[ "$valid_w" == 1 && "$valid_h" == 1 ]] && unresolved=$FLAGS_FALSE
    done
  fi

  local splash
  while IFS= read -r -d '' splash; do
    echo -e "Converting ${G}$(basename "$splash")${N} to png..."
    mkdir -p mod-files/bootsplash
    silence inkscape -w "$width" -h "$height" "$splash" -o "mod-files/bootsplash/$(basename "${splash%.*}.png")"
  done < <(find "bootsplash/$branch" -mindepth 1 -name '*.svg' -print0)
}

genUserKeys() {
  echo -e "${G}Generating user keys...${N}"
  silence pushd build-utils/keygeneration
  [[ -d ApRoV1Signing-PreMP ]] && rm -rf ApRoV1Signing-PreMP
  asUser "bash make_arv_root.sh" || fail "${R}make_arv_root.sh failed${N}"
  asUser "bash create_new_keys.sh --arv-root-path ./ApRoV1Signing-PreMP" \
    || fail "${R}create_new_keys.sh failed${N}"
  cd accessory || fail "cd accessory failed"
  asUser "bash create_new_ec_efs_key.sh" || fail "${R}create_new_ec_efs_key.sh failed${N}"
  asUser "openssl genrsa -f4 -out ec_data_key.pem 2048 && futility create --desc \"EC Data Key\" --hash_alg 2 ec_data_key.pem ec_data_key" \
    || fail "${R}ec_data_key generation failed${N}"
  cd .. || fail "cd .. failed"
  asUser "mkdir -p ../keys/userkeys" || fail "${R}mkdir userkeys failed${N}"
  local key
  while IFS= read -r -d '' key; do
    asUser "mv \"$key\" ../keys/userkeys/" || fail "${R}mv key failed: $key${N}"
  done < <(find . -mindepth 1 \( -name '*.vbpubk' -o -name '*.vbprivk' -o -name '*.vbprik2' -o -name '*.vbpubk2' -o -name '*.keyblock' -o -name '*ec_*' \) ! -name '*ec_*.sh' -print0)
  silence popd || true
}

backupUserKeys() {
  local BACKUPDIR=/tmp/backupdir
  echo -e "These are the external drives connected to your device:"
  lsblk -dpno NAME,SIZE,MODEL | grep "/dev/sd"
  echo -e "What drive would you like write the backup onto? Type /dev/sdX or sdX ${R}(THIS WILL ERASE THE DRIVE!!!!)${N}"
  read -ep "Drive: " driveloc
  driveloc="${driveloc%/}"
  echo -e "Are you absolutely ${UN}CERTAIN${RUN} you want to ${R}WIPE ${driveloc}${N}?"
  read -r -n 2 -s -p "(Press yy to continue)"; echo
  if [[ "$REPLY" != yy ]]; then
    fail "${R}Exiting...${N}"
  fi
  local fulldev="$driveloc"
  [[ "$driveloc" != *"/dev/"* ]] && fulldev="/dev/$driveloc"
  # Validate: must be a block device, must NOT be the internal disk
  [[ -b "$fulldev" ]] || fail "${R}$fulldev is not a block device.${N}"
  local _intdisk
  _intdisk=$(get_largest_cros_blockdev 2>/dev/null || echo "")
  [[ -n "$_intdisk" && "$fulldev" == "$_intdisk" ]] && fail "${R}REFUSING TO WIPE THE INTERNAL DISK ($fulldev).${N}"
  if ! mkfs.vfat -I -F 32 "$fulldev"; then fail "${R}Unable to wipe device...${N}"; fi
  mkdir -p "$BACKUPDIR"
  if ! mount "$fulldev" "$BACKUPDIR"; then fail "${R}Unable to mount device...${N}"; fi
  DRIVEBACKUP=1
  sync
  if ! [[ -d "$BACKUPDIR" && -w "$BACKUPDIR" ]]; then
    fail "${R}Unable to write to backup.${N}"
  fi
  echo -e "${G}Backing up signing keys...${N}"
  cp -r build-utils/keys/userkeys "$BACKUPDIR"
  # EZ improvement: also write a sha256 manifest
  (cd "$BACKUPDIR/userkeys" && sha256sum * > userkeys.sha256 2>/dev/null) || true
  umount "$BACKUPDIR"
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
downloadImage() {
  local recoveryUrl
  log_step "Resolving recovery image URL for board=$FLAGS_board version=$FLAGS_version..."

  # EZ improvement: download data.json via fetch_and_verify (verifies SHA-256
  # against a pinned hash if EZ_DATA_JSON_PINNED_SHA256 is set, and checks for
  # a GPG-signed manifest if present).
  local data_json_tmp
  data_json_tmp=$(mktemp)
  fetch_and_verify "$EZ_RELEASES_JSON_URL" "$data_json_tmp"
  verify_data_json "$data_json_tmp" || {
    rm -f "$data_json_tmp"
    fail "${R}data.json verification failed — possible CDN compromise. Aborting.${N}"
  }

  recoveryUrl=$(jq -r --arg board "$FLAGS_board" --arg ver "$FLAGS_version" '
    .[$board].images // []
    | map(select(
    .channel == "stable-channel" and
    (.chrome_version | startswith($ver + "."))
    ))
    | sort_by(.last_modified)
    | last
    | .url // empty
    ' "$data_json_tmp" 2>/dev/null)
  rm -f "$data_json_tmp"

  if [[ -n "$recoveryUrl" && "$recoveryUrl" =~ dl\.google\.com ]]; then
    log_info "Recovery URL found!"
  else
    fail "${R}Recovery URL not found or invalid :(${N}"
  fi

  # EZ improvement: download the recovery image via fetch_and_verify, which
  # checks for a sidecar .sha256 manifest (and optional GPG signature).
  log_step "Downloading image..."
  fetch_and_verify "$recoveryUrl" recovery.zip

  echo -e "${G}Unzipping image...${N}"
  pv recovery.zip | bsdtar -Oxf - > recovery.bin \
    || fail "${R}Failed to unzip recovery image (corrupt zip?)${N}"
  [[ -s recovery.bin ]] || fail "${R}Unzipped recovery.bin is empty${N}"
  downloadedImage="recovery.bin"
  echo -e "${G}Removing zip file...${N}"
  rm -rf recovery.zip
  log_info "Done! Continuing to build..."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  getFlags "$@"
  checkFlagValidity
  checkDependencies

  if [[ "$FLAGS_dryrun" == "$FLAGS_TRUE" ]]; then
    log_info "${G}[DRY-RUN]${N} Flags + dependencies validated. No build performed."
    log_info "Would build: image=$FLAGS_image board=$FLAGS_board version=$FLAGS_version userkeys=$FLAGS_userkeys bootsplash=$FLAGS_bootsplash json=$FLAGS_json kernver=$FLAGS_kernver"
    exit 0
  fi

  if [[ "$FLAGS_userkeys" == "$FLAGS_TRUE" ]]; then
    if [[ ! -d build-utils/keys/userkeys ]]; then
      genUserKeys
    else
      echo -e "${G}Userkeys already present in build-utils/keys/userkeys${N}"
    fi
    if [[ -z "$FLAGS_image" && -z "$FLAGS_board" ]]; then
      return 0
    fi
    [[ "$FLAGS_backup" -eq "$FLAGS_TRUE" ]] && backupUserKeys
  fi

  [[ "$FLAGS_bootsplash" == "$FLAGS_TRUE" ]] && bootsplash
  [[ -n "$FLAGS_board" && -n "$FLAGS_version" ]] && downloadImage
  removeVerity
  echo -e "${G}Enabling RW mount for p3${N}"
  enable_rw_mount "${loopDev}p3"
  dropModFiles
}

main "$@"
credits
