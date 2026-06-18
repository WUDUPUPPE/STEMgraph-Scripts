#!/usr/bin/env bash
# fetch_subgraph_challenges.sh
# Berechnet einen Pfad (Subgraph) zwischen zwei Challenges auf Basis der graph-data.json

set -euo pipefail                                  # Script bricht bei Fehlern/ungesetzten Variablen sauber ab

BASE_DIR="./challenges"                            # Hier liegen die lokalen Repos, falls ich Pfade ausgeben will
GRAPH_FILE="./graph-data.json"                     # Diese Datei wurde vorher von export_graph_data.sh gebaut

# Prüfen, ob genau zwei Argumente übergeben wurden
if [[ $# -ne 2 ]]; then                            # Wenn nicht genau zwei Argumente da sind
  echo "Usage: $0 <start-challenge-id> <ziel-challenge-id>"  # Kurze Hilfe ausgeben
  echo "Beispiel:"                                 # Beispielzeile, damit ich es später nicht googeln muss
  echo "  $0 c1f2cd2b-3ffc-44a8-86b1-111f9d246c10 2d1d315d-bb92-48c0-b19f-19529a45e5ff"  # Beispielaufruf mit zwei UUIDs
  exit 1                                           # Script abbrechen, weil die Eingabe nicht passt
fi                                                 # Wenn zwei Argumente da sind, geht es weiter

START_ID="$1"                                      # Erste Argument ist die Start-Challenge
TARGET_ID="$2"                                     # Zweites Argument ist die Ziel-Challenge

# Prüfen, ob die graph-data.json existiert
if [[ ! -f "$GRAPH_FILE" ]]; then                  # Wenn die Datei nicht gefunden wird
  echo "FEHLER: '$GRAPH_FILE' wurde nicht gefunden."  # Klarer Fehlerhinweis
  echo "Bitte vorher 'export_graph_data.sh' ausführen."  # Erinnerung an die richtige Reihenfolge
  exit 1                                           # Script abbrechen
fi                                                 # Wenn die Datei da ist, mache ich weiter

# Prüfen, ob das Basisverzeichnis für die Repos existiert
if [[ ! -d "$BASE_DIR" ]]; then                    # Wenn ./challenges nicht existiert
  echo "WARNUNG: Basisverzeichnis '$BASE_DIR' nicht gefunden."  # Nur Warnung, weil ich für die Pfadliste darauf zugreifen möchte
  echo "Die Pfade zu den lokalen Repos können dann eventuell nicht angezeigt werden."  # Erklärung, was das bedeutet
fi                                                 # Kein harter Fehler, Subgraph-Berechnung geht trotzdem

# Wichtige Variablen für Python exportieren
export BASE_DIR                                    # BASE_DIR für Python verfügbar machen
export GRAPH_FILE                                  # GRAPH_FILE für Python verfügbar machen
export START_ID                                    # START_ID für Python verfügbar machen
export TARGET_ID                                   # TARGET_ID für Python verfügbar machen

# Hauptlogik in Python: JSON laden, Graph bauen, Pfad mit BFS suchen und ausgeben
python3 - << 'PY'
import os                                          # os für Pfade holen
import json                                        # json zum Einlesen der graph-data.json
from collections import deque                      # deque für eine saubere BFS-Queue

base_dir = os.environ.get("BASE_DIR", "./challenges")      # BASE_DIR aus Umgebung holen
graph_file = os.environ.get("GRAPH_FILE", "./graph-data.json")  # Pfad zur graph-data.json holen
start_id = os.environ.get("START_ID")              # Start-Challenge-ID aus Umgebung
target_id = os.environ.get("TARGET_ID")            # Ziel-Challenge-ID aus Umgebung

if not start_id or not target_id:                  # Wenn eine der beiden IDs fehlt
    print("FEHLER: START_ID oder TARGET_ID nicht gesetzt.")  # Fehler ausgeben
    raise SystemExit(1)                            # Script abbrechen

# graph-data.json einlesen
try:                                               # Lesen und Parsen in einem try-Block
    with open(graph_file, "r", encoding="utf-8") as f:  # Datei öffnen
        graph_data = json.load(f)                  # JSON in ein Python-Objekt laden
except Exception as e:                             # Falls etwas schiefgeht
    print(f"FEHLER: Konnte '{graph_file}' nicht lesen: {e}")  # Fehlermeldung mit Grund
    raise SystemExit(1)                            # Script abbrechen

nodes = graph_data.get("nodes", [])                # Liste der Knoten aus dem JSON holen
edges = graph_data.get("edges", [])                # Liste der Kanten aus dem JSON holen

# Adjazenzliste für die BFS bauen: source -> [targets]
adj = {}                                           # Leere Map für Nachbarn
for edge in edges:                                 # Jede Kante durchgehen
    source = edge.get("source")                    # Quelle der Kante (Voraussetzung)
    target = edge.get("target")                    # Ziel der Kante (Challenge, die darauf aufbaut)
    if not source or not target:                   # Wenn eine Seite fehlt, ist die Kante unbrauchbar
        continue                                   # Kante überspringen
    adj.setdefault(source, []).append(target)      # Liste von Nachbarn für source pflegen

# Metadaten pro ID für die schöne Ausgabe aufbauen
meta_by_id = {}                                    # Map von id -> Metadaten
for node in nodes:                                 # Über alle Knoten iterieren
    cid = node.get("id")                           # Challenge-ID aus dem Node
    if not cid:                                    # Ohne ID ist der Node nutzlos
        continue                                   # Node überspringen
    meta_by_id[cid] = {                            # Metadaten für diese ID speichern
        "teaches": node.get("teaches", ""),        # teaches-Titel merken
        "keywords": node.get("keywords", []),      # keywords-Liste merken
    }

# Prüfen, ob Start/Ziel überhaupt im Graph vorkommen
all_ids = set(meta_by_id.keys())                   # Alle bekannten IDs aus den Knoten
all_ids.update(adj.keys())                         # Quellen aus den Kanten dazunehmen
for targets in adj.values():                       # Über alle Ziel-Listen der Kanten
    all_ids.update(targets)                        # Alle Ziel-IDs dem Set hinzufügen

if start_id not in all_ids:                        # Wenn die Start-ID unbekannt ist
    print(f"FEHLER: Start-ID '{start_id}' kommt im Graph nicht vor.")  # Fehlermeldung ausgeben
    raise SystemExit(1)                            # Script abbrechen

if target_id not in all_ids:                       # Wenn die Ziel-ID unbekannt ist
    print(f"FEHLER: Ziel-ID '{target_id}' kommt im Graph nicht vor.")  # Fehlermeldung ausgeben
    raise SystemExit(1)                            # Script abbrechen

# BFS von start_id nach target_id
queue = deque()                                    # Queue für die Knoten, die ich als nächstes besuche
visited = set()                                    # Set, um doppelte Besuche zu vermeiden
prev = {}                                          # Map: node -> Vorgänger im Pfad

queue.append(start_id)                             # Startknoten in die Queue legen
visited.add(start_id)                              # Startknoten als besucht markieren

found = False                                      # Flag, ob ich die Ziel-ID gefunden habe

while queue:                                       # Solange noch Knoten in der Queue sind
    current = queue.popleft()                      # Nächsten Knoten aus der Queue holen
    if current == target_id:                       # Wenn ich am Ziel angekommen bin
        found = True                               # Flag setzen
        break                                      # Schleife beenden

    neighbors = adj.get(current, [])               # Nachbarn des aktuellen Knotens holen
    for n in neighbors:                            # Jeden Nachbarn durchgehen
        if n not in visited:                       # Nur unbesuchte Nachbarn interessieren mich
            visited.add(n)                         # Nachbarn als besucht markieren
            prev[n] = current                      # Vorgänger im Pfad merken
            queue.append(n)                        # Nachbarn in die Queue legen

if not found:                                      # Wenn kein Pfad zum Ziel gefunden wurde
    print(f"Kein Pfad von '{start_id}' nach '{target_id}' gefunden.")  # Info ausgeben
    raise SystemExit(0)                            # Script ohne Fehlercode beenden

# Pfad rekonstrieren, indem ich von der Ziel-ID zurücklaufe
path = []                                          # Liste für die Pfad-IDs
node = target_id                                   # Startpunkt für die Rückwärtsrekonstruktion ist die Ziel-ID
while True:                                        # Solange, bis ich beim Start angekommen bin
    path.append(node)                              # Aktuellen Knoten an den Pfad anhängen
    if node == start_id:                           # Wenn ich die Start-ID erreicht habe
        break                                      # Rekonstruktion beenden
    node = prev.get(node)                          # Vorgänger des aktuellen Knotens holen
    if node is None:                               # Falls hier etwas fehlt, ist intern etwas schiefgelaufen
        print("Interner Fehler bei der Pfadreonstruktion.")  # Fehlermeldung ausgeben
        raise SystemExit(1)                        # Script abbrechen

path.reverse()                                     # Pfad umdrehen, damit er von Start nach Ziel zeigt

# Pfad sauber ausgeben
print()                                            # Leere Zeile zur Trennung
print(f"Pfad von {start_id} nach {target_id}:")    # Überschrift mit Start- und Ziel-ID
print("----------------------------------------")   # Trennlinie für die Optik

for idx, cid in enumerate(path):                   # Über alle Knoten im Pfad iterieren
    if cid == start_id:                            # Wenn es die Start-ID ist
        marker = "START"                           # Marker auf START setzen
    elif cid == target_id:                         # Wenn es die Ziel-ID ist
        marker = "ZIEL"                            # Marker auf ZIEL setzen
    else:                                          # Alle Zwischenknoten
        marker = f"Step {idx}"                     # Step-Nummer als Marker
    teaches = meta_by_id.get(cid, {}).get("teaches", "")  # teaches-Titel für diese ID holen
    line = f"{marker}: {cid}"                      # Basiszeile mit Marker und ID bauen
    if teaches:                                    # Wenn es einen teaches-Titel gibt
        line += f"  |  {teaches}"                  # Titel mit Pipe dranhängen
    print(line)                                    # Zeile ausgeben

print()                                            # Leere Zeile zur Trennung
print("Lokale Repo-Pfade zu diesem Pfad:")         # Überschrift für die lokalen Pfade
print("----------------------------------------")   # Trennlinie

for cid in path:                                   # Noch einmal über den Pfad laufen
    repo_path = os.path.join(base_dir, cid)        # Pfad zum lokalen Repo der Challenge bauen
    print(f"- {repo_path}")                        # Pfad ausgeben, auch wenn der Ordner evtl. fehlt
PY                                                 # Ende des Python-Blocks
