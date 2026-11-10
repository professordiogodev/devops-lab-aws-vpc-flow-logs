#!/usr/bin/env bash
# Generic submission check. It cannot see your cloud account or your laptop;
# it checks that you left the evidence and answered the questions.
# Lab-specific checks (optional) go in .lab/lab-check.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source .lab/config.env

fail=0
out="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
say() { echo "$@" >> "$out"; }
ok()  { say "- ✅ $*"; }
bad() { say "- ❌ $*"; fail=1; }

say "## Lab check"
say ""

# 1. Answers filled in
if [ ! -f SUBMISSION.md ]; then
  bad "SUBMISSION.md is missing"
elif grep -q "replace this line with your answer" SUBMISSION.md; then
  left=$(grep -c "replace this line with your answer" SUBMISSION.md)
  bad "SUBMISSION.md: $left question(s) still unanswered (look for 'replace this line with your answer')"
else
  ok "SUBMISSION.md: all questions answered"
fi

# 2. Tear down proof (mandatory when the lab creates anything)
if [ -n "${TEARDOWN_MARKER:-}" ]; then
  if grep -qE "^${TEARDOWN_MARKER} \(" SUBMISSION.md 2>/dev/null; then
    ok "Tear down: proof found ($TEARDOWN_MARKER)"
  else
    bad "Tear down: SUBMISSION.md must contain the pasted output of the teardown proof (a line starting with '$TEARDOWN_MARKER (')"
  fi
fi

# 3. Lab-specific checks
if [ -f .lab/lab-check.sh ]; then
  say ""
  say "### Lab-specific checks"
  if bash .lab/lab-check.sh >> "$out" 2>&1; then
    ok "Lab-specific checks passed"
  else
    bad "Lab-specific checks failed (see above)"
  fi
fi

say ""
if [ "$fail" -eq 0 ]; then
  say "**Result: ready to submit.** Paste the URL of this fork into the lab deliverable."
else
  say "**Result: not ready yet.** Fix the items marked ❌ and push again."
fi
exit "$fail"
