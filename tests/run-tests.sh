#!/bin/bash
# =============================================================================
# EZ-Modmium test runner
# =============================================================================
# Runs:
#   1. bash -n syntax checks on every shell script
#   2. python -m py_compile on stream.py
#   3. The built-in selftest from libmodmium.sh
#
# Usage: tests/run-tests.sh
# Exit code: 0 if all pass, non-zero otherwise.
# =============================================================================
set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

PASS=0
FAIL=0

ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

echo "=== EZ-Modmium test suite ==="
echo

echo "--- 1. bash -n syntax checks ---"
for f in \
  modmium.sh \
  build-image.sh \
  build-utils/libmodmium.sh \
  build-utils/common_modmium.sh \
  mod-files/usr/lib/libmodmium.sh \
  mod-files/usr/bin/update-modmium.sh \
  tools/install-deps.sh; do
  if bash -n "$f" 2>/dev/null; then ok "$f"; else bad "$f"; fi
done

echo
echo "--- 2. Python syntax check ---"
if python3 -m py_compile mod-files/usr/bin/stream.py 2>/dev/null; then
  ok "stream.py compiles"
else
  bad "stream.py compile failed"
fi

echo
echo "--- 3. libmodmium selftest ---"
if EZ_FORCE_COLOR=1 bash -c 'source build-utils/libmodmium.sh; ez_selftest' 2>&1; then
  ok "selftest passed"
else
  bad "selftest failed"
fi

echo
echo "--- 4. --help smoke tests ---"
if bash modmium.sh --help >/dev/null 2>&1; then
  ok "modmium.sh --help"
else
  bad "modmium.sh --help"
fi
if bash build-image.sh --help >/dev/null 2>&1; then
  ok "build-image.sh --help"
else
  bad "build-image.sh --help"
fi

echo
echo "--- 5. --selftest smoke test ---"
if EZ_FORCE_COLOR=1 bash modmium.sh --selftest >/dev/null 2>&1; then
  ok "modmium.sh --selftest"
else
  bad "modmium.sh --selftest"
fi

echo
echo "==============================="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "==============================="
[[ "$FAIL" == 0 ]] && exit 0 || exit 1
