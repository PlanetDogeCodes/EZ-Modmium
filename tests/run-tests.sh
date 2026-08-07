#!/bin/bash
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok()   { echo "  PASS: $1"; PASS=$((PASS+1)); }
bad()  { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
echo "=== EZ-Modmium test suite ==="
echo
echo "--- 1. bash -n syntax checks ---"
for f in modmium.sh build-image.sh build-utils/libmodmium.sh build-utils/common_modmium.sh mod-files/usr/lib/libmodmium.sh mod-files/usr/bin/update-modmium.sh mod-files/usr/bin/devpolicy-editor.sh mod-files/usr/bin/features.sh mod-files/usr/bin/localacc.sh mod-files/usr/lib/libmosh.sh tools/install-deps.sh; do
  bash -n "$f" 2>/dev/null && ok "$f" || bad "$f"
done
echo
echo "--- 2. Python syntax check ---"
python3 -m py_compile mod-files/usr/bin/stream.py 2>/dev/null && ok "stream.py" || bad "stream.py"
echo
echo "--- 3. libmodmium selftest ---"
EZ_FORCE_COLOR=1 bash -c 'source build-utils/libmodmium.sh; ez_selftest' >/dev/null 2>&1 && ok "selftest" || bad "selftest"
echo
echo "--- 4. --help smoke tests ---"
bash modmium.sh --help >/dev/null 2>&1 && ok "modmium.sh --help" || bad "modmium.sh --help"
bash build-image.sh --help >/dev/null 2>&1 && ok "build-image.sh --help" || bad "build-image.sh --help"
echo
echo "--- 5. --selftest smoke test ---"
EZ_FORCE_COLOR=1 bash modmium.sh --selftest >/dev/null 2>&1 && ok "modmium.sh --selftest" || bad "modmium.sh --selftest"
echo
echo "--- 6. --status smoke test ---"
EZ_FORCE_COLOR=1 bash modmium.sh --status >/dev/null 2>&1 && ok "modmium.sh --status" || bad "modmium.sh --status"
echo
echo "==============================="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo "==============================="
[[ "$FAIL" == 0 ]] && exit 0 || exit 1
