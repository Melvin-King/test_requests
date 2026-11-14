#!/usr/bin/env bash
# Build the pristine, bug-injected `requests` tree that every trial is copied from.
# Idempotent: safe to re-run. Clones once, injects the CaseInsensitiveDict bug once.
#
#   bash build_fixtures.sh
#   PPI_MINI_WORK=~/ppi-fragmented-mini bash build_fixtures.sh   # pick the work dir
set -euo pipefail

REQUESTS_TAG="${REQUESTS_TAG:-v2.32.3}"
WORK="${PPI_MINI_WORK:-$HOME/ppi-fragmented-mini}"
PRISTINE="$WORK/pristine"
SRC_REL="src/requests/structures.py"
FIND='return self._store[key.lower()][1]'      # original (correct) getter
BROKEN='return self._store[key][1]'            # injected bug

mkdir -p "$WORK"

if [ -d "$PRISTINE/.git" ]; then
  echo "pristine already cloned at $PRISTINE (reusing; delete it to re-clone)"
else
  echo "cloning requests@$REQUESTS_TAG -> $PRISTINE"
  git -c advice.detachedHead=false clone --depth 1 --branch "$REQUESTS_TAG" \
      https://github.com/psf/requests "$PRISTINE"
fi

cd "$PRISTINE"
git config core.autocrlf false
git config core.filemode false

if [ ! -f "$SRC_REL" ]; then
  echo "ERROR: $SRC_REL not found — unexpected layout for tag $REQUESTS_TAG" >&2
  exit 1
fi

if grep -qF "$FIND" "$SRC_REL"; then
  python3 - "$SRC_REL" <<'PY'
import io, sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
s2 = s.replace("return self._store[key.lower()][1]", "return self._store[key][1]", 1)
io.open(p, "w", encoding="utf-8", newline="\n").write(s2)
print("injected CaseInsensitiveDict bug into", p)
PY
elif grep -qF "$BROKEN" "$SRC_REL"; then
  echo "bug already injected in $SRC_REL (nothing to do)"
else
  echo "ERROR: neither original nor injected getter found in $SRC_REL." >&2
  echo "       The pinned line changed for tag $REQUESTS_TAG — update FIND/BROKEN in this script" >&2
  echo "       and in ppi_spec.yaml (repo.bug)." >&2
  exit 1
fi

echo
echo "verifying the injected getter is present ..."
grep -nF "$BROKEN" "$SRC_REL" || { echo "verification failed" >&2; exit 1; }
echo
echo "pristine ready:"
echo "  $PRISTINE   (requests $REQUESTS_TAG, CaseInsensitiveDict getter bug injected)"
echo "next:  python run_fragmented_mini.py --model qwen/qwen-2.5-coder-32b-instruct"
