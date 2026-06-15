#!/usr/bin/env bash
# fetch_all_challenges.sh
# Holt alle Challenge-Repos von STEMgraph und verarbeitet gültige depends_on-UUIDs rekursiv

set -euo pipefail # Fehler bei ungültigen Variablen oder Befehlen

GITHUB_ORG="STEMgraph" #GitHub Org ist auf STEMgraph gesetzt
BASE_DIR="./challenges" #Es entseht ein Unterordner challenges, in dem die Repos abgelegt werden

declare -A VISITED # Assoziatives Array, um bereits verarbeitete UUIDs nicht doppelt zu speichern

#fetch_all_challenge: Holt ein Challenge-Repo, extrahiert gültige depends_on-UUIDs und ruft sich rekursiv auf
fetch_all_challenge() { 
  local id="$1" #Die Funktion wird in eine Variable gesetzt, so arbeite ich nur noch mit der id

  # Nur gültige UUIDs zulassen
  if [[ ! "$id" =~ ^[0-9a-fA-F-]{36}$ ]]; then #Sollte die id nicht 36 Zeichen lang sein wird sie übersprungen
    echo "    Überspringe ungültige ID: $id" #Gibt die ungültige ID aus
    return #Die Funktion wird verlassen
  fi #Funktion verlassen wenn id ungültig

  # Bereits verarbeitet → nichts tun
  [[ -n "${VISITED[$id]:-}" ]] && return #wenn die id im VISITED Array existiert, sofort zurückkehren
  VISITED["$id"]=1 #Makiert die id als gesehen oder verarbeitet

  echo "==> [$id]" #Gibt die id im Terminal aus die verarbeitet wird

  local repo_url="https://github.com/${GITHUB_ORG}/${id}.git" #Baut aus der GITUB_ORG und der BASE_DIR die URL fürs Repo zusammen
  local target_dir="${BASE_DIR}/${id}" #Lokaler Pfad wo das Repo abgelegt wird 

  # Repo clonen oder aktualisieren
  if [[ -d "$target_dir/.git" ]]; then #Prüft ob im Zielodner schon ein Git-Repo existiert
    echo "    Update..." #Gibt aus wenn das Repo aktualisiert wurde
    git -C "$target_dir" pull --ff-only --quiet || { #Prüft ob das Repo aktualisiert werden kann
      echo "    WARNUNG: Update fehlgeschlagen für $id" #Gibt eine Warnung aus wenn  das Update fehlschlägt
      return #Beim Fehlschlagen die Funktion verlassen
    }
  else #Wenn es nicht existiert wird es geklont
    echo "    Clone ${repo_url}" #Gibt das geklonte Repo aus
    git clone --depth 1 --quiet "$repo_url" "$target_dir" || { #Prüft ob das Klonen erfolgreich war, --ff onlyführt einen Fast Forward Pull aus, --quiet gibt weniger Ausgabe, --depth 1 klont nur den letzten Commit
      echo "    WARNUNG: Clone fehlgeschlagen für $id" #Gibt eine Warnung aus wenn das Klonen fehlschlägt
      return #Verlässt die Funktion
    }
  fi #Repo existiert jetzt lokal, weiter mit der Verarbeitung

  # README.md vorhanden?
  local readme="${target_dir}/README.md"
  if [[ ! -f "$readme" ]]; then
    echo "    WARNUNG: README.md nicht gefunden"
    return
  fi

  # JSON aus <!--- ... ---> Kommentar extrahieren
  local meta_json
  meta_json=$(awk '/<!---/{flag=1;next} /--->/ {flag=0} flag' "$readme")

  if [[ -z "$meta_json" ]]; then
    echo "    WARNUNG: Kein JSON-Kommentar gefunden"
    return
  fi

  # Nur gültige UUIDs aus depends_on extrahieren
  local deps
  deps=$(python3 -c "
import json, sys, re

try:
    data = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

deps = data.get('depends_on', [])
uuid_pattern = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')

if isinstance(deps, list):
    for dep in deps:
        if isinstance(dep, str) and uuid_pattern.match(dep):
            print(dep)
" <<< "$meta_json")

  if [[ -z "$deps" ]]; then
    echo "    Keine gültigen UUID-Dependencies."
    return
  fi

  echo "    Depends on:"
  while IFS= read -r dep_id; do
    [[ -z "$dep_id" ]] && continue
    echo "      - $dep_id"
    fetch_all_challenge "$dep_id"
  done <<< "$deps"
}

echo "Lade Repo-Liste von github.com/${GITHUB_ORG}..."
mkdir -p "$BASE_DIR"

all_ids=()

for page in 1 2 3; do
  ids=$(curl -s "https://api.github.com/orgs/${GITHUB_ORG}/repos?per_page=100&page=${page}" \
    | python3 -c "
import json, sys, re

try:
    repos = json.loads(sys.stdin.read())
except Exception:
    sys.exit(0)

uuid_pattern = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')

if isinstance(repos, list):
    for r in repos:
        name = r.get('name', '')
        if isinstance(name, str) and uuid_pattern.match(name):
            print(name)
")

  [[ -z "$ids" ]] && break

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    all_ids+=("$id")
  done <<< "$ids"
done

echo "Gefundene Challenge-Repos: ${#all_ids[@]}"
echo

for id in "${all_ids[@]}"; do
  fetch_all_challenge "$id"
done

echo
echo "Fertig. Insgesamt ${#VISITED[@]} Challenge(s) verarbeitet:"
for id in "${!VISITED[@]}"; do
  echo "  ${BASE_DIR}/${id}"
done
