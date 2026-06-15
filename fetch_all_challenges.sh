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
  fi #Repo existiert lokal, weiter mit der Verarbeitung

  # README.md vorhanden?
  local readme="${target_dir}/README.md" #Prüft ob die README existiert
  if [[ ! -f "$readme" ]]; then #Wenn die keine README vorhnden ist dann 
    echo "    WARNUNG: README.md nicht gefunden" #Gibt er die Warnung aus
    return #Verlässt die Funktion
  fi #README vorhanden dann weiter Verarbeiten

  # JSON aus <!--- ... ---> Kommentar extrahieren
  local meta_json 
  meta_json=$(awk '/<!---/{flag=1;next} /--->/ {flag=0} flag' "$readme"). #flag ist eine awk Variable die gesetzt wird beim STart Marker und beim End Marker zurückgesetzt wird 

  if [[ -z "$meta_json" ]]; then #Wenn Json Kommentar nicht existiert oder leer ist, dann
    echo "    WARNUNG: Kein JSON-Kommentar gefunden" #Gibt die Warnung aus
    return #Verlässt die Funktion
  fi #Json Kommentar vorhanden, weiter Verarbeitet

  # Nur gültige UUIDs aus depends_on extrahieren
  local deps 
  deps=$(python3 -c " #Python Skript um die JSON Daten zu parsen und gültige UUIDs aus depends_on zu extrahieren
import json, sys, re #Importiert die Module json, sys und re

try: 
    data = json.loads(sys.stdin.read()) #Liest die JSON Daten von stdin und parst sie in ein Python Objekt
except Exception: #wenn das fehlschlägt wird eine Exception ausgelöst
    sys.exit(0) #Bei Fehler wird mit Status false zurückgegeben

deps = data.get('depends_on', []) #Extrahiert die depends_on aus der JSON Datei
uuid_pattern = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') #Definiert ein Regex Pattern für gültige UUIDs

if isinstance(deps, list): #Prüft ob depends_on eine Liste ist
    for dep in deps: #Iteriert über die Elemente in depends_on
        if isinstance(dep, str) and uuid_pattern.match(dep): #Prüft ob es ein STring ist und ob es dem UUID Pattern entspricht
            print(dep) #Gibt die gültige UUID aus
" <<< "$meta_json") #Leitet die JSON Datei an das Python Skript weiter

  if [[ -z "$deps" ]]; then #Wenn keine gültigen Dependencies gefunden
    echo "    Keine gültigen UUID-Dependencies." #Gibt die Warnung aus
    returnn #Verlässt die Funktion
  fi #Gültige Abhängigkeit dann weiter Veraerbeitem

  echo "    Depends on:" #Gibt die UUIDs der Abhängigkeiten aus
  while IFS= read -r dep_id; do #Liest die gültigen UUIDs Zeile für Zeile ein
    [[ -z "$dep_id" ]] && continue #Wenn Zeile leer überspringen
    echo "      - $dep_id" #Gibt die gültige UUID aus
    fetch_all_challenge "$dep_id" #Ruft die Funktion rekursiv mit der gültigen UUID auf
  done <<< "$deps" #Leitet UUIDs an while Schleife weiter, damit sie Zeile für Zeile verarbeitet werden
}

echo "Lade Repo-Liste von github.com/${GITHUB_ORG}..." #GitHub-API wird abgefragt um die Repos der Organisation zu erhalten
mkdir -p "$BASE_DIR" #Erstellt denn Zielordner wenn er nicht existiert, -p verhindert Fehler falls er existiert

all_ids=() #Bash Array ind dem alle gültigen UUIDs gespeichert werden

for page in 1 2 3; do #GitHub API paginiert die Ergebnisse, hier werden bis zu 300 Repos abgefragt (100 pro Seite)
  ids=$(curl -s "https://api.github.com/orgs/${GITHUB_ORG}/repos?per_page=100&page=${page}" \ 
    | python3 -c " #Python Skript filtert noch mal die Repos und extrahiert gültige UUIDs aus den Repo-Namen
import json, sys, re #Importiert die Module json, sys und re

try:
    repos = json.loads(sys.stdin.read()) #Liest die JSON Daten von stdin und parst sie in ein Python Objekt, das eine Liste von Repos ist
except Exception: #Bei Fehler wird eine Exception ausgelöst
    sys.exit(0) #Bei Fehler wird mit Status false zurückgegeben

uuid_pattern = re.compile(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') #Definiert ein Regex Pattern für gültige UUIDs, das genau 36 Zeichen lang ist und die typische UUID-Struktur hat

if isinstance(repos, list): #Prüft ob die Repos eine Liste ist
    for r in repos: #Iteriert über die Repos
        name = r.get('name', '') #Extrahiert den Namen des Repos, falls er existiert, sonst wird ein leerer String verwendet
        if isinstance(name, str) and uuid_pattern.match(name): #Prüft ob der Name ein String ist und ob er dem UUID Pattern entspricht
            print(name) #Gibt die gültige UUID aus, die im Namen des Repos gefunden wurde
")

  [[ -z "$ids" ]] && break #Wenn keine UUIDs gefunden werden, bricht die Schleife ab

  while IFS= read -r id; do #Liest die gefundenen UUIDs Zeile für Zeile ein
    [[ -z "$id" ]] && continue #Wenn Zeile leer ist, überspringt sie
    all_ids+=("$id") #Fügt die gültige UUID zum all_ids Array hinzu
  done <<< "$ids" #Leitet UUIDs an while Schleife weiter, damit sie Zeile für Zeile verarbeitet werden
done

echo "Gefundene Challenge-Repos: ${#all_ids[@]}" #Gibt die Anzahl der gefundenen Challenge-Repos aus, die in all_ids gespeichert sind
echo #Gibt die gefundenen UUIDs aus

for id in "${all_ids[@]}"; do #Iteriert über alle gefundenen UUIDs in all_ids
  fetch_all_challenge "$id" #Ruft die Funktion fetch_all_challenge mit jeder gefundenen UUID auf, um die Repos zu klonen und die Abhängigkeiten zu verarbeiten
done #Nachdem alle Repos verarbeitet wurden, gibt es eine Zusammenfassung der verarbeiteten Challenges aus

echo #Gibt eine leere Zeile aus
echo "Fertig. Insgesamt ${#VISITED[@]} Challenge(s) verarbeitet:" #Gibt die Anzahl der verarbeiteten Challenges aus, die im VISITED Array gespeichert sind
for id in "${!VISITED[@]}"; do #Iteriert über alle Schlüssel im VISITED Array, die die verarbeiteten UUIDs repräsentieren
  echo "  ${BASE_DIR}/${id}" #Gibt den Pfad zu jedem verarbeiteten Challenge-Repo aus, basierend auf der UUID
done #Gibt die Liste der verarbeiteten Challenges aus
