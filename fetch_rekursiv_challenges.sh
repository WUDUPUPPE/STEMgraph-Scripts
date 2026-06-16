#!/usr/bin/env bash
# fetch_rekursiv_challenges.sh
# Holt alle Challenge-Repos von STEMgraph rekursiv über depends_on

set -euo pipefail # Fehler bei ungültigen Variablen oder Befehlen

GITHUB_ORG="STEMgraph" #GitHub Org ist auf STEMgraph gesetzt
BASE_DIR="./challenges" #Es entseht ein Unterordner challenges, in dem die Repos abgelegt werden

declare -A VISITED # Assoziatives Array, um bereits verarbeitete UUIDs nicht doppelt zu speichern

#fetch_rekursiv_challenge: Holt ein Challenge-Repo, extrahiert gültige depends_on-UUIDs und ruft sich rekursiv auf
fetch_rekursiv_challenge() { 
  local id="$1" #Die Funktion wird in eine Variable gesetzt, so arbeite ich nur noch mit der id

  # Nur gültige UUIDs zulassen
  if [[ ! "$id" =~ ^[0-9a-fA-F-]{36}$ ]]; then #Sollte die id nicht 36 Zeichen lang sein wird sie übersprungen
    echo "  Überspringe ungültige ID: $id" #Gibt die ungültige ID aus
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
      echo "    WARNUNG: Update fehlgeschlagen für $id" #Gibt eine Warnung aus wenn fehlschlägt
      return #Beim Fehlschlagen die Funktion verlassen
    }
  else #Wenn es nicht existiert wird es geklont
    echo "    Clone ${repo_url}" # Gibt das geklonte Repo aus
    git clone --depth 1 --quiet "$repo_url" "$target_dir" #Prüft ob das Klonen erfolgreich war, --ff onlyführt einen Fast Forward Pull aus, --quiet gibt weniger Ausgabe, --depth 1 klont nur den letzten Commit
  fi #Repo existiert lokal, weiter mit der Verarbeitung

  # README.md vorhanden?
  local readme="${target_dir}/README.md" #Prüft ob die README existiert
  if [[ ! -f "$readme" ]]; then #Wenn die keine README vorhnden ist dann
    echo "    WARNUNG: README.md nicht gefunden – keine Dependencies auslesbar" #Gibt er die Warnung aus
    return #Verlässt die Funktion
  fi #README vorhanden dann weiter Verarbeiten

  # JSON aus <!--{ ... }--> Kommentar extrahieren
  local meta_json 
  meta_json=$(awk '/<!---/{flag=1;next} /--->/  {flag=0} flag' "$readme") #flag ist eine awk Variable die gesetzt wird beim STart Marker und beim End Marker zurückgesetzt wird

  if [[ -z "$meta_json" ]]; then #Wenn Json Kommentar nicht existiert oder leer ist, dann
    echo "    WARNUNG: Kein JSON-Kommentar gefunden – überspringe" #Gibt die Warnung aus
    return #Verlässt die Funktion
  fi #Json Kommentar vorhanden, weiter Verarbeiten

  # depends_on-IDs auslesen
  local deps 
  deps=$(python3 -c " #Python Skript filtert noch mal die Repos und extrahiert gültige UUIDs aus den Repo-Namen
import json, sys #Importiert die Module json und sys
data = json.loads(sys.stdin.read()) #Liest die JSON Daten aus der Standardeingabe und parst sie in ein Python Dictionary
deps = data.get('depends_on', []) #Extrahiert die depends_on Liste aus den Daten, falls sie nicht existiert wird eine leere Liste zurückgegeben
print(' '.join(deps)) #Gibt die gültigen UUIDs aus der depends_on Liste als durch Leerzeichen getrennte Zeichenkette aus
" <<< "$meta_json") #Leitet den Inhalt von meta_json als Standardeingabe an das Python Skript weiter

  if [[ -z "$deps" ]]; then #Wenn keine Dependencies gefunden wurden
    echo "    Keine Dependencies." #Warnung ausgeben das keine Dependencies gefunden wurden
    return #Funktion verlassen
  fi #Dependencies vorhanden, weiter Verarbeiten

  echo "    Depends on: $deps" #Gibt die gefundenen Dependencies aus, die in der README gefunden wurden

  # Rekursiv für jede Dependency
  for dep_id in $deps; do #Schleife über die gefundenen Dependencies, die in der Variable deps gespeichert sind
    fetch_rekursiv_challenge "$dep_id" #Ruft die Funktion fetch_rekursiv_challenge rekursiv für jede gefundene Dependency auf, um auch deren Repos zu holen
  done #Ende der Schleife über die Dependencies
}

# --- Hauptprogramm beginnt hier - prüft Argumente und startet die Rekursion ---
echo "    --- Hauptprogramm beginnt - prüft Argumente und startet Rekursion ---"
if [[ $# -ne 1 ]]; then #Wenn die Anzahl der Argumente nicht gleich 1 ist, dann
  echo "Usage: $0 <start-challenge-id>" #Gibt die richtige Verwendung des Skripts aus, wenn die Anzahl der Argumente falsch ist
  exit 1 #Verlässt das Skript mit einem Fehlercode, wenn die Anzahl der Argumente falsch ist
fi #Wenn die Anzahl der Argumente korrekt ist, wird das Skript fortgesetzt

mkdir -p "$BASE_DIR" #Erstellt den Zielordner, falls er nicht existiert, -p verhindert Fehler, wenn er bereits existiert
fetch_rekursiv_challenge "$1" #Ruft die Funktion fetch_rekursiv_challenge mit der ersten Argument auf, um die Rekursion zu starten und die Challenge-Repos zu holen

echo
echo "Fertig. Insgesamt ${#VISITED[@]} Challenge(s) geholt:" #Gibt die Anzahl der gesammelten Challenges aus, die im VISITED Array gespeichert sind
for id in "${!VISITED[@]}"; do #Schleife über die Schlüssel des VISITED Arrays, um die IDs der gesammelten Challenges auszugeben
  echo "  ${BASE_DIR}/${id}" #Gibt den Pfad zu jeder gesammelten Challenge aus, basierend auf der ID und dem BASE_DIR
done #Ende der Schleife über die gesammelten Challenges
