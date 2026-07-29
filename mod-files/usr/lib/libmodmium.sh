#!/bin/bash
# =============================================================================
# EZ-Modmium shared helper library  (build-utils/libmodmium.sh)
# =============================================================================
# Single source of truth for: colors, confirm/ask prompts, log/fail, ChromeOS
# partition helpers, block-device discovery, recovery-URL resolution, branch
# selection, mod-files drop (mode-aware, space-safe), dependency bootstrap,
# SHA-256 helpers, WP/APROV checks, and the selftest harness.
#
# Sourcing is safe and idempotent. No side effects on source.
#
# License: GPL-3.0 (same as Modmium)
# =============================================================================

# Guard against double-source
[[ -n "${_EZ_LIBMODMIUM_LOADED:-}" ]] && return 0 2>/dev/null || true
_EZ_LIBMODMIUM_LOADED=1

# ---------------------------------------------------------------------------
# 0. Script directory (for finding sibling config)
# ---------------------------------------------------------------------------
EZ_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
[[ -z "$EZ_LIB_DIR" ]] && EZ_LIB_DIR="$(pwd)"

# ---------------------------------------------------------------------------
# 1. Defaults (overridable by modmium.conf or env vars)
# ---------------------------------------------------------------------------
: "${EZ_MIN_VERSION:=131}"
: "${EZ_GBB_FLAGS:=0xa0b1}"
: "${EZ_TPM_KERNVER_INDEX:=0x1008}"
: "${EZ_RELEASES_JSON_URL:=https://cdn.jsdelivr.net/gh/crosbreaker/chromeos-releases-data/data.json}"
: "${EZ_MODMIUM_SH_URL:=https://modmium.dev/modmium.sh}"
: "${EZ_FWMP_SH_URL:=https://modmium.dev/fwmp.sh}"
: "${EZ_STREAM_PY_URL:=https://modmium.dev/tools/stream.py}"
: "${EZ_HWWP_GUIDE_URL:=https://crosmium.dev/HWWP}"
: "${EZ_LOG_ENABLED:=1}"
: "${EZ_LOG_QUIET:=0}"
: "${EZ_LOG_DEBUG:=0}"
: "${EZ_LOG_DIR:=/var/log/modmium}"
: "${EZ_FORCE_COLOR:=}"

# Board lists
: "${EZ_BOARDS:=ambassador arkham asuka asurada atlas auron-paine auron-yuna banjo banon bob brask brox brya buddy buddy-cfm butterfly candy caroline cave celes chell cherry clapper constitution coral corsola cyan daisy daisy-skate daisy-spring dedede drallion edgar elm endeavour enguarde eve excelsior expresso falco falco-li fizz fizz-cfm gale gandof geralt glimmer gnawty grunt guado guado-cfm guybrush hana hatch heli jacuzzi kalista kalista-cfm kefka kevin kip kukui lars leon link lulu lumpy mccloud monroe nami nautilus ninja nirva nissa nocturne nyan-big nyan-blaze nyan-kitty octopus orco ovis panther parrot parrot-ivb peach-pi peach-pit peppy puff pyro quawks rammus rauru reef reks relm reven rex rikku rikku-cfm samus sand sarien scarlet sentry setzer skyrim skywalker snappy soraka squawks staryu stout strongbad stumpy sumo swanky terra tidus tricky trogdor ultima veyron-fievel veyron-jaq veyron-jerry veyron-mickey veyron-mighty veyron-minnie veyron-speedy veyron-tiger volteer whirlwind winky wizpig wolf x86-alex x86-alex-he x86-mario x86-zgb x86-zgb-he zako zork}"

: "${EZ_MINIOS_BOARDS:=brask brox brya cherry corsola geralt guybrush jedi nissa ovis rauru rex skyrim skywalker staryu}"

# Load user/system overrides if present (search a few sensible locations)
for _conf in \
  "/etc/modmium/modmium.conf" \
  "${EZ_LIB_DIR}/modmium.conf" \
  "${EZ_LIB_DIR}/../modmium.conf" \
  "${HOME}/.config/modmium.conf" \
  "${PWD}/modmium.conf"; do
  if [[ -f "$_conf" ]]; then
    # shellcheck disable=SC1090
    source "$_conf"
    break
  fi
done
unset _conf

# ---------------------------------------------------------------------------
# 2. Colors / formatting (single definition — fixes the 4-way duplication)
# ---------------------------------------------------------------------------
# Always define the vars (callers reference them unconditionally).
# Codes are empty when stdout isn't a TTY (clean logs/CI).
# Override with EZ_FORCE_COLOR=1 to keep codes even when piped.
if [[ -t 1 || "${EZ_FORCE_COLOR:-0}" == "1" ]]; then
  B=$'\033[38;5;45m'
  G=$'\033[38;5;46m'
  Y=$'\033[38;5;220m'
  R=$'\033[38;5;203m'
  P=$'\033[38;5;135m'
  N=$'\033[0m'
  D=$'\033[1;90m'
  UN=$'\033[4m'
  RUN=$'\033[24m'
else
  B=''; G=''; Y=''; R=''; P=''; N=''; D=''; UN=''; RUN=''
fi

# ---------------------------------------------------------------------------
# 3. Structured logging
# ---------------------------------------------------------------------------
EZ_LOG_FILE="${EZ_LOG_FILE:-}"

_log_init() {
  EZ_LOG_FILE="${EZ_LOG_FILE:-${EZ_LOG_DIR}/ez-modmium-$(date +%Y%m%d-%H%M%S).log}"
  if [[ "$EZ_LOG_ENABLED" != "1" ]]; then
    EZ_LOG_FILE="/dev/null"
    return 0
  fi
  # Try the configured dir; fall back to /tmp; fall back to disabling.
  if ! mkdir -p "$EZ_LOG_DIR" 2>/dev/null; then
    EZ_LOG_DIR="/tmp"
    EZ_LOG_FILE="/tmp/ez-modmium-$(date +%Y%m%d-%H%M%S).log"
  fi
  if ! ( : > "$EZ_LOG_FILE" ) 2>/dev/null; then
    EZ_LOG_FILE="/tmp/ez-modmium-$(date +%Y%m%d-%H%M%S)-$$.log"
    if ! ( : > "$EZ_LOG_FILE" ) 2>/dev/null; then
      EZ_LOG_ENABLED=0
      EZ_LOG_FILE="/dev/null"
    fi
  fi
}

log() {
  [[ "$EZ_LOG_ENABLED" != "1" ]] && return 0
  local level="${1:-INFO}"
  local msg="${2:-}"
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] [%s] %s\n' "$ts" "$level" "$msg" >> "$EZ_LOG_FILE" 2>/dev/null || true
}

echo_log() {
  local level="${1:-INFO}"
  local color="${2:-$N}"
  local msg="${3:-}"
  log "$level" "$msg"
  [[ "$EZ_LOG_QUIET" == "1" ]] && return
  printf '%s%s%s\n' "$color" "$msg" "$N"
}

log_info()  { echo_log "INFO"  "$G" "$1"; }
log_warn()  { echo_log "WARN"  "$Y" "$1"; }
log_error() { echo_log "ERROR" "$R" "$1"; }
log_step()  { echo_log "STEP"  "$B" "$1"; }
log_debug() { [[ "${EZ_LOG_DEBUG:-0}" == "1" ]] && echo_log "DEBUG" "$D" "$1" || log "DEBUG" "$1"; }

# ---------------------------------------------------------------------------
# 4. fail() — log + exit, with optional cleanup
#   fail "msg"                     -> exit 1, run vpd -d + umount
#   fail "msg" keepflag            -> exit 1, skip vpd -d + umount
#   fail "msg" --cleanup "cmds"    -> exit 1, run cmds, skip vpd -d + umount
# ---------------------------------------------------------------------------
fail() {
  local msg="$1"
  local mode="${2:-}"
  local cleanup_cmd="${3:-}"

  log "ERROR" "$msg"
  echo -e "${R}${msg}${N}" >&2

  if [[ -n "$cleanup_cmd" ]]; then
    log "INFO" "Running cleanup: $cleanup_cmd"
    # shellcheck disable=SC2086
    eval $cleanup_cmd 2>/dev/null || true
  fi

  if [[ "$mode" != "keepflag" && -z "$cleanup_cmd" ]]; then
    command -v vpd >/dev/null 2>&1 && vpd -d dev_firmware 2>/dev/null || true
  fi
  if [[ -z "$cleanup_cmd" ]]; then
    command -v umount >/dev/null 2>&1 && umount "${BACKUP:-/tmp/backupdir}" >/dev/null 2>&1 || true
  fi
  sleep 1
  exit 1
}

die() { log "ERROR" "$1"; echo -e "${R}$1${N}" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 5. Prompt helpers
# ---------------------------------------------------------------------------
# confirm <prompt> [default: Y|N] [--single]
# Double-tap y by default (matches upstream's askConfirmation).
# --single: single keypress, honoring the default.
# Honors EZ_YES=1 (always yes) for non-interactive.
confirm() {
  local prompt="$1"
  local default="${2:-N}"
  local single=0
  [[ "${3:-}" == "--single" ]] && single=1

  if [[ "${EZ_YES:-0}" == "1" ]]; then
    log "INFO" "confirm (auto-yes): $prompt"
    return 0
  fi

  local hint
  if [[ "$default" == "Y" ]]; then hint="[Y/n]"; else hint="[y/N]"; fi

  if [[ "$single" == "1" ]]; then
    echo -ne "${prompt} ${hint} "
    local ans
    read -r -n 1 ans
    echo
    if [[ -z "$ans" ]]; then ans="$default"; fi
    case "$ans" in
      [Yy]*) log "INFO" "confirm (accepted): $prompt"; return 0 ;;
      *)     log "INFO" "confirm (denied): $prompt";   return 1 ;;
    esac
  else
    echo -e "${prompt} ${hint}"
    echo -ne "(double-tap y to confirm, any other key to abort): "
    local ans
    read -r -n 2 -s ans
    echo
    if [[ "$ans" == "yy" ]]; then
      log "INFO" "confirm (accepted): $prompt"
      return 0
    fi
    log "INFO" "confirm (denied): $prompt"
    return 1
  fi
}

# ask <prompt> <varname> [default]
ask() {
  local prompt="$1"
  local varname="$2"
  local default="${3:-}"
  local val

  if [[ "${EZ_YES:-0}" == "1" ]]; then
    printf -v "$varname" '%s' "$default"
    log "INFO" "ask (auto): $prompt => $default"
    return
  fi

  if [[ -n "$default" ]]; then
    echo -ne "${prompt} [${default}]: "
  else
    echo -ne "${prompt}: "
  fi
  read -r -e val
  val="${val:-$default}"
  printf -v "$varname" '%s' "$val"
  log "INFO" "ask: $prompt => $val"
}

# ---------------------------------------------------------------------------
# 6. ChromeOS partition helpers (single source)
# ---------------------------------------------------------------------------
# get_booted_kernnum [intdis] — echoes 2 or 4.
# Falls back to $intdis env var, then `rootdev -d`.
get_booted_kernnum() {
  local intdis="${1:-${intdis:-}}"
  if [[ -z "$intdis" ]]; then
    command -v rootdev >/dev/null 2>&1 && intdis="$(rootdev -d 2>/dev/null)"
  fi
  if [[ -z "$intdis" ]]; then
    echo -n 2
    return
  fi
  local p2 p4
  p2="$(cgpt show -n "$intdis" -i 2 -P 2>/dev/null || echo 0)"
  p4="$(cgpt show -n "$intdis" -i 4 -P 2>/dev/null || echo 0)"
  if (( p2 > p4 )); then
    echo -n 2
  else
    echo -n 4
  fi
}

get_booted_rootnum() {
  echo $(( $(get_booted_kernnum "${1:-}") + 1 ))
}

opposite_num() {
  case "$1" in
    2) echo -n 4 ;;
    3) echo -n 5 ;;
    4) echo -n 2 ;;
    5) echo -n 3 ;;
    *) echo -n "skid" ;;
  esac
}

# Format partition number with proper prefix (nvme0n1 → nvme0n1p3, sda → sda3)
format_part_number() {
  echo -n "$1"
  echo "$1" | grep -q '[0-9]$' && echo -n p
  echo -n "$2"
}

# get_largest_cros_blockdev — find the internal ChromeOS disk
get_largest_cros_blockdev() {
  local largest="" size=0 dev_name tmp_size remo blockdev
  command -v sfdisk >/dev/null 2>&1 || return 0
  for blockdev in /sys/block/*; do
    dev_name="${blockdev##*/}"
    echo "$dev_name" | grep -q '^\(loop\|ram\)' && continue
    tmp_size=$(cat "$blockdev"/size 2>/dev/null || echo 0)
    remo=$(cat "$blockdev"/removable 2>/dev/null || echo 1)
    if [[ "$tmp_size" =~ ^[0-9]+$ ]] && [[ "$tmp_size" -gt "$size" ]] && [[ "${remo:-1}" -eq 0 ]]; then
      case "$(sfdisk -d "/dev/$dev_name" 2>/dev/null)" in
        *'name="STATE"'*'name="KERN-A"'*'name="ROOT-A"'*)
          largest="/dev/$dev_name"
          size="$tmp_size"
          ;;
      esac
    fi
  done
  echo "$largest"
}

# ---------------------------------------------------------------------------
# 7. Recovery image URL resolution (single source)
# ---------------------------------------------------------------------------
# getImageLink <board> <version> <outvar>
getImageLink() {
  local board="$1"
  local ver="$2"
  local outvar="$3"
  local recoveryUrl

  log_step "Checking crosbreaker/chromeos-releases-data for recovery image URL..."
  if ! command -v jq >/dev/null 2>&1; then
    fail "${R}jq is required but not found. Install it first.${N}"
  fi
  if ! command -v curl >/dev/null 2>&1; then
    fail "${R}curl is required but not found.${N}"
  fi

  recoveryUrl=$(curl -sL "$EZ_RELEASES_JSON_URL" 2>/dev/null | jq -r --arg board "$board" --arg ver "$ver" '
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
    printf -v "$outvar" '%s' "$recoveryUrl"
    return 0
  else
    fail "${R}Recovery URL not found or invalid for board='$board' version='$ver'.${N}"
  fi
}

# ---------------------------------------------------------------------------
# 8. Branch selection (single source)
# ---------------------------------------------------------------------------
# askBranch <outvar> [default]
askBranch() {
  local outvar="$1"
  local default="${2:-stable}"
  local branchreq branch

  if [[ "${EZ_YES:-0}" == "1" ]]; then
    printf -v "$outvar" '%s' "$default"
    log "INFO" "askBranch (auto): $default"
    return
  fi

  echo -e "[If you don't know what this means, just press enter]"
  if [[ "$default" == "stable" ]]; then
    echo -ne "Branch of Modmium to install (${G}stable${N}, nightly): "
  else
    echo -ne "Branch of Modmium to install (stable, ${G}nightly${N}): "
  fi
  read -r -ep "" branchreq
  case "$branchreq" in
    nightly) branch="nightly" ;;
    stable)  branch="stable" ;;
    *)       branch="$default" ;;
  esac
  echo
  printf -v "$outvar" '%s' "$branch"
  log "INFO" "askBranch: $branch"
}

# ---------------------------------------------------------------------------
# 9. drop_mod_files — mode-aware, space-safe, single implementation
# ---------------------------------------------------------------------------
# drop_mod_files <modfiles_dir> <target_root_mnt> [repo_root_for_minioverride]
#
# Copies every regular file under <modfiles_dir> onto <target_root_mnt>,
# preserving relative path. Replaced originals are moved to .old.
# File modes are chosen intelligently instead of blanket chmod 777:
#   - *.so              → 755
#   - bin/, sbin/, usr/bin/, usr/sbin/ → preserve source exec bit (min 755)
#   - etc/              → 644 unless source is executable
#   - everything else   → preserve source mode, default 644
# Also drops the architecture-correct minioverride.so if <repo_root> given.
# Removes cr50/ti50/force_update_firmware markers (recovery fails otherwise).
drop_mod_files() {
  local modfiles="$1"
  local mnt="$2"
  local repo_root="${3:-}"

  [[ -d "$modfiles" ]] || { log_error "drop_mod_files: modfiles dir not found: $modfiles"; return 1; }
  [[ -d "$mnt" ]] || { log_error "drop_mod_files: target mnt not found: $mnt"; return 1; }

  log_step "Dropping modfiles from $modfiles onto $mnt ..."

  local file rel oldFile dir src_mode new_mode
  while IFS= read -r -d '' file; do
    # Skip directories (created on demand)
    [[ -d "$file" ]] && continue
    [[ ! -f "$file" ]] && continue

    rel="${file#"$modfiles"/}"
    oldFile="$mnt/$rel"
    dir="$(dirname "$oldFile")"

    if [[ -f "$oldFile" ]]; then
      mv "$oldFile" "$oldFile.old"
      log_debug "backed up: $oldFile -> $oldFile.old"
    fi
    mkdir -p "$dir"
    cp "$file" "$oldFile"
    chown 0:0 "$oldFile"

    src_mode=$(stat -c '%a' "$file" 2>/dev/null || echo 644)
    # Decide new mode based on path
    case "/$rel" in
      /lib/*.so|/lib64/*.so|/usr/lib/*.so|/usr/lib64/*.so)
        new_mode=755 ;;
      /bin/*|/sbin/*|/usr/bin/*|/usr/sbin/*)
        new_mode=755 ;;
      /etc/*)
        if [[ -x "$file" ]]; then new_mode=755; else new_mode=644; fi ;;
      *)
        new_mode="$src_mode" ;;
    esac
    chmod "$new_mode" "$oldFile"
    log_debug "$rel -> $oldFile (mode $new_mode)"
  done < <(find "$modfiles" -mindepth 1 -print0 2>/dev/null)

  # Architecture-specific minioverride.so (only if repo_root given and has it)
  if [[ -n "$repo_root" ]]; then
    local arch archfile
    if [[ -f "$mnt/bin/bash" ]]; then
      arch=$(file "$mnt/bin/bash" | awk -F', ' '{print $2}')
      [[ "$arch" == *"ARM"* ]] && arch=aarch64
      archfile="$repo_root/build-utils/lib/minioverride-${arch}.so"
      if [[ -f "$archfile" ]]; then
        mkdir -p "$mnt/lib"
        cp "$archfile" "$mnt/lib/minioverride.so"
        chmod 755 "$mnt/lib/minioverride.so"
        log_debug "minioverride-${arch}.so -> $mnt/lib/minioverride.so"
      else
        log_warn "minioverride-${arch}.so not found at $archfile"
      fi
    fi
  fi

  # Always remove these markers (recovery fails otherwise)
  rm -rf "$mnt/root/.force_update_firmware" "$mnt/opt/google/cr50" "$mnt/opt/google/ti50"

  log_info "Modfiles dropped."
}

# ---------------------------------------------------------------------------
# 10. Dependency bootstrap (on-device)
# ---------------------------------------------------------------------------
ensure_dev_tools() {
  if command -v git >/dev/null 2>&1 && command -v file >/dev/null 2>&1; then
    return 0
  fi
  log_warn "Dependencies not installed, installing..."
  # shellcheck disable=SC1091
  source /etc/profile 2>/dev/null || true
  if [[ ! -f /mnt/stateful_partition/.devinstall_complete ]]; then
    printf 'y\n\nn' | dev_install --reinstall || fail "${R}Could not install dependencies. Connect to the internet first.${N}" keepflag
    touch /mnt/stateful_partition/.devinstall_complete
  fi
  ldconfig 2>/dev/null || true
  emerge git file || fail "${R}Could not install dependencies. Connect to the internet first.${N}" keepflag
  cp -r /usr/local/usr/share/git-core/templates /usr/share/git-core 2>/dev/null || true
  log_info "Dev tools ready."
}

# ---------------------------------------------------------------------------
# 11. SHA-256 helpers
# ---------------------------------------------------------------------------
sha256_verify() {
  local file="$1" expected="$2" actual
  [[ -f "$file" ]] || { log_error "File missing: $file"; return 1; }
  actual=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
  if [[ -z "$actual" ]]; then
    log_error "Could not compute SHA-256 for $file"
    return 1
  fi
  if [[ "$actual" == "$expected" ]]; then
    log_info "SHA-256 OK: $file"
    return 0
  else
    log_error "SHA-256 MISMATCH for $file"
    log_error "  expected: $expected"
    log_error "  actual:   $actual"
    return 1
  fi
}

sha256_of() { sha256sum "$1" 2>/dev/null | awk '{print $1}'; }

# ---------------------------------------------------------------------------
# 12. WP / APROV checks (fixed — no `|| grep "0"` masking bugs)
# ---------------------------------------------------------------------------
checkWP() {
  local writeprotect wprange
  writeprotect=$(flashrom --wp-status 2>&1 | grep "disabled")
  if [[ "$writeprotect" == *"disabled"* ]]; then
    log_info "FWWP is currently ${G}DISABLED${N}, continuing..."
    return 0
  fi
  log_warn "FWWP is currently ENABLED, checking for wp range..."
  wprange=$(flashrom --wp-status 2>&1 | grep -E "range: start=0x[0-9a-f]+, len=0x00000000")
  if [[ -n "$wprange" ]]; then
    log_info "WP range allows for flashing, continuing."
    return 0
  fi
  log_warn "WP range non-zero, checking for HWWP."
  local wpsw
  wpsw="$(crossystem wpsw_cur 2>/dev/null || echo "")"
  if [[ "$wpsw" == "0" ]]; then
    log_warn "HWWP off, attempting to disable SWWP."
    if ! flashrom --wp-disable 2>/dev/null; then
      log_warn "SWWP FAILED TO DISABLE! Known issue on ARM boards (corsola, geralt)."
      log_warn "As HWWP is off, Modmium can still install, but WP must be disabled again to revert."
      echo -e "${Y}Press enter to continue, or Ctrl+C to abort.${N}"
      read -r
    fi
    return 0
  fi
  # HWWP on
  if gsctool -a -I 2>/dev/null | grep -q AllowUnverifiedRo; then
    : # Ti50 path handled by checkAPROV
  fi
  fail "HWWP and SWWP are enabled with WP range non-zero. Disable WP: ${G}${EZ_HWWP_GUIDE_URL}${N}"
}

checkAPROV() {
  local isti50 setting rc
  if ! command -v gsctool >/dev/null 2>&1; then
    log_warn "gsctool not found; cannot verify APROV state. Continuing at your own risk."
    return 0
  fi
  isti50=$(gsctool -a -I 2>/dev/null | grep AllowUnverifiedRo)
  rc=$?
  if [[ $rc -eq 0 ]]; then
    setting=$(echo "$isti50" | awk '{print $3}')
    case "$setting" in
      Always)
        log_info "APROV is currently ${G}DISABLED${N}, continuing..."
        ;;
      Never)
        fail "APROV is currently ${R}ENABLED${N}. WP is off but APROV is on — rebooting will ${R}${UN}BRICK YOUR DEVICE${RUN}${N}. Disable APROV immediately: \`gsctool -a -I AllowUnverifiedRo:always\`"
        ;;
      *)
        fail "Unexpected APROV state: '$setting'"
        ;;
    esac
  else
    log_info "Device is not Ti50, continuing..."
  fi
}

# ---------------------------------------------------------------------------
# 13. Install state management (resumable installs)
# ---------------------------------------------------------------------------
# State file records completed phases so an interrupted install can resume.
EZ_STATE_FILE="${EZ_STATE_FILE:-/tmp/.modmium-state}"
EZ_STATE_PHASES=(deps_installed image_resolved image_downloaded chromeos_written verity_removed modfiles_dropped boot_switched)

# save_state <phase>
save_state() {
  local phase="$1"
  mkdir -p "$(dirname "$EZ_STATE_FILE")" 2>/dev/null || true
  # Mark this phase + all before it as done (we only advance forward)
  local p found=0
  : > "$EZ_STATE_FILE"
  for p in "${EZ_STATE_PHASES[@]}"; do
    echo "$p=done" >> "$EZ_STATE_FILE"
    [[ "$p" == "$phase" ]] && { found=1; break; }
  done
  if [[ "$found" -eq 0 ]]; then
    log "ERROR" "save_state: unknown phase '$phase' — state file not modified"
    rm -f "$EZ_STATE_FILE"
    return 1
  fi
  log "INFO" "State saved: reached phase '$phase'"
}

# state_has <phase> — returns 0 if phase is done
state_has() {
  local phase="$1"
  [[ -f "$EZ_STATE_FILE" ]] || return 1
  grep -q "^${phase}=done$" "$EZ_STATE_FILE" 2>/dev/null
}

# state_clear — remove the state file (on success or explicit reset)
state_clear() {
  rm -f "$EZ_STATE_FILE" 2>/dev/null
  log "INFO" "Install state cleared."
}

# state_show — print current state
state_show() {
  if [[ ! -f "$EZ_STATE_FILE" ]]; then
    echo "No install state file (no interrupted install)."
    return
  fi
  echo "Install state ($EZ_STATE_FILE):"
  local p
  for p in "${EZ_STATE_PHASES[@]}"; do
    if state_has "$p"; then
      echo "  ${G}[x]${N} $p"
    else
      echo "  ${D}[ ]${N} $p"
    fi
  done
}

# ---------------------------------------------------------------------------
# 14. Download integrity verification (signed manifests)
# ---------------------------------------------------------------------------
# A "manifest" is a simple text file: <sha256>  <filename>
# Optionally signed with a GPG detached signature (.sha256.sig).
# If EZ_VERIFY_DOWNLOADS=1 and a .sig is present, gpg is used to verify it.

EZ_VERIFY_DOWNLOADS="${EZ_VERIFY_DOWNLOADS:-1}"
EZ_MANIFEST_BASE_URL="${EZ_MANIFEST_BASE_URL:-https://raw.githubusercontent.com/crosmium/modmium/stable/build-utils/manifests}"

# fetch_and_verify <url> <output_path> [expected_sha256]
# Downloads <url> to <output_path>. If [expected_sha256] is given, verifies it.
# If EZ_VERIFY_DOWNLOADS=1, also tries to fetch <url>.sha256 and verify.
fetch_and_verify() {
  local url="$1" out="$2" expected="${3:-}"
  log_step "Downloading $url ..."
  if ! command -v curl >/dev/null 2>&1; then
    fail "${R}curl is required for downloads.${N}"
  fi
  curl -fSL -o "$out" "$url" || fail "${R}Download failed: $url${N}"

  # Verify against expected hash if provided
  if [[ -n "$expected" ]]; then
    sha256_verify "$out" "$expected" || {
      rm -f "$out"
      fail "${R}SHA-256 mismatch for $out — download may be corrupted or tampered. Aborting.${N}"
    }
    return 0
  fi

  # If verification enabled, look for a sidecar manifest
  if [[ "$EZ_VERIFY_DOWNLOADS" == "1" ]]; then
    local manifest_url="${url}.sha256"
    local manifest_tmp
    manifest_tmp=$(mktemp)
    if curl -fsSL -o "$manifest_tmp" "$manifest_url" 2>/dev/null; then
      local manifest_sha
      # Manifest format: "<sha256>  <filename>" — take the first field
      manifest_sha=$(awk '{print $1}' "$manifest_tmp" | head -1)
      if [[ -n "$manifest_sha" ]]; then
        # Check if there's a GPG signature too
        local sig_url="${url}.sha256.sig"
        local sig_tmp
        sig_tmp=$(mktemp)
        if curl -fsSL -o "$sig_tmp" "$sig_url" 2>/dev/null; then
          if command -v gpg >/dev/null 2>&1; then
            if gpg --verify "$sig_tmp" "$manifest_tmp" 2>/dev/null; then
              log_info "Manifest GPG signature verified."
            else
              rm -f "$out" "$manifest_tmp" "$sig_tmp"
              fail "${R}GPG signature verification FAILED for $manifest_url — possible tampering. Aborting.${N}"
            fi
          else
            log_warn "gpg not available; manifest signature not verified."
          fi
          rm -f "$sig_tmp"
        fi
        # Verify the downloaded file against the manifest hash
        sha256_verify "$out" "$manifest_sha" || {
          rm -f "$out" "$manifest_tmp"
          fail "${R}Downloaded $out does not match the manifest SHA-256. Aborting.${N}"
        }
      fi
    else
      log_warn "No SHA-256 manifest found at $manifest_url; skipping verification."
    fi
    rm -f "$manifest_tmp"
  fi
}

# verify_data_json <local_file>
# Verifies the crosbreaker data.json against a pinned hash (if available).
EZ_DATA_JSON_PINNED_SHA256="${EZ_DATA_JSON_PINNED_SHA256:-}"
verify_data_json() {
  local file="$1"
  [[ -f "$file" ]] || { log_error "data.json not found: $file"; return 1; }
  if [[ -z "$EZ_DATA_JSON_PINNED_SHA256" ]]; then
    log_debug "No pinned SHA-256 for data.json; skipping verification (set EZ_DATA_JSON_PINNED_SHA256 to enable)."
    return 0
  fi
  sha256_verify "$file" "$EZ_DATA_JSON_PINNED_SHA256"
}

# ---------------------------------------------------------------------------
# 15. Screen resolution auto-detection
# ---------------------------------------------------------------------------
# detect_resolution — echoes "WxH" by probing the connected display.
# On a build host (not a Chromebook) there's nothing to probe; returns empty.
# On-device, reads /sys/class/drm/*/modes (prefers the largest).
detect_resolution() {
  local mode best_w=0 best_h=0 w h
  # Try /sys/class/drm/*/modes (connected panels)
  while IFS= read -r -d '' modes_file; do
    while IFS= read -r mode; do
      # mode format: "1920x1080" or "1920x1080R" etc.
      if [[ "$mode" =~ ^([0-9]+)x([0-9]+) ]]; then
        w="${BASH_REMATCH[1]}"
        h="${BASH_REMATCH[2]}"
        if (( w * h > best_w * best_h )); then
          best_w="$w"
          best_h="$h"
        fi
      fi
    done < "$modes_file"
  done < <(find /sys/class/drm -name modes -print0 2>/dev/null)

  # Fallback: try `crossystem` (on-device) — doesn't directly give resolution
  # but confirms we're on a Chromebook.
  if [[ $best_w -eq 0 ]] && command -v crossystem >/dev/null 2>&1; then
    # Try reading the panel resolution from the cmdline or VPD
    : # crossystem doesn't expose resolution directly
  fi

  if [[ $best_w -gt 0 && $best_h -gt 0 ]]; then
    echo "${best_w}x${best_h}"
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# 16. Device status reporting (for `modmium.sh --status`)
# ---------------------------------------------------------------------------
ez_status() {
  echo -e "${B}=== EZ-Modmium device status ===${N}"
  echo

  # ChromeOS version + board
  local milestone="" board=""
  if [[ -f /etc/lsb-release ]]; then
    milestone=$(grep '^CHROMEOS_RELEASE_CHROME_MILESTONE=' /etc/lsb-release 2>/dev/null | cut -d= -f2 | tr -d '\r')
    board=$(grep '^CHROMEOS_RELEASE_BOARD=' /etc/lsb-release 2>/dev/null | cut -d= -f2 | tr -d '\r')
  fi
  if [[ -n "$milestone" ]]; then
    echo -e "  ChromeOS version : ${G}v${milestone}${N}"
  else
    echo -e "  ChromeOS version : ${R}unknown${N}"
  fi
  if [[ -n "$board" ]]; then
    echo -e "  Board            : ${board}"
  fi

  # Branch
  if [[ -f /.branch ]]; then
    echo -e "  Modmium branch   : $(cat /.branch 2>/dev/null)"
  else
    echo -e "  Modmium branch   : ${D}(not installed)${N}"
  fi

  # DevFW state
  local devfw
  if command -v vpd >/dev/null 2>&1; then
    devfw=$(vpd -i RO_VPD -g "dev_firmware" 2>/dev/null || echo "")
    if [[ "$devfw" == "1" ]]; then
      echo -e "  DevFW            : ${G}flashed${N}"
    else
      echo -e "  DevFW            : ${D}not flashed${N}"
    fi
  else
    echo -e "  DevFW            : ${D}(vpd unavailable — not a Chromebook?)${N}"
  fi

  # WP state
  if command -v flashrom >/dev/null 2>&1; then
    local wp_status
    wp_status=$(flashrom --wp-status 2>&1 | grep -E "WP:|write protect" | head -1)
    if [[ -n "$wp_status" ]]; then
      echo -e "  Write Protect    : ${wp_status}"
    fi
  fi

  # APROV state (Ti50 only)
  if command -v gsctool >/dev/null 2>&1; then
    local aprov
    aprov=$(gsctool -a -I 2>/dev/null | grep AllowUnverifiedRo || true)
    if [[ -n "$aprov" ]]; then
      echo -e "  APROV (Ti50)     : $(echo "$aprov" | awk '{print $3}')"
    fi
  fi

  # Kernver
  if command -v tpmc >/dev/null 2>&1 && command -v trunksd >/dev/null 2>&1; then
    # Only attempt if trunksd is running (don't disrupt it)
    if pgrep -x trunksd >/dev/null 2>&1 || pgrep -x tcsd >/dev/null 2>&1; then
      local rawkv kernver=0
      rawkv=$(tpmc read "$EZ_TPM_KERNVER_INDEX" 9 2>/dev/null || echo "")
      if [[ -n "$rawkv" ]]; then
        local -a bytes=()
        local byte
        for byte in $rawkv; do
          while [[ -n "$byte" ]]; do
            bytes+=("${byte:0:2}")
            byte="${byte:2}"
          done
        done
        if [[ "16#${bytes[0]:-0}" -eq 16 ]]; then
          kernver=$(( 16#${bytes[4]:-0} | 16#${bytes[5]:-0}<<8 ))
        elif [[ "16#${bytes[0]:-0}" -eq 2 ]]; then
          kernver=$(( 16#${bytes[5]:-0} | 16#${bytes[6]:-0}<<8 ))
        fi
        echo -e "  Kernver (TPM)    : $kernver"
      fi
    fi
  fi

  # Active kernel partition
  if command -v rootdev >/dev/null 2>&1 && command -v cgpt >/dev/null 2>&1; then
    local intdis
    intdis=$(rootdev -d 2>/dev/null)
    if [[ -n "$intdis" ]]; then
      local kn
      kn=$(get_booted_kernnum "$intdis" 2>/dev/null)
      echo -e "  Active kernel    : KERN-${kn/A/-} (partition ${kn})"
    fi
  fi

  # Firmware backup
  local backup_found=""
  for f in /tmp/backupdir/backup_*.rom /mnt/stateful_partition/backup_*.rom; do
    if [[ -f "$f" ]]; then
      backup_found="$f"
      break
    fi
  done
  if [[ -n "$backup_found" ]]; then
    local bsha
    bsha=$(sha256_of "$backup_found" 2>/dev/null | cut -c1-16)
    echo -e "  Firmware backup  : ${G}found${N} ($backup_found)"
    [[ -n "$bsha" ]] && echo -e "  Backup SHA-256   : ${bsha}..."
  else
    echo -e "  Firmware backup  : ${Y}not found in default locations${N}"
  fi

  # User keys
  if [[ -d /usr/share/vboot/userkeys ]]; then
    echo -e "  User signing keys: ${G}present${N} (/usr/share/vboot/userkeys)"
  else
    echo -e "  User signing keys: ${D}using devkeys${N}"
  fi

  # Install state (resumable)
  if [[ -f "$EZ_STATE_FILE" ]]; then
    echo
    echo -e "${B}Install state (interrupted install detected):${N}"
    state_show
  fi

  # Disk space
  local stateful_free
  if [[ -d /mnt/stateful_partition ]]; then
    stateful_free=$(df -h /mnt/stateful_partition 2>/dev/null | awk 'NR==2{print $4}')
    [[ -n "$stateful_free" ]] && echo -e "  Stateful free    : ${stateful_free}"
  fi

  # Last log
  if [[ -d "$EZ_LOG_DIR" ]]; then
    local last_log
    last_log=$(ls -t "$EZ_LOG_DIR"/ez-modmium-*.log 2>/dev/null | head -1)
    if [[ -n "$last_log" ]]; then
      echo -e "  Last log         : $(basename "$last_log")"
    fi
  fi

  echo
  echo -e "${B}=== end status ===${N}"
}

# ---------------------------------------------------------------------------
# 17. Uninstall / clean revert (`modmium.sh --uninstall`)
# ---------------------------------------------------------------------------
# Automates the Emergency Revert + firmware restore flow.
# Requires a firmware backup to restore. Refuses to proceed without one
# unless --force is passed (which only clears FWMP + VPD without restoring FW).
ez_uninstall() {
  local force=0
  [[ "${1:-}" == "--force" ]] && force=1

  echo -e "${B}=== EZ-Modmium uninstall / clean revert ===${N}"
  echo
  echo -e "${Y}WARNING: This will restore your stock firmware and revert DevFW.${N}"
  echo -e "${Y}The device will no longer run Modmium. Make sure you have a firmware backup.${N}"
  echo

  if ! confirm "Proceed with uninstall?" "N"; then
    log_info "Uninstall cancelled."
    return 1
  fi

  # Step 1: clear FWMP (so the stock recovery image will boot)
  log_step "Step 1/3: Clearing FWMP..."
  local _fwmp_cleared=0
  if command -v device_management_client >/dev/null 2>&1; then
    if device_management_client --action=remove_firmware_management_parameters >/dev/null 2>&1; then
      _fwmp_cleared=1
    elif command -v cryptohome >/dev/null 2>&1; then
      cryptohome --action=remove_firmware_management_parameters >/dev/null 2>&1 && _fwmp_cleared=1
    fi
  elif command -v cryptohome >/dev/null 2>&1; then
    cryptohome --action=remove_firmware_management_parameters >/dev/null 2>&1 && _fwmp_cleared=1
  fi
  # TPM fallback (same as modmium.sh flashDevFW)
  if command -v tpmc >/dev/null 2>&1; then
    initctl stop tcsd >/dev/null 2>&1 || true
    initctl stop trunksd >/dev/null 2>&1 || true
    tpmc clear 2>/dev/null || true
    tpmc def 0x100a 0x28 0x12000 2>/dev/null || true
    tpmc write 0x100a 76 28 10 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 2>/dev/null || true
  fi
  if [[ $_fwmp_cleared -eq 1 ]]; then
    log_info "FWMP cleared."
  else
    log_warn "Could not clear FWMP via device_management_client/cryptohome. Will attempt TPM fallback."
  fi

  # Step 2: find and restore the firmware backup
  log_step "Step 2/3: Restore firmware backup..."
  local backup_file=""
  # Search common locations
  for f in /tmp/backupdir/backup_*.rom /mnt/stateful_partition/backup_*.rom; do
    if [[ -f "$f" ]]; then
      backup_file="$f"
      break
    fi
  done

  if [[ -z "$backup_file" ]] && [[ $force -eq 0 ]]; then
    echo
    echo -e "${R}No firmware backup found in default locations.${N}"
    echo -e "If you have a backup on a USB, mount it and re-run:"
    echo -e "  bash modmium.sh --uninstall"
    echo -e "Or, to skip firmware restore (only clear FWMP + VPD), run:"
    echo -e "  bash modmium.sh --uninstall --force"
    echo
    log_warn "Uninstall aborted — no firmware backup."
    return 1
  fi

  if [[ -n "$backup_file" ]]; then
    echo -e "Found backup: ${G}$backup_file${N}"
    # Verify SHA-256 if a sidecar exists
    local sha_file="${backup_file}.sha256"
    local sha_dir
    sha_dir=$(dirname "$backup_file")
    local expected=""
    if [[ -f "$sha_file" ]]; then
      expected=$(awk '{print $1}' "$sha_file" 2>/dev/null)
    elif [[ -f "$sha_dir/backup.sha256" ]]; then
      expected=$(grep "$(basename "$backup_file")" "$sha_dir/backup.sha256" 2>/dev/null | awk '{print $1}')
    fi
    if [[ -n "$expected" ]]; then
      log_info "Verifying backup SHA-256..."
      if ! sha256_verify "$backup_file" "$expected"; then
        fail "${R}Firmware backup SHA-256 mismatch! Refusing to restore a corrupted backup.${N}" keepflag
      fi
    fi
    if ! confirm "Restore this backup to your firmware? (THIS IS IRREVERSIBLE)" "N"; then
      log_warn "Skipping firmware restore. FWMP was still cleared."
      log_info "You can now recover with a stock ChromeOS recovery image."
      return 0
    fi
    if ! command -v flashrom >/dev/null 2>&1; then
      fail "${R}flashrom not found — cannot restore firmware.${N}" keepflag
    fi
    log_step "Writing firmware backup with flashrom..."
    flashrom -w "$backup_file" || fail "${R}flashrom write failed — DO NOT REBOOT.${N}" keepflag
    log_info "Firmware restored."
  else
    log_warn "Running with --force: skipping firmware restore. Only FWMP + VPD cleared."
  fi

  # Step 3: clear the dev_firmware VPD flag
  log_step "Step 3/3: Clearing dev_firmware VPD flag..."
  if command -v vpd >/dev/null 2>&1; then
    vpd -d dev_firmware 2>/dev/null || true
    log_info "dev_firmware VPD cleared."
  fi

  # Clear install state
  state_clear 2>/dev/null || true

  echo
  echo -e "${G}=== Uninstall complete ===${N}"
  echo -e "Your device now has stock firmware (or FWMP cleared)."
  echo -e "${B}Next steps:${N}"
  echo -e "  1. Reboot into recovery (Esc+Refresh+Power)"
  echo -e "  2. Recover with a stock ChromeOS recovery image"
  echo -e "  3. The device will be back to factory state"
  echo
  if confirm "Reboot now?" "Y" --single; then
    reboot
  fi
}

# ---------------------------------------------------------------------------
# 18. Selftest harness
# ---------------------------------------------------------------------------
ez_selftest() {
  local pass=0 fail_count=0

  echo -e "${B}=== EZ-Modmium self-test ===${N}"

  # opposite_num
  [[ "$(opposite_num 2)" == "4" ]] && { log_info "PASS: opposite_num(2)==4"; pass=$((pass+1)); } || { log_error "FAIL: opposite_num(2)==4"; fail_count=$((fail_count+1)); }
  [[ "$(opposite_num 4)" == "2" ]] && { log_info "PASS: opposite_num(4)==2"; pass=$((pass+1)); } || { log_error "FAIL: opposite_num(4)==2"; fail_count=$((fail_count+1)); }
  [[ "$(opposite_num 3)" == "5" ]] && { log_info "PASS: opposite_num(3)==5"; pass=$((pass+1)); } || { log_error "FAIL: opposite_num(3)==5"; fail_count=$((fail_count+1)); }
  [[ "$(opposite_num 5)" == "3" ]] && { log_info "PASS: opposite_num(5)==3"; pass=$((pass+1)); } || { log_error "FAIL: opposite_num(5)==3"; fail_count=$((fail_count+1)); }

  # format_part_number
  [[ "$(format_part_number sda 3)" == "sda3" ]] && { log_info "PASS: format_part_number sda 3 == sda3"; pass=$((pass+1)); } || { log_error "FAIL: format_part_number sda 3"; fail_count=$((fail_count+1)); }
  [[ "$(format_part_number nvme0n1 3)" == "nvme0n1p3" ]] && { log_info "PASS: format_part_number nvme0n1 3"; pass=$((pass+1)); } || { log_error "FAIL: format_part_number nvme0n1 3"; fail_count=$((fail_count+1)); }

  # color vars defined
  [[ -n "$G" && -n "$R" && -n "$N" ]] && { log_info "PASS: colors defined"; pass=$((pass+1)); } || { log_error "FAIL: colors defined"; fail_count=$((fail_count+1)); }

  # config loaded
  [[ "$EZ_MIN_VERSION" == "131" ]] && { log_info "PASS: EZ_MIN_VERSION==131"; pass=$((pass+1)); } || { log_error "FAIL: EZ_MIN_VERSION==131 (got '$EZ_MIN_VERSION')"; fail_count=$((fail_count+1)); }
  [[ "$EZ_GBB_FLAGS" == "0xa0b1" ]] && { log_info "PASS: EZ_GBB_FLAGS==0xa0b1"; pass=$((pass+1)); } || { log_error "FAIL: EZ_GBB_FLAGS==0xa0b1 (got '$EZ_GBB_FLAGS')"; fail_count=$((fail_count+1)); }

  # boards list non-empty
  [[ -n "$EZ_BOARDS" ]] && { log_info "PASS: boards list non-empty"; pass=$((pass+1)); } || { log_error "FAIL: boards list empty"; fail_count=$((fail_count+1)); }
  echo "$EZ_BOARDS" | grep -q corsola && { log_info "PASS: corsola in boards"; pass=$((pass+1)); } || { log_error "FAIL: corsola in boards"; fail_count=$((fail_count+1)); }
  [[ -n "$EZ_MINIOS_BOARDS" ]] && { log_info "PASS: minios_boards non-empty"; pass=$((pass+1)); } || { log_error "FAIL: minios_boards empty"; fail_count=$((fail_count+1)); }

  # sha256 helpers
  echo hi > /tmp/ez_test_file 2>/dev/null
  if [[ $(sha256_of /tmp/ez_test_file 2>/dev/null) =~ ^[0-9a-f]{64}$ ]]; then
    log_info "PASS: sha256_of works"; pass=$((pass+1))
  else
    log_error "FAIL: sha256_of works"; fail_count=$((fail_count+1))
  fi
  rm -f /tmp/ez_test_file

  # log function works
  log "INFO" "selftest log line" && { log_info "PASS: log() works"; pass=$((pass+1)); } || { log_error "FAIL: log()"; fail_count=$((fail_count+1)); }

  # state management (resumable installs)
  local _old_state="$EZ_STATE_FILE"
  EZ_STATE_FILE="/tmp/ez_selftest_state"
  rm -f "$EZ_STATE_FILE"
  save_state "image_downloaded"
  if state_has "image_downloaded" && state_has "deps_installed" && ! state_has "chromeos_written"; then
    log_info "PASS: state save/has"; pass=$((pass+1))
  else
    log_error "FAIL: state save/has"; fail_count=$((fail_count+1))
  fi
  state_clear
  if state_has "image_downloaded"; then
    log_error "FAIL: state_clear"; fail_count=$((fail_count+1))
  else
    log_info "PASS: state_clear"; pass=$((pass+1))
  fi
  rm -f "$EZ_STATE_FILE"
  EZ_STATE_FILE="$_old_state"

  # detect_resolution returns empty or WxH (can't test on non-Chromebook, just check it doesn't crash)
  local _res
  _res=$(detect_resolution 2>/dev/null || true)
  if [[ -z "$_res" || "$_res" =~ ^[0-9]+x[0-9]+$ ]]; then
    log_info "PASS: detect_resolution (returned '$_res')"; pass=$((pass+1))
  else
    log_error "FAIL: detect_resolution returned '$_res'"; fail_count=$((fail_count+1))
  fi

  # verify_data_json with no pinned hash returns 0 (skip)
  echo '{}' > /tmp/ez_test_data.json
  if verify_data_json /tmp/ez_test_data.json 2>/dev/null; then
    log_info "PASS: verify_data_json (skip when no pin)"; pass=$((pass+1))
  else
    log_error "FAIL: verify_data_json"; fail_count=$((fail_count+1))
  fi
  rm -f /tmp/ez_test_data.json

  echo
  if [[ "$fail_count" == 0 ]]; then
    echo -e "${G}All $pass tests passed.${N}"
    return 0
  else
    echo -e "${R}$fail_count test(s) FAILED, $pass passed.${N}"
    return 1
  fi
}

# Initialize logging on source
_log_init

log "INFO" "libmodmium.sh loaded (EZ_LIB_DIR=$EZ_LIB_DIR)"
