#!/usr/bin/env bash
# export_graph_data.sh
# Liest alle lokalen Challenges aus ./challenges und baut daraus eine zentrale graph-data.json

set -euo pipefail                                  # Script bricht bei Fehlern/ungesetzten Variablen sauber ab

BASE_DIR="./challenges"                            # Hier liegen die von den anderen Scripts geklonten Challenge-Repos
OUTPUT_FILE="./graph-data.json"                    # In diese Datei schreibe ich den kompletten Graph für das Frontend

# Prüfen, ob das Basisverzeichnis existiert
if [[ ! -d "$BASE_DIR" ]]; then                    # Wenn es ./challenges nicht gibt
  echo "FEHLER: Basisverzeichnis '$BASE_DIR' nicht gefunden."  # Hinweis ausgeben
  echo "Bitte vorher 'fetch_all_challenges.sh' ausführen."     # Ich erinnere mich selbst dran, wie die Reihenfolge ist
  exit 1                                           # Script sauber abbrechen
fi                                                 # Wenn Verzeichnis existiert, geht es unten weiter

echo "Baue Graph-Daten aus '$BASE_DIR' nach '$OUTPUT_FILE'..." # Kurze Statusmeldung, damit ich sehe was passiert

# Übergabe der wichtigen Variablen an Python
export BASE_DIR                                    # BASE_DIR für den Python-Teil exportieren
export OUTPUT_FILE                                 # OUTPUT_FILE für den Python-Teil exportieren

# Hauptlogik in Python, weil JSON-Parsen und Listenbauen dort angenehmer ist
python3 - << 'PY'
import os # os brauche ich für Pfade und Verzeichnisdurchläufe
import json                                        # json brauche ich zum Einlesen und Schreiben der Metadaten

base_dir = os.environ.get("BASE_DIR", "./challenges")   # BASE_DIR aus der Umgebung holen, Fallback ./challenges
output_file = os.environ.get("OUTPUT_FILE", "./graph-data.json")  # Pfad für die graph-data.json aus Umgebung holen

# Hilfsfunktion: JSON-Block zwischen <!--- und ---> aus einem README ziehen
def extract_meta_json(readme_path: str):           # Funktion bekommt den Pfad zur README
    if not os.path.isfile(readme_path):            # Wenn die Datei nicht existiert
        return None                                # Gebe ich direkt None zurück
    lines = []                                     # Liste für die Zeilen im JSON-Block
    in_block = False                               # Flag, ob ich gerade innerhalb des Kommentarblocks bin
    with open(readme_path, "r", encoding="utf-8", errors="ignore") as f:  # README öffnen, Encoding robust halten
        for line in f:                             # Zeile für Zeile durchgehen
            if "<!---" in line:                    # Start-Marker für den JSON-Kommentar
                in_block = True                    # Flag setzen, dass jetzt der Block beginnt
                continue                           # Diese Zeile selbst nicht inhaltlich mitnehmen
            if "--->" in line and in_block:        # End-Marker für den JSON-Kommentar
                in_block = False                   # Flag zurücksetzen, Block ist zu Ende
                break                              # Danach interessiert mich der Rest der Datei hier nicht mehr
            if in_block:                           # Nur wenn ich im Block bin
                lines.append(line)                 # Zeile sammeln
    if not lines:                                  # Wenn keine Zeilen gefunden wurden
        return None                                # Gibt es effektiv keinen JSON-Block
    raw = "".join(lines).strip()                   # Alle Zeilen zusammenfügen und Leerraum wegtrimmen
    if not raw:                                    # Wenn der Block leer ist
        return None                                # Dann ebenfalls None zurückgeben
    try:                                           # JSON-Parsing versuchen
        return json.loads(raw)                     # Wenn das klappt, gebe ich das Dict zurück
    except Exception:                              # Falls das JSON kaputt ist
        return None                                # Ignoriere ich diese Challenge für den Export

nodes = []                                         # Liste aller Knoten für graph-data.json
edges = []                                         # Liste aller Kanten für graph-data.json

seen_ids = set()                                   # Set, damit ich jede id nur einmal als Node eintrage

# Alle Unterordner unter BASE_DIR durchgehen
for entry in os.listdir(base_dir):                 # Jedes Element im challenges-Ordner anschauen
    repo_dir = os.path.join(base_dir, entry)       # Absoluten Pfad zum Repo-Verzeichnis bauen
    if not os.path.isdir(repo_dir):                # Nur Verzeichnisse interessieren mich
        continue                                   # Dateien überspringe ich
    readme_path = os.path.join(repo_dir, "README.md")  # Pfad zur README in diesem Repo
    meta = extract_meta_json(readme_path)          # JSON-Metadaten aus der README holen
    if not meta:                                   # Wenn keine verwertbaren Metadaten da sind
        continue                                   # Dieses Repo überspringe ich

    cid = meta.get("id", entry)                    # Challenge-ID aus dem JSON, sonst der Ordnername
    teaches = meta.get("teaches", "")              # teaches-Titel aus dem JSON, sonst leer
    keywords = meta.get("keywords", [])            # keywords-Liste aus dem JSON, sonst leere Liste
    depends_on = meta.get("depends_on", []) or []  # depends_on-Liste aus dem JSON, Fallback leere Liste

    if not isinstance(keywords, list):             # Falls jemand keywords aus Versehen nicht als Liste geschrieben hat
        keywords = [str(keywords)]                 # Verpacke ich das in eine Liste mit einem Element

    if cid not in seen_ids:                        # Prüfen, ob ich die ID schon als Node drin habe
        nodes.append({                             # Neuen Node in die nodes-Liste schieben
            "id": cid,                             # id ist die Challenge-ID
            "teaches": teaches,                    # teaches ist der Titel / Lerninhalt
            "keywords": keywords                   # keywords ist die Liste der Schlagwörter
        })
        seen_ids.add(cid)                          # ID als schon verarbeitet markieren

    if not isinstance(depends_on, list):           # depends_on sollte eine Liste sein
        depends_on = []                            # Wenn nicht, behandle ich das wie keine Dependencies

    for dep in depends_on:                         # Über alle Voraussetzungen iterieren
        if not isinstance(dep, str) or not dep:    # Nur nicht-leere Strings interessieren mich
            continue                               # Alles andere überspringen
        edges.append({                             # Neue Kante in die edges-Liste eintragen
            "source": dep,                         # source ist die vorausgesetzte Challenge (Dependency)
            "target": cid                          # target ist die aktuelle Challenge, die darauf aufbaut
        })

graph = {                                          # Gesamtobjekt für die graph-data.json
    "nodes": nodes,                                # Liste aller Knoten
    "edges": edges                                 # Liste aller Kanten
}

with open(output_file, "w", encoding="utf-8") as f:  # Datei zum Schreiben öffnen
    json.dump(graph, f, indent=2, ensure_ascii=False) # JSON schön formatiert mit Einrückungen schreiben

print(f"Fertig. {len(nodes)} Nodes und {len(edges)} Edges nach '{output_file}' geschrieben.")  # Kurze Zusammenfassung ausgeben
PY                                                   # Ende des Python-Blocks

echo "Export abgeschlossen."                         # Abschlussmeldung im Bash-Teil
