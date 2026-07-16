#!/usr/bin/env bash
# commit-data.sh — post-experiment commit & push helper (AGENTS.md completion protocol)
#
# Validates all data CSVs, then commits and pushes to origin/main.
# Use this instead of raw `git commit` after any experiment produces data.
#
# Usage:
#   ./scripts/commit-data.sh "feat(data): S6c output verbosity — 12 models"
#   ./scripts/commit-data.sh "fix(data): re-run stale Phi-4 calls" path/to/file.csv
#
# The script:
#   1. Runs scripts/validate-data.py --strict (blocks commit on corruption/warnings)
#   2. Stages the given files (or all changed data/ if none given)
#   3. Commits with the provided message
#   4. Pushes to origin/main
#   5. Reports the commit hash + files changed
#
# Exit non-zero if validation fails or git rejects. Never commits experiment-config.ps1.

set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

if [ $# -lt 1 ]; then
    echo "Usage: $0 \"<commit message>\" [file1 file2 ...]" >&2
    echo "  If no files given, stages all changes under data/." >&2
    exit 1
fi

MSG="$1"; shift
FILES=("$@")

echo "=== Step 1/4: Validate data (strict) ==="
python scripts/validate-data.py --strict
echo "Validation passed."

echo
echo "=== Step 2/4: Stage files ==="
# Never allow committing the gitignored config with the API key
if git diff --cached --name-only | grep -q 'experiment-config\.ps1'; then
    echo "REFUSING: experiment-config.ps1 is staged. This file holds the API key." >&2
    exit 1
fi

if [ ${#FILES[@]} -eq 0 ]; then
    git add data/
    echo "Staged all changes under data/."
else
    git add "${FILES[@]}"
    echo "Staged: ${FILES[*]}"
fi

# Guard again: nothing with the key should slip in
if git diff --cached --name-only | grep -q 'experiment-config\.ps1'; then
    echo "REFUSING: experiment-config.ps1 got staged. Aborting." >&2
    git reset HEAD experiment-config.ps1 2>/dev/null || true
    exit 1
fi

STAGED=$(git diff --cached --name-only)
if [ -z "$STAGED" ]; then
    echo "Nothing staged to commit. Aborting." >&2
    exit 1
fi
echo "Files to commit:"
echo "$STAGED" | sed 's/^/  /'

echo
echo "=== Step 3/4: Commit ==="
git commit -m "$MSG" -q
HASH=$(git rev-parse --short HEAD)
echo "Committed: $HASH"

echo
echo "=== Step 4/4: Push to origin/main ==="
git push origin main
echo

echo "=== DONE ==="
echo "Commit: $HASH"
echo "Message: $MSG"
echo "Files:"
git show --stat --oneline "$HASH" | tail -n +2
