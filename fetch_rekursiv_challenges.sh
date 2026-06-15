#!/usr/bin/env bash
# fetch_challenges.sh
# Holt alle Challenge-Repos von STEMgraph rekursiv über depends_on
set -euo pipefail

GITHUB_ORG="STEMgraph"
BASE_DIR="./challenges"

declare -A VISITED

fetch_challenge() {
  local id="$1"

  # Bereits verarbeitet → nichts tun
  [[ -n "${VISITED[$id]:-}" ]] && return
  VISITED["$id"]=1

  echo "==> [$id]"

  local repo_url="https://github.com/${GITHUB_ORG}/${id}.git"
  local target_dir="${BASE_DIR}/${id}"

  # Repo clonen oder aktualisieren
  if [[ -d "$target_dir/.git" ]]; then
    echo "    Update..."
    git -C "$target_dir" pull --ff-only --quiet
  else
    echo "    Clone ${repo_url}"
    git clone --depth 1 --quiet "$repo_url" "$target_dir"
  fi

  # README.md vorhanden?
  local readme="${target_dir}/README.md"
  if [[ ! -f "$readme" ]]; then
    echo "    WARNUNG: README.md nicht gefunden – keine Dependencies auslesbar"
    return
  fi

  # JSON aus <!--{ ... }--> Kommentar extrahieren
  local meta_json
  meta_json=$(awk '/<!---/{flag=1;next} /--->/  {flag=0} flag' "$readme")

  if [[ -z "$meta_json" ]]; then
    echo "    WARNUNG: Kein JSON-Kommentar gefunden – überspringe"
    return
  fi

  # depends_on-IDs auslesen
  local deps
  deps=$(python3 -c "
import json, sys
data = json.loads(sys.stdin.read())
deps = data.get('depends_on', [])
print(' '.join(deps))
" <<< "$meta_json")

  if [[ -z "$deps" ]]; then
    echo "    Keine Dependencies."
    return
  fi

  echo "    Depends on: $deps"

  # Rekursiv für jede Dependency
  for dep_id in $deps; do
    fetch_challenge "$dep_id"
  done
}

# ── Einstiegspunkt ────────────────────────────────────────────────
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <start-challenge-id>"
  exit 1
fi

mkdir -p "$BASE_DIR"
fetch_challenge "$1"

echo
echo "Fertig. Insgesamt ${#VISITED[@]} Challenge(s) geholt:"
for id in "${!VISITED[@]}"; do
  echo "  ${BASE_DIR}/${id}"
done
