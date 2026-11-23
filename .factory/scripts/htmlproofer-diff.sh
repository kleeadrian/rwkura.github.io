#!/usr/bin/env bash
# Build two source trees of this Jekyll site and diff their html-proofer failures.
# Usage: .factory/scripts/htmlproofer-diff.sh <base-src-dir> <head-src-dir> [out-dir]
# Prints NEW failures (in head, not base) and FIXED failures (in base, not head).
# Failures are compared per built page + message (line numbers ignored), counting
# duplicates, so an extra copy of an already-known failure class still shows as NEW.
set -uo pipefail
BASE_SRC=$(cd "$1" && pwd); HEAD_SRC=$(cd "$2" && pwd); OUT=${3:-/tmp/proofer-diff-$$}
mkdir -p "$OUT"
export PATH="$(ruby -e 'print Gem.user_dir')/bin:$PATH"
status=0
for side in base head; do
  src=$BASE_SRC; [ "$side" = head ] && src=$HEAD_SRC
  if ! (cd "$src" && bundle exec jekyll build -s "$src" -d "$OUT/site-$side" >"$OUT/build-$side.log" 2>&1); then
    echo "BUILD FAILED ($side): see $OUT/build-$side.log"; tail -15 "$OUT/build-$side.log"; status=2
    continue
  fi
  echo "build $side: $(grep -E 'done in' "$OUT/build-$side.log" | tail -1 | sed 's/^ *//')"
  htmlproofer "$OUT/site-$side" --disable-external --no-enforce-https --allow-missing-href >"$OUT/proofer-$side.log" 2>&1
  python3 - "$OUT/proofer-$side.log" "$OUT/site-$side" >"$OUT/failures-$side.txt" <<'PY'
import re, sys
root = sys.argv[2]; loc = None; out = []
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"^\* At (.*?)(:\d+)?:?\s*$", line)
    if m:
        loc = m.group(1).replace(root, ""); continue
    if loc and line.strip():
        out.append(f"{loc} :: {line.strip()}"); loc = None
print("\n".join(sorted(out)))
PY
  echo "htmlproofer $side: $(grep -c . "$OUT/failures-$side.txt") failures ($(grep -E 'found [0-9]+ failure|All checks passed' "$OUT/proofer-$side.log" | tail -1))"
done
[ $status -ne 0 ] && exit $status
comm -13 "$OUT/failures-base.txt" "$OUT/failures-head.txt" >"$OUT/new.txt"
comm -23 "$OUT/failures-base.txt" "$OUT/failures-head.txt" >"$OUT/fixed.txt"
echo "NEW failures: $(grep -c . "$OUT/new.txt")"; sed 's/^/  + /' "$OUT/new.txt" | head -50
echo "FIXED failures: $(grep -c . "$OUT/fixed.txt")"; sed 's/^/  - /' "$OUT/fixed.txt" | head -20
echo "logs: $OUT"
[ -s "$OUT/new.txt" ] && exit 1 || exit 0
