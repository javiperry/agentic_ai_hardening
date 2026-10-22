#!/bin/sh
# Run every sample's tests. Exit non-zero if any fails.
set -u
cd "$(dirname "$0")"
rc=0
for t in masking/Mask.Tests.ps1 job-runner/Round.Tests.ps1 trust-gate/TrustGate.Tests.ps1 egress/EgressPlan.Tests.ps1; do
  echo "== $t"; pwsh -NoProfile -File "$t" || rc=1
done
for t in write-guard/write-guard.test.ts chat-gate/gate-core.test.ts; do
  echo "== $t"; node --no-warnings --experimental-strip-types --test "$t" | grep -E '^# (pass|fail)' ; [ "$(node --no-warnings --experimental-strip-types --test "$t" | grep -c '^not ok')" = 0 ] || rc=1
done
[ $rc = 0 ] && echo "ALL SAMPLE TESTS PASSED" || echo "SOME SAMPLE TESTS FAILED"
exit $rc
