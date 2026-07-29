#!/bin/bash
# =============================================================================
# EZ-Modmium dependency installer
# =============================================================================
# Detects your distro and installs everything Modmium needs to build, with an
# optional --bootstrap-vboot fallback that compiles vboot-utils from source.
#
# Usage:
#   tools/install-deps.sh                    # install for detected distro
#   tools/install-deps.sh --with-bootsplash  # also install inkscape
#   tools/install-deps.sh --bootstrap-vboot  # compile vboot-utils if missing
#   tools/install-deps.sh --help
# =============================================================================
set -uo pipefail

WITH_BOOTSPLASH=0
BOOTSTRAP_VBOOT=0

usage() {
  cat <<EOF
EZ-Modmium dependency installer

Usage: $0 [options]

Options:
  --with-bootsplash   Also install inkscape (required for custom bootsplashes)
  --bootstrap-vboot   Compile vboot-utils from source if distro package is
                      missing or older than the required minimum
  --help              Show this help

Supported distros: Arch, Debian/Ubuntu (incl. WSL), Fedora.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --with-bootsplash) WITH_BOOTSPLASH=1 ;;
    --bootstrap-vboot) BOOTSTRAP_VBOOT=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $arg"; usage; exit 1 ;;
  esac
done

# Color helpers
if [[ -t 1 ]]; then
  G=$'\033[38;5;46m'; Y=$'\033[38;5;220m'; R=$'\033[38;5;203m'; N=$'\033[0m'
else
  G=''; Y=''; R=''; N=''
fi

ok()   { echo "${G}[OK]${N} $1"; }
warn() { echo "${Y}[WARN]${N} $1"; }
err()  { echo "${R}[ERR]${N} $1"; }

# ---- Detect distro ----
detect_distro() {
  if [[ -f /etc/arch-release ]]; then echo arch
  elif [[ -f /etc/debian_version ]]; then echo debian
  elif [[ -f /etc/fedora-release ]] || [[ -f /etc/redhat-release ]]; then echo fedora
  else echo unknown
  fi
}

# ---- vboot-utils version check ----
vboot_too_old() {
  command -v futility >/dev/null 2>&1 || return 0
  local v
  v=$(futility --version 2>/dev/null | head -1 | awk '{print $2}')
  [[ -z "$v" ]] && return 0
  local major minor
  major=$(echo "$v" | cut -d. -f1)
  minor=$(echo "$v" | cut -d. -f2)
  [[ "$major" =~ ^[0-9]+$ ]] || return 0
  [[ "$minor" =~ ^[0-9]+$ ]] || minor=0
  [[ "$major" -lt 1 ]] && return 0
  [[ "$major" == 1 && "$minor" -lt 1 ]] && return 0
  return 1
}

# ---- Compile vboot-utils from source ----
bootstrap_vboot() {
  echo "${Y}Compiling vboot-utils from source...${N}"
  local tmpdir
  tmpdir=$(mktemp -d)
  (
    cd "$tmpdir" || exit 1
    git clone --depth 1 https://chromium.googlesource.com/chromiumos/platform/vboot_reference || exit 1
    cd vboot_reference || exit 1
    make all WERROR= || exit 1
    sudo make install || exit 1
    sudo mkdir -p /usr/share/vboot/devkeys
    sudo cp -r tests/devkeys /usr/share/vboot/devkeys 2>/dev/null || true
  ) || { err "vboot-utils compilation failed"; rm -rf "$tmpdir"; return 1; }
  rm -rf "$tmpdir"
  ok "vboot-utils compiled and installed"
}

# ---- Per-distro install ----
install_arch() {
  ok "Detected Arch Linux"
  local helper
  if command -v yay >/dev/null 2>&1; then helper=yay
  elif command -v paru >/dev/null 2>&1; then helper=paru
  else
    warn "Neither yay nor paru found. Install one first: https://github.com/Jguer/yay"
    return 1
  fi
  $helper -S --needed --noconfirm acpica coreutils curl jq libarchive pv util-linux wget 2>&1
  if [[ "$WITH_BOOTSPLASH" == 1 ]]; then
    $helper -S --needed --noconfirm inkscape
  fi
  if ! command -v futility >/dev/null 2>&1; then
    $helper -S --needed --noconfirm vboot-utils || {
      [[ "$BOOTSTRAP_VBOOT" == 1 ]] && bootstrap_vboot
    }
  fi
}

install_debian() {
  ok "Detected Debian/Ubuntu"
  sudo apt update
  sudo apt install -y acpica-tools coreutils curl jq libarchive-tools pv sed util-linux wget
  if [[ "$WITH_BOOTSPLASH" == 1 ]]; then
    sudo apt install -y inkscape
  fi
  if ! command -v futility >/dev/null 2>&1; then
    sudo apt install -y vboot-utils 2>/dev/null || {
      warn "vboot-utils not in your repos."
      if [[ "$BOOTSTRAP_VBOOT" == 1 ]]; then
        bootstrap_vboot
      else
        warn "Run '$0 --bootstrap-vboot' to compile it from source."
      fi
    }
  fi
  if ! command -v bsdtar >/dev/null 2>&1; then
    warn "bsdtar not found; creating a tar wrapper. Install libarchive-tools for the real thing."
    bsdtar() { tar "$@"; }
    export -f bsdtar
  fi
}

install_fedora() {
  ok "Detected Fedora"
  sudo dnf install -y acpica-tools coreutils curl jq libarchive pv sed util-linux wget
  if [[ "$WITH_BOOTSPLASH" == 1 ]]; then
    sudo dnf install -y inkscape
  fi
  if ! command -v futility >/dev/null 2>&1; then
    sudo dnf install -y vboot-utils 2>/dev/null || {
      [[ "$BOOTSTRAP_VBOOT" == 1 ]] && bootstrap_vboot
    }
  fi
}

install_unknown() {
  err "Unknown distro. Install manually: acpica, coreutils, curl, jq, libarchive (bsdtar), pv, util-linux, wget, vboot-utils"
  err "  (and inkscape if you want custom bootsplashes)"
  err "Or run with --bootstrap-vboot to compile vboot-utils from source."
  return 1
}

# ---- Main ----
main() {
  local distro
  distro=$(detect_distro)
  case "$distro" in
    arch)    install_arch ;;
    debian)  install_debian ;;
    fedora)  install_fedora ;;
    unknown) install_unknown ;;
  esac

  # Verify
  echo
  echo "${G}Verifying...${N}"
  local missing=0
  for dep in bsdtar file futility jq pv wget curl; do
    if command -v "$dep" >/dev/null 2>&1; then
      ok "$dep"
    else
      err "$dep MISSING"
      missing=1
    fi
  done
  if [[ "$missing" == 1 ]]; then
    err "Some dependencies are still missing. See messages above."
    exit 1
  fi
  echo
  ok "All dependencies installed. Ready to build Modmium."
}

main "$@"
