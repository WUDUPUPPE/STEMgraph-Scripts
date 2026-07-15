#!/usr/bin/env bash
# export_graph_data.sh
# Liest alle lokalen Challenges aus ./challenges und baut daraus eine zentrale graph-data.json
# Erweiterung: author und firstused werden jetzt mit exportiert

set -euo pipefail 									# Script bricht bei Fehlern/ungesetzten Variablen sauber ab

BASE_DIR="./challenges" 							# Hier liegen die von den anderen Scripts geklonten Challenge-Repos
OUTPUT_FILE="./graph-data.json" 					# In diese Datei schreibe ich den kompletten Graph für das Frontend

# Prüfen, ob das Basisverzeichnis existiert
if [[ ! -d "$BASE_DIR" ]]; then 					# Wenn es ./challenges nicht gibt
  echo "FEHLER: Basisverzeichnis '$BASE_DIR' nicht gefunden." # Hinweis ausgeben
  echo "Bitte vorher 'fetch_all_challenges.sh' ausführen." # Erinnerung an die Reihenfolge
  exit 1 											# Script sauber abbrechen
fi 													# Wenn Verzeichnis existiert, geht es unten weiter

echo "Baue Graph-Daten aus '$BASE_DIR' nach '$OUTPUT_FILE'..." # Kurze Statusmeldung, damit ich sehe, was passiert

# Übergabe der wichtigen Variablen an Python
export BASE_DIR 									# BASE_DIR für den Python-Teil exportieren
export OUTPUT_FILE 									# OUTPUT_FILE für den Python-Teil exportieren

# Hauptlogik in Python, weil JSON-Parsen und Listenbauen dort angenehmer ist
python3 - << 'PY'
import os 											# os brauche ich für Pfade und Verzeichnisdurchläufe
import json 										# json brauche ich zum Einlesen und Schreiben der Metadaten

# Basisverzeichnis aus der Umgebung holen, Fallback ./challenges
base_dir = os.environ.get("BASE_DIR", "./challenges")

# Pfad für die graph-data.json aus Umgebung holen
output_file = os.environ.get("OUTPUT_FILE", "./graph-data.json")

# Hilfsfunktion: JSON-Block aus einem README ziehen
def extract_meta_json(readme_path: str):
    """
    Liest den JSON-Kommentarblock aus einer README.md heraus.
    Erwartet einen Block zwischen <!--- und ---> am Anfang der Datei.
    """
    if not os.path.isfile(readme_path):  			# Wenn die Datei nicht existiert
        return None                      			# Gebe ich direkt None zurück

    lines = []       								# Liste für die Zeilen im JSON-Block
    in_block = False 								# Flag, ob ich gerade innerhalb des Kommentarblocks bin

    # README öffnen, Encoding robust halten
    with open(readme_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:                 				# Zeile für Zeile durchgehen
            stripped = line.strip()    				# Whitespace am Rand wegnehmen

            # Start-Marker für den JSON-Kommentar (<!---)
            if "<!---" in stripped and not in_block:
                in_block = True         			# Wir sind jetzt im Block
                continue                			# Startzeile selbst nicht übernehmen

            # End-Marker für den JSON-Kommentar (--->)
            if "--->" in stripped and in_block:
                in_block = False       				# Flag zurücksetzen, Block ist zu Ende
                break                   			# Danach interessiert mich der Rest der Datei hier nicht mehr

            # Nur wenn ich im Block bin, sammle ich die Zeilen
            if in_block:
                lines.append(line)

    # Wenn keine Zeilen gefunden wurden, gibt es effektiv keinen JSON-Block
    if not lines:
        return None

    # Alle Zeilen zusammenfügen und Leerraum wegtrimmen
    raw = "".join(lines).strip()
    if not raw:       								# Wenn der Block leer ist
        return None   								# Dann ebenfalls None zurückgeben

    # JSON-Parsing versuchen
    try:
        return json.loads(raw)  					# Wenn das klappt, gebe ich das Dict zurück
    except Exception:
        											# Falls das JSON kaputt ist, ignoriere ich diese Challenge für den Export
        return None

# Liste aller Knoten für graph-data.json
nodes = []
# Liste aller Kanten für graph-data.json
edges = []

# Set, damit ich jede id nur einmal als Node eintrage
seen_ids = set()

# Alle Unterordner unter BASE_DIR durchgehen
for entry in os.listdir(base_dir):          		# Jedes Element im challenges-Ordner anschauen
    repo_dir = os.path.join(base_dir, entry) 		# Absoluten Pfad zum Repo-Verzeichnis bauen
    if not os.path.isdir(repo_dir):         		# Nur Verzeichnisse interessieren mich
        continue                            		# Dateien überspringe ich

    readme_path = os.path.join(repo_dir, "README.md") # Pfad zur README in diesem Repo
    meta = extract_meta_json(readme_path)            # JSON-Metadaten aus der README holen

    if not meta:                       				# Wenn keine verwertbaren Metadaten da sind
        continue                       				# Dieses Repo überspringe ich

    # Challenge-ID aus dem JSON, sonst der Ordnername
    cid = meta.get("id", entry)
    # teaches-Titel aus dem JSON, sonst leer
    teaches = meta.get("teaches", "")
    # keywords-Liste aus dem JSON, sonst leere Liste
    keywords = meta.get("keywords", [])
    # depends_on-Liste aus dem JSON, Fallback leere Liste
    depends_on = meta.get("depends_on", []) or []

    # NEU: author und firstused aus dem Metablock lesen (mit Fallback auf first_used)
    author = meta.get("author", "")                                # Wer die Challenge geschrieben hat
    firstused = meta.get("firstused", meta.get("first_used", ""))  # Wann sie das erste Mal verwendet wurde

    # Falls jemand keywords aus Versehen nicht als Liste geschrieben hat
    if not isinstance(keywords, list):
        # Verpacke ich das in eine Liste mit einem Element
        keywords = [str(keywords)]

    # Nur wenn wir die ID noch nicht gesehen haben, einen neuen Node anlegen
    if cid not in seen_ids:
        nodes.append({
            "id": cid,             					# id ist die Challenge-ID
            "teaches": teaches,    					# teaches ist der Titel / Lerninhalt
            "keywords": keywords,  					# keywords ist die Liste der Schlagwörter
            "author": author,      					# NEU: Autor der Challenge
            "firstused": firstused 					# NEU: erstes Verwendungsdatum
        })
        seen_ids.add(cid)         					# ID als schon verarbeitet markieren

    # depends_on sollte eine Liste sein, sonst wie keine Dependencies behandeln
    if not isinstance(depends_on, list):
        depends_on = []

    # Über alle Voraussetzungen iterieren
    for dep in depends_on:
        # Nur nicht-leere Strings interessieren mich
        if not isinstance(dep, str) or not dep:
            continue
        # Neue Kante in die edges-Liste eintragen
        edges.append({
            "source": dep, 							# source ist die vorausgesetzte Challenge (Dependency)
            "target": cid  							# target ist die aktuelle Challenge, die darauf aufbaut
        })

# Gesamtobjekt für die graph-data.json
graph = {
    "nodes": nodes, 								# Liste aller Knoten
    "edges": edges  								# Liste aller Kanten
}

# Datei zum Schreiben öffnen
with open(output_file, "w", encoding="utf-8") as f:
    # JSON schön formatiert mit Einrückungen schreiben
    json.dump(graph, f, indent=2, ensure_ascii=False)

# Kurze Zusammenfassung ausgeben
print(f"Fertig. {len(nodes)} Nodes und {len(edges)} Edges nach '{output_file}' geschrieben.")
PY
# Ende des Python-Blocks

echo "Export abgeschlossen." # Abschlussmeldung im Bash-Teil