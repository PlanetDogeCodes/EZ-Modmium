#!/bin/bash
# =============================================================================
# EZ-Modmium common_modmium.sh
# =============================================================================
# Loads the shared libmodmium.sh (single source of truth for colors, board
# lists, config, helpers) and re-exports the legacy variables that build-image.sh
# still expects ($boards, $minios_boards, $keydir, $B/$G/...).
# =============================================================================

SCRIPT_DIR_CM="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR_CM}/libmodmium.sh"

# Backwards-compat aliases for build-image.sh (legacy variable names)
boards="$EZ_BOARDS"
minios_boards="$EZ_MINIOS_BOARDS"

# keydir selection (unchanged semantics)
if [[ -d build-utils/keys/userkeys ]]; then
  keydir=build-utils/keys/userkeys
else
  keydir=build-utils/keys/devkeys
fi

# bsdtar / 7z aliases (unchanged)
if ! command -v 7z >/dev/null 2>&1 && command -v 7za >/dev/null 2>&1; then
  7z() { 7za "$@"; }
fi

# shflags loader (delegates to the bundled shflags)
load_shflags() {
  if [ -f /usr/share/misc/shflags ]; then
    # shellcheck disable=SC1091
    . /usr/share/misc/shflags
  elif [ -f "${SCRIPT_DIR_CM}/lib/shflags/shflags" ]; then
    # shellcheck disable=SC1091
    . "${SCRIPT_DIR_CM}/lib/shflags/shflags"
  else
    echo "ERROR: Cannot find the required shflags library." >&2
    return 1
  fi
  DEFINE_boolean debug "${FLAGS_FALSE}" "Provide debug messages" "d" 2>/dev/null || true
}
