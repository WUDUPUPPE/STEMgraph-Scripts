#!/usr/bin/env bash
# get_all_challenges.sh
# Holt alle Challenge-Repos von STEMgraph und verarbeitet gültige depends_on-UUIDs rekursiv
# Am Ende wird zusätzlich ausgegeben, was neu geklont und was aktualisiert wurde

set -euo pipefail                                       # Fehler bei ungültigen Variablen oder Befehlen sofort abbrechen

GITHUB_ORG="STEMgraph"                                  # GitHub Organisation, aus der die Challenge-Repos geholt werden
BASE_DIR="./challenges"                                 # Hier werden die Repos lokal gespeichert

declare -A VISITED                                      # Merkt sich, welche UUIDs schon verarbeitet wurden, damit nichts doppelt läuft
declare -a CLONED_REPOS                                 # Liste für Repos, die in diesem Lauf neu geklont wurden
declare -a UPDATED_REPOS                                # Liste für Repos, die in diesem Lauf wirklich aktualisiert wurden

# get_all_challenge: Holt ein Challenge-Repo, extrahiert gültige depends_on-UUIDs und ruft sich rekursiv auf
get_all_challenge() {
  local id="$1"                                         # Die aktuelle Challenge-ID, mit der diese Funktion arbeitet

  # Nur gültige UUIDs zulassen
  if [[ ! "$id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
    echo "Überspringe ungültige ID: $id"                # Ausgabe falls die ID kein gültiges UUID-Format hat
    return                                              # Ungültige ID nicht weiter verarbeiten
  fi

  # Bereits verarbeitet -> nichts doppelt machen
  [[ -n "${VISITED[$id]:-}" ]] && return                # Wenn die ID schon im Array existiert, direkt zurück
  VISITED["$id"]=1                                      # ID als verarbeitet markieren

  echo "==> [$id]"                                      # Ausgabe, welche Challenge gerade verarbeitet wird

  local repo_url="https://github.com/${GITHUB_ORG}/${id}.git" # URL zum GitHub-Repo bauen
  local target_dir="${BASE_DIR}/${id}"                  # Lokales Zielverzeichnis für das Repo

  # Repo clonen oder aktualisieren
  if [[ -d "$target_dir/.git" ]]; then                  # Wenn dort schon ein Git-Repo liegt
    echo "Update..."                                    # Hinweis, dass versucht wird zu aktualisieren

    local old_head=""                                   # Variable für den Commit-Stand vor dem Pull
    local new_head=""                                   # Variable für den Commit-Stand nach dem Pull

    old_head=$(git -C "$target_dir" rev-parse HEAD 2>/dev/null || echo "") # Alten Commit-Hash lesen

    if git -C "$target_dir" pull --ff-only --quiet; then # Repo aktualisieren, wenn möglich nur Fast-Forward
      new_head=$(git -C "$target_dir" rev-parse HEAD 2>/dev/null || echo "") # Neuen Commit-Hash lesen

      if [[ -n "$old_head" && -n "$new_head" && "$old_head" != "$new_head" ]]; then
        UPDATED_REPOS+=("$id")                          # Nur wenn sich der Commit geändert hat, als aktualisiert merken
        echo "Aktualisiert."                            # Ausgabe, dass wirklich neue Änderungen gezogen wurden
      else
        echo "Schon aktuell."                           # Ausgabe, wenn sich nichts geändert hat
      fi
    else
      echo "WARNUNG: Update fehlgeschlagen für $id"     # Warnung bei Fehler im Pull
      return                                            # Repo bei Fehler nicht weiter auswerten
    fi
  else
    echo "Clone ${repo_url}"                            # Ausgabe, welches Repo neu geklont wird

    if git clone --depth 1 --quiet "$repo_url" "$target_dir"; then # Repo neu klonen, nur mit letztem Stand
      CLONED_REPOS+=("$id")                             # Geklonte Repo-ID in die Liste übernehmen
      echo "Geklont."                                   # Ausgabe, dass das Klonen erfolgreich war
    else
      echo "WARNUNG: Clone fehlgeschlagen für $id"      # Warnung falls das Klonen fehlschlägt
      return                                            # Bei Fehler Funktion verlassen
    fi
  fi

  # README.md vorhanden?
  local readme="${target_dir}/README.md"                # Pfad zur README des aktuellen Repos
  if [[ ! -f "$readme" ]]; then
    echo "WARNUNG: README.md nicht gefunden"            # Warnung wenn keine README existiert
    return                                              #  Ohne README keine Metadaten auslesen
  fi

  # JSON aus Kommentar extrahieren
  local meta_json                                       # Variable für den ausgelesenen JSON-Kommentar
  meta_json=$(awk '
    /!---/ {flag=1; next}
    /---/ && flag {flag=0}
    flag
  ' "$readme")                                          # JSON-Block zwischen !--- und --- aus der README herausziehen

  if [[ -z "$meta_json" ]]; then
    echo "WARNUNG: Kein JSON-Kommentar gefunden"        # Warnung wenn kein Metablock gefunden wurde
    return                                              # Ohne JSON keine Abhängigkeiten auslesen
  fi

  # Nur gültige UUIDs aus depends_on extrahieren
  local deps                                            # Variable für die gültigen Dependency-UUIDs
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
" <<< "$meta_json")                                   # JSON an Python übergeben und dort nur gültige UUIDs herausfiltern

  if [[ -z "$deps" ]]; then
    echo "Keine gültigen UUID-Dependencies."          # Ausgabe, wenn keine gültigen Abhängigkeiten gefunden wurden
    return                                            # Dann hier beenden
  fi

  echo "Depends on:"                                  # Überschrift für die gefundenen Abhängigkeiten
  while IFS= read -r dep_id; do                       # Jede Dependency-Zeile einzeln lesen
    [[ -z "$dep_id" ]] && continue                    # Leere Zeilen überspringen
    echo "- $dep_id"                                  # Abhängigkeit im Terminal ausgeben
    get_all_challenge "$dep_id"                       # Rekursiver Aufruf mit der gefundenen Dependency
  done <<< "$deps"                                    # Dependencies zeilenweise in die while-Schleife geben
}

# Prüfen, ob genau eine Start-ID übergeben wurde
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <start-challenge-id>"               # Kurze Hilfe zur richtigen Verwendung
  exit 1                                              # Script beenden, wenn das Argument fehlt
fi

mkdir -p "$BASE_DIR"                                  # Zielordner anlegen, falls er noch nicht existiert

get_all_challenge "$1"                                # Start mit der übergebenen Challenge-ID

echo # Leerzeile für bessere Lesbarkeit
echo "Fertig. Insgesamt ${#VISITED[@]} Challenges verarbeitet." # Ausgabe der Gesamtanzahl

echo # Leerzeile
echo "Neu geklont:"                                   # Überschrift für neu geklonte Repos
if [[ ${#CLONED_REPOS[@]} -eq 0 ]]; then
  echo "Keine neuen Repos geklont."                   # Falls in diesem Lauf nichts neu geklont wurde
else
  for id in "${CLONED_REPOS[@]}"; do
    echo "- $id"                                      # Jede neu geklonte ID einzeln ausgeben
  done
fi

echo # Leerzeile
echo "Aktualisiert:"                                  # Überschrift für wirklich geänderte Repos
if [[ ${#UPDATED_REPOS[@]} -eq 0 ]]; then
  echo "Keine Repos aktualisiert."                    # Falls kein Repo neue Änderungen hatte
else
  for id in "${UPDATED_REPOS[@]}"; do
    echo "- $id"                                      # Jede wirklich aktualisierte ID einzeln ausgeben
  done
fi