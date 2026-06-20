#!/usr/bin/env bash
# fetch_subgraph_challenges.sh
# Baut aus den lokalen Challenges einen Abhängigkeits‑Graphen
# und berechnet einen Pfad von einer Start‑Challenge zu einer Ziel‑Challenge.

set -euo pipefail                               #Script bei Fehlern/ungesetzten Variablen sauber beenden

BASE_DIR="./challenges"                         #Hier liegen die von den anderen Scripts geklonten Repos

# Kurze Usage‑Ausgabe, falls Argumente fehlen
if [[ $# -ne 2 ]]; then                         #Wenn die Anzahl der Argumente nicht gleich 2 ist, dann
  echo "Usage: $0 <start-challenge-id> <ziel-challenge-id>" #Gibt die richtige Verwendung des Skripts aus, wenn die Anzahl der Argumente falsch ist
  echo "Beispiel:"                              #Gibt ein Beispiel für die Verwendung des Skripts aus, damit ich sehe wie es funktioniert
  echo "  $0 c1f2cd2b-3ffc-44a8-86b1-111f9d246c10 2d1d315d-bb92-48c0-b19f-19529a45e5ff" #Gibt ein Beispiel für die Verwendung des Skripts aus, damit ich sehe wie es funktioniert
  exit 1                                        #Verlässt das Skript mit einem Fehlercode, wenn die Anzahl der Argumente falsch ist
fi                                              #Wenn die Anzahl der Argumente korrekt ist, wird das Skript fortgesetzt

START_ID="$1"                                   #Challenge, bei der der Pfad beginnen soll
TARGET_ID="$2"                                  #Challenge, bei der der Pfad enden soll

# Prüfen, ob der Basis‑Ordner existiert
if [[ ! -d "$BASE_DIR" ]]; then                 #Wenn es ./challenges nicht gibt
  echo "FEHLER: Basisverzeichnis '$BASE_DIR' wurde nicht gefunden." #Gibt eine Fehlermeldung aus, wenn der Basisordner nicht gefunden wurde
  echo "Bitte vorher 'fetch_all_challenges.sh' ausführen, damit die Repos lokal liegen." #Gibt eine Anweisung aus, was zu tun ist, damit die Repos lokal liegen
  exit 1                                        #Verlässt das Skript mit einem Fehlercode, wenn der Basisordner nicht gefunden wurde
fi                                              #Wenn der Basisordner existiert, wird das Skript fortgesetzt

# Hauptlogik in Python, damit Graph‑Aufbau und Pfadsuche übersichtlich bleiben
python3 - << 'PY'                               #Python‑Teil beginnt hier, alles bis zum PY am Ende ist Python‑Code
import os                                       #os brauche ich für Pfade und Verzeichnisdurchläufe     
import sys                                      #sys brauche ich für die Übergabe der Argumente und das Beenden mit Fehlercodes
import json                                     #json brauche ich zum Einlesen der Metadaten aus den README‑Dateien

BASE_DIR = os.path.abspath(os.environ.get("BASE_DIR", "./challenges")) # Basisverzeichnis für die lokalen Challenge‑Repos
start_id = os.environ.get("START_ID")           #Start‑Challenge‑ID aus der Umgebung holen
target_id = os.environ.get("TARGET_ID")         #Ziel‑Challenge‑ID aus der Umgebung holen

if not start_id or not target_id:               #Wenn Start‑ID oder Ziel‑ID nicht gesetzt ist, dann
    print("FEHLER: START_ID oder TARGET_ID nicht gesetzt.") #Gibt eine Fehlermeldung aus, wenn die Start‑ID oder Ziel‑ID nicht gesetzt ist
    sys.exit(1)                                 #Verlässt das Skript mit einem Fehlercode, wenn die Start‑ID oder Ziel‑ID nicht gesetzt ist

# Hilfsfunktion: JSON‑Block zwischen <!--- und ---> aus einem README holen
def extract_meta_json(readme_path: str):        #Funktion bekommt den Pfad zur README
    if not os.path.isfile(readme_path):         #Wenn die Datei nicht existiert
        return None                             #Gibt None zurück, wenn die README nicht gefunden wurde
    lines = []                                  #Liste für die Zeilen im JSON‑Block
    in_block = False                            #Flag, ob ich gerade innerhalb des Kommentarblocks bin
    with open(readme_path, "r", encoding="utf-8", errors="ignore") as f: #README öffnen, Encoding robust halten
        for line in f:                          #Zeile für Zeile durchgehen
            if "<!---" in line:                 #Start‑Marker für den JSON‑Kommentar
                in_block = True                 #Flag setzen, dass jetzt der Block beginnt
                continue                        #Diese Zeile selbst nicht inhaltlich mitnehmen, da sie den Marker enthält
            if "--->" in line and in_block:     #End‑Marker für den JSON‑Kommentar
                in_block = False                #Danach interessiert mich der Rest der Datei hier nicht mehr
                break                           #Block ist zu Ende, Schleife verlassen
            if in_block:                        #Nur wenn ich im Block bin, Zeile sammeln
                lines.append(line)              #Zeile sammeln, wenn ich mich innerhalb des JSON‑Kommentarblocks befinde
    if not lines:                               #Wenn keine Zeilen gefunden wurden, dann
        return None                             #Gibt None zurück, wenn kein JSON‑Kommentar gefunden wurde   
    raw = "".join(lines).strip().               #Alle Zeilen zusammenfügen und Leerraum wegtrimmen
    if not raw:                                 #Wenn der Block leer ist, dann
        return None                             #Gibt None zurück, wenn der JSON‑Kommentar leer ist
    try:                                        #JSON‑Parsing versuchen
        return json.loads(raw)                  #Wenn das klappt, gebe ich das Dictionary zurück
    except Exception:                           #Falls das JSON kaputt ist, dann
        return None                             #Gibt None zurück, wenn der JSON‑Kommentar nicht geparst werden konnte

# Graph als Adjazenzliste: id -> Liste von depends_on‑IDs
graph = {}                                      #Graph‑Datenstruktur, die ich aufbaue, um die Abhängigkeiten zu speichern
# Optional: Metadaten für spätere Verwendung (z.B. teaches, keywords) #id -> Dict mit Metadaten
meta_by_id = {}                                 #Metadaten‑Datenstruktur, um zusätzliche Informationen zu speichern, die ich später für die Ausgabe verwenden könnte

# Alle Unterordner in BASE_DIR durchgehen und README.md auswerten
for entry in os.listdir(BASE_DIR):              #Jedes Element im challenges‑Ordner anschauen
    repo_dir = os.path.join(BASE_DIR, entry)    #Absoluten Pfad zum Repo‑Verzeichnis bauen, um später die README zu finden
    if not os.path.isdir(repo_dir):             #Nur Verzeichnisse interessieren mich, Dateien überspringen
        continue                                #Wenn es kein Verzeichnis ist, überspringe ich es
    readme_path = os.path.join(repo_dir, "README.md") #Pfad zur README in diesem Repo, um die Metadaten zu extrahieren
    meta = extract_meta_json(readme_path)       #JSON‑Metadaten aus der README holen, um die Abhängigkeiten zu extrahieren
    if not meta:                                #Wenn keine Metadaten gefunden wurden, dann
        continue                                #Dieses Repo überspringen, da ich keine Informationen daraus ziehen kann

    cid = meta.get("id", entry)                 #Challenge‑ID aus den Metadaten holen, falls nicht vorhanden nehme ich den Ordnernamen als Fallback
    depends = meta.get("depends_on", []) or []  #depends_on‑Liste aus den Metadaten holen, falls nicht vorhanden gebe ich eine leere Liste zurück
    if not isinstance(depends, list):           #Falls jemand depends_on aus Versehen nicht als Liste geschrieben hat, dann
        depends = []                            #Setze ich depends auf eine leere Liste, um Fehler zu vermeiden

    # Knoten im Graphen anlegen
    graph.setdefault(cid, [])                   #Stelle sicher, dass es einen Eintrag für diese Challenge‑ID im Graph gibt, auch wenn sie keine Dependencies hat
    # Kanten aus depends_on eintragen           
    for dep in depends:                         #Schleife über die Einträge in depends_on, um die Kanten im Graphen zu bauen
        if isinstance(dep, str) and dep:        #Nur gültige, nicht‑leere Strings als IDs akzeptieren, um Fehler zu vermeiden
            graph[cid].append(dep).             #Füge die Dependency‑ID als Nachbarn im Graphen hinzu, damit ich später die Pfadsuche durchführen kann

    # Metadaten merken (für spätere Ausgaben, falls gewünscht)
    meta_by_id[cid] = {                         #Metadaten für diese Challenge‑ID speichern, damit ich später z.B. teaches oder keywords ausgeben kann
        "teaches": meta.get("teaches", ""),     #teaches‑Titel aus den Metadaten holen, falls nicht vorhanden gebe ich einen leeren String zurück
        "keywords": meta.get("keywords", []),   #keywords‑Liste aus den Metadaten holen, falls nicht vorhanden gebe ich eine leere Liste zurück
    }

# Prüfen, ob Start/Ziel überhaupt im Graph vorkommen
if start_id not in graph and all(start_id not in deps for deps in graph.values()): #Wenn die Start‑ID weder als Knoten im Graph noch als Dependency in irgendeinem Knoten vorkommt, dann
    print(f"FEHLER: Start‑ID '{start_id}' kommt in den lokalen Challenges nicht vor.") #Gibt eine Fehlermeldung aus, wenn die Start‑ID nicht im Graph vorkommt
    sys.exit(1)                                 #Verlässt das Skript mit einem Fehlercode, wenn die Start‑ID nicht im Graph vorkommt

if target_id not in graph and all(target_id not in deps for deps in graph.values()): #Wenn die Ziel‑ID weder als Knoten im Graph noch als Dependency in irgendeinem Knoten vorkommt, dann
    print(f"FEHLER: Ziel‑ID '{target_id}' kommt in den lokalen Challenges nicht vor.") #Gibt eine Fehlermeldung aus, wenn die Ziel‑ID nicht im Graph vorkommt
    sys.exit(1)                                 #Verlässt das Skript mit einem Fehlercode, wenn die Ziel‑ID nicht im Graph vorkommt

# BFS für einen Pfad von start_id nach target_id
from collections import deque                   #Importiere deque für die Implementierung der Warteschlange in der BFS

queue = deque()                                 #Warteschlange für die BFS, um die Knoten zu besuchen
visited = set()                                 #Set, um die besuchten Knoten zu tracken und Zyklen zu vermeiden
prev = {}                                       #Vorgänger‑Map: node -> Vorgänger im Pfad 

queue.append(start_id)                          #Start‑ID in die Warteschlange einfügen, um die Suche zu starten
visited.add(start_id)                           #Start‑ID als besucht markieren, damit ich sie nicht nochmal besuche

found = False                                   #Flag, um zu merken, ob ich das Ziel gefunden habe, damit ich die Pfadrecherche später steuern kann

while queue:                                    #Solange die Warteschlange nicht leer ist, weiter suchen
    current = queue.popleft()                   #Nächsten Knoten aus der Warteschlange nehmen, um ihn zu besuchen
    if current == target_id:                    #Ziel gefunden, Suche beenden
        found = True                            #Ziel gefunden, Flag setzen, um später die Pfadrecherche zu steuern
        break                                   #Ziel gefunden, Schleife verlassen

    # Nachbarn: alle Kanten current -> dep
    neighbors = graph.get(current, [])          #Nachbarn des aktuellen Knotens aus dem Graphen holen, falls es keine gibt, gebe ich eine leere Liste zurück
    for dep in neighbors:                       #Über alle Nachbarn iterieren, um sie zu besuchen   
        if dep not in visited:                  #Wenn der Nachbar noch nicht besucht wurde, dann
            visited.add(dep)                    #Nachbar als besucht markieren, damit ich ihn nicht nochmal besuche
            prev[dep] = current                 #Vorgänger‑Map aktualisieren, damit ich später den Pfad rekonstruieren kann
            queue.append(dep)                   #Nachbar in die Warteschlange einfügen, damit er später besucht wird

if not found:                                   #Wenn die Suche beendet ist, aber das Ziel nicht gefunden wurde, dann
    print(f"Kein Pfad von '{start_id}' nach '{target_id}' gefunden.") #Gibt eine Meldung aus, wenn kein Pfad von der Start‑ID zur Ziel‑ID gefunden wurde
    sys.exit(0)                                 #Verlässt das Skript mit einem Erfolgscode, da es technisch gesehen kein Fehler ist, wenn kein Pfad gefunden wird

# Pfad rekonstrieren    
path = []                                       #Liste für die Rekonstruktion des Pfads von der Ziel‑ID zurück zur Start‑ID
node = target_id                                #Startpunkt für die Pfadrecherche ist die Ziel‑ID, von der ich zurück zur Start‑ID gehen möchte
while True:                                     #Solange ich nicht am Startpunkt angekommen bin, weiter zurückgehen
    path.append(node)                           #Aktuellen Knoten zum Pfad hinzufügen, damit ich am Ende den kompletten Pfad habe
    if node == start_id:                        #Wenn ich den Startpunkt erreicht habe, ist die Pfadrecherche abgeschlossen
        break                                   #Pfadrecherche abgeschlossen, Schleife verlassen
    node = prev.get(node)                       #Nächsten Knoten in der Vorgänger‑Map nachschlagen, um weiter zurückzugehen
    if node is None:                            #Wenn es keinen Vorgänger gibt, obwohl ich noch nicht am Startpunkt bin, dann ist das ein Fehler in der Pfadrecherche, da ich eigentlich immer einen Vorgänger haben sollte, bis ich den Startpunkt erreiche
        # Sollte eigentlich nicht passieren, wenn found == True 
        print("Interner Fehler bei der Pfadreonstruktion.") #Gibt eine Fehlermeldung aus, wenn es einen Fehler bei der Pfadrecherche gibt, z.B. wenn ich keinen Vorgänger finde, obwohl ich noch nicht am Startpunkt bin
        sys.exit(1)                             #Verlässt das Skript mit einem Fehlercode, wenn es einen Fehler bei der Pfadrecherche gibt

path.reverse()                                  

# Ausgabe
print()                                         
print(f"Pfad von {start_id} nach {target_id}:") 
print("----------------------------------------")
for idx, cid in enumerate(path):                
    marker = "START" if cid == start_id else ("ZIEL" if cid == target_id else f"Step {idx}")
    teaches = meta_by_id.get(cid, {}).get("teaches", "")
    line = f"{marker}: {cid}"
    if teaches:
        line += f"  |  {teaches}"
    print(line)

print()
print("Lokale Repo-Pfade zu diesem Pfad:")
print("----------------------------------------")
for cid in path:
    repo_path = os.path.join(BASE_DIR, cid)
    print(f"- {repo_path}")
PY
