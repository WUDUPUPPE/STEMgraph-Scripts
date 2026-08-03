#!/usr/bin/env bash
# load_neo4j.sh
# Liest graph-data.json und lädt alle Nodes/Edges als Cypher-Statements in Neo4j
# Erwartet: NEO4J_URI, NEO4J_USER, NEO4J_PW als Umgebungsvariablen

set -euo pipefail                                               # Script bricht bei Fehlern/ungesetzten Variablen oder Fehlern sauber ab

INPUT_FILE="./graph-data.json"                                  # Hier liegt die von export_graph_data.sh erzeugte Graph-Datei

# Prüfen, ob die graph-data.json überhaupt existiert
if [[ ! -f "$INPUT_FILE" ]]; then                               # Wenn die Datei nicht gefunden wird
  echo "FEHLER: '$INPUT_FILE' nicht gefunden."                  # Hinweis an die Konsole ausgeben
  echo "Bitte vorher 'export_graph_data.sh' ausführen."         # Erinnerung an die richtige Reihenfolge
  exit 1                                                        # Script mit Fehlercode beenden
fi                                                              # Wenn die Datei existiert, unten weitermachen

# Prüfen, ob die nötigen Verbindungsdaten gesetzt sind
: "${NEO4J_URI:?FEHLER: NEO4J_URI ist nicht gesetzt}"           # Bricht ab, wenn NEO4J_URI fehlt
: "${NEO4J_USER:?FEHLER: NEO4J_USER ist nicht gesetzt}"         # Bricht ab, wenn NEO4J_USER fehlt
: "${NEO4J_PW:?FEHLER: NEO4J_PW ist nicht gesetzt}"             # Bricht ab, wenn NEO4J_PW fehlt

echo "Lade '$INPUT_FILE' nach Neo4j ($NEO4J_URI)..."            # Kurze Statusmeldung, damit ich sehe, was passiert

# Wichtige Variablen für den Python-Teil exportieren
export INPUT_FILE                                               # Pfad zur graph-data.json für Python exportieren
export NEO4J_URI                                                # Neo4j-URI für Python exportieren
export NEO4J_USER                                               # Neo4j-User für Python exportieren
export NEO4J_PW                                                 # Neo4j-Passwort für Python exportieren

# Hauptlogik in Python, weil JSON einlesen und Neo4j-Treiber dort angenehmer ist
python3 - << 'PY'
import os                                                       # os brauche ich für Umgebungsvariablen und Pfade
import json                                                     # json brauche ich zum Einlesen der graph-data.json
from neo4j import GraphDatabase                                 # offizieller Neo4j-Python-Treiber

# Verbindungsdaten aus der Umgebung holen
uri = os.environ["NEO4J_URI"]                                   # URI der Neo4j-Datenbank
user = os.environ["NEO4J_USER"]                                 # Benutzername für Neo4j
password = os.environ["NEO4J_PW"]                               # Passwort für Neo4j
input_file = os.environ.get("INPUT_FILE", "./graph-data.json")  # Pfad zur graph-data.json

# graph-data.json einlesen
with open(input_file, "r", encoding="utf-8") as f:              # Datei im Lesemodus öffnen
    graph = json.load(f)                                        # JSON-Inhalt in ein Python-Dict laden

nodes = graph.get("nodes", [])                                  # Liste aller Challenge-Nodes aus dem Graph-Objekt holen
edges = graph.get("edges", [])                                  # Liste aller Abhängigkeits-Kanten aus dem Graph-Objekt holen

# Verbindung zu Neo4j aufbauen
driver = GraphDatabase.driver(uri, auth=(user, password))       # Neo4j-Driver mit URI und Auth erstellen

# Legt alle Challenges als Nodes in Neo4j an oder aktualisiert sie. MERGE sorgt dafür, dass nichts doppelt angelegt wird.
def load_nodes(tx, nodes):
    for n in nodes:                                             # Über alle Nodes aus der graph-data.json iterieren
        tx.run(
            """
            MERGE (c:Challenge {uuid: $id})
            SET c.title = $teaches, c.keywords = $keywords, c.author = $author, c.first_use = $firstused
            """,
            id=n.get("id", ""),                                 # Challenge-ID aus dem Node-Dict
            teaches=n.get("teaches", ""),                       # Titel / Lerninhalt aus dem Node-Dict
            keywords=n.get("keywords", []),                     # Schlagwörter aus dem Node-Dict
            author=n.get("author", ""),                         # Autor aus dem Node-Dict
            firstused=n.get("firstused", "")                    # Erstverwendung aus dem Node-Dict
        )

# Legt alle BUILDS_ON-Beziehungen zwischen Challenges an. target BUILDS_ON source bedeutet: Challenge target baut auf Challenge source auf.
def load_edges(tx, edges):
    for e in edges:                                             # Über alle Kanten aus der graph-data.json iterieren
        tx.run(
            """
            MATCH (target:Challenge {uuid: $target})
            MATCH (source:Challenge {uuid: $source})
            MERGE (target)-[:BUILDS_ON]->(source)
            """,
            target=e.get("target", ""),                         # Ziel-Challenge (die auf etwas aufbaut)
            source=e.get("source", "")                          # Quell-Challenge (die Voraussetzung)
        )

# Session öffnen und Nodes/Kanten in Neo4j schreiben
with driver.session() as session:                               # Session-Kontext öffnen
    session.execute_write(load_nodes, nodes)                    # Erst alle Nodes laden/aktualisieren
    session.execute_write(load_edges, edges)                    # Danach alle Beziehungen anlegen

driver.close()                                                  # Verbindung zur Datenbank sauber schließen

print(f"Fertig. {len(nodes)} Nodes und {len(edges)} Edges nach Neo4j geladen.") # Zusammenfassung für die Konsole ausgeben
PY
# Ende des Python-Blocks

echo "Neo4j-Import abgeschlossen." # Abschlussmeldung im Bash-Teil