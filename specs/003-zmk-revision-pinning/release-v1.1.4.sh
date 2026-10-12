#!/usr/bin/env bash
# release-v1.1.4.sh — commands to run on `../zmk-keybeacon/` after
# feat/compat-contract-v1.1.4 PR is merged into main. Captured as a
# shell script (rather than tribal knowledge) so the step sequence
# survives maintainer rotation.
#
# This script is NOT run automatically. Review each command before
# executing. "远端暂停" rule applies — the final `git push` requires
# explicit human sign-off.

set -euo pipefail

cd "$(dirname "$0")/../../zmk-keybeacon"

# 1. Verify we're on main at the exact merge commit of the compat-contract PR.
#    NOTE on upstream state: at feature-003 time, main HEAD was 6c15918 which
#    is TWO commits BEHIND v1.1.3 (cbfe34f + e4dc6a5). v1.1.3 was tagged on a
#    chain that was never fast-forwarded back to main. feat/compat-contract-v1.1.4
#    was branched off v1.1.3 so it correctly includes everything in v1.1.3 plus
#    the 003 compat-contract work. When merging this PR, make sure the PR brings
#    main up to v1.1.3 before adding v1.1.4 (i.e. merging the feature branch is
#    enough — it carries the 2 lost commits with it; no separate catch-up PR
#    needed).
echo "[1/6] current branch:"
git branch --show-current
echo "    HEAD:"
git log HEAD -1 --oneline

# 2. Run the full validation suite one more time to make sure nothing drifted
#    between PR approval and tag time.
echo "[2/6] running validate_compat.py …"
python3 scripts/validate_compat.py

echo "[3/6] running pytest …"
python3 -m pytest scripts/tests/ -q

echo "[4/6] running smoke-cmake.sh …"
scripts/tests/smoke-cmake.sh

# 5. Regenerate the README Compatibility table so the new v1.1.4 row is real
#    (replaces the --pending-tag row from the PR).
echo "[5/6] regenerating README Compatibility table (no --pending-tag now) …"
python3 scripts/update-readme-table.py
if ! git diff --quiet README.md; then
    echo "    README changed; committing …"
    git add README.md
    git commit -m "docs: regenerate README Compatibility table for v1.1.4"
fi

# 6. Tag + push. The push line is intentionally commented out — flip it on
#    only after reviewing CHANGELOG v1.1.4 one last time.
echo "[6/6] tag v1.1.4 (push commented out until human review):"
echo "    git tag -a v1.1.4 -m \"KBP 1.1 compatibility contract and endpoint API forward-compat\""
echo "    # git push origin v1.1.4"
echo
echo "After pushing, create a GitHub release copying the v1.1.4 section"
echo "from CHANGELOG.md. Then update specs/003-zmk-revision-pinning/manual-run-log.md"
echo "with the release URL and tag sha."
