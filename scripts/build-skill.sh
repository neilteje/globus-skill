#!/usr/bin/env bash
#
# Package the editable skill source (globus-sdk/) into a distributable
# .skill bundle (dist/globus-sdk.skill).
#
# A .skill file is just a zip archive whose top-level entry is the skill
# directory (globus-sdk/), containing SKILL.md and references/.
#
# Usage: ./scripts/build-skill.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_DIR="globus-sdk"
OUT_DIR="dist"
OUT_FILE="${OUT_DIR}/${SKILL_DIR}.skill"

cd "$REPO_ROOT"

if [[ ! -f "${SKILL_DIR}/SKILL.md" ]]; then
  echo "error: ${SKILL_DIR}/SKILL.md not found — run from the repo root" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -f "$OUT_FILE"

# Zip the skill directory so the archive contains globus-sdk/SKILL.md etc.
# -r recurse, -X strip extra file attributes for reproducible-ish output.
zip -rX "$OUT_FILE" "$SKILL_DIR" \
  -x '*/.DS_Store' '*/.*' >/dev/null

echo "Built ${OUT_FILE}"
unzip -l "$OUT_FILE"
