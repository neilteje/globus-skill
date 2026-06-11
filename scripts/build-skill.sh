#!/usr/bin/env bash
#
# Package each editable skill source directory into a distributable
# .skill bundle under dist/.
#
# A .skill file is just a zip archive whose top-level entry is the skill
# directory, containing SKILL.md and optional resources.
#
# Usage: ./scripts/build-skill.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="dist"

cd "$REPO_ROOT"

mkdir -p "$OUT_DIR"

found=0
for skill_md in ./*/SKILL.md; do
  [[ -f "$skill_md" ]] || continue
  skill_dir="$(basename "$(dirname "$skill_md")")"
  out_file="${OUT_DIR}/${skill_dir}.skill"
  found=1

  rm -f "$out_file"

  # Zip the skill directory so the archive contains skill-name/SKILL.md etc.
  # -r recurse, -X strip extra file attributes for reproducible-ish output.
  zip -rX "$out_file" "$skill_dir" \
    -x '*/.DS_Store' '*/.*' >/dev/null

  echo "Built ${out_file}"
  unzip -l "$out_file"
done

if [[ "$found" -eq 0 ]]; then
  echo "error: no top-level skill directories with SKILL.md found" >&2
  exit 1
fi
