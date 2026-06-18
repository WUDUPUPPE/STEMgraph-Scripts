#!/usr/bin/env bash
# fetch_subgraph_challenges.sh
# Baut aus den lokalen Challenges einen Abhängigkeits‑Graphen
# und berechnet einen Pfad von einer Start‑Challenge zu einer Ziel‑Challenge.

set -euo pipefail  # Script bei Fehlern/ungesetzten Variablen sauber beenden

BASE_DIR="./challenges"   # Hier liegen die von den anderen Scripts geklonten Repos

# Kurze Usage‑Ausgabe, falls Argumente fehlen
if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <start-challenge-id> <ziel-challenge-id>"
  echo "Beispiel:"
  echo "  $0 c1f2cd2b-3ffc-44a8-86b1-111f9d246c10 2d1d315d-bb92-48c0-b19f-19529a45e5ff"
  exit 1
fi

START_ID="$1"  # Challenge, bei der der Pfad beginnen soll
TARGET_ID="$2" # Challenge, bei der der Pfad enden soll

# Prüfen, ob der Basis‑Ordner existiert
if [[ ! -d "$BASE_DIR" ]]; then
  echo "FEHLER: Basisverzeichnis '$BASE_DIR' wurde nicht gefunden."
  echo "Bitte vorher 'fetch_all_challenges.sh' ausführen, damit die Repos lokal liegen."
  exit 1
fi

# Hauptlogik in Python, damit Graph‑Aufbau und Pfadsuche übersichtlich bleiben
python3 - << 'PY'
import os
import sys
import json

BASE_DIR = os.path.abspath(os.environ.get("BASE_DIR", "./challenges"))
start_id = os.environ.get("START_ID")
target_id = os.environ.get("TARGET_ID")

if not start_id or not target_id:
    print("FEHLER: START_ID oder TARGET_ID nicht gesetzt.")
    sys.exit(1)

# Hilfsfunktion: JSON‑Block zwischen <!--- und ---> aus einem README holen
def extract_meta_json(readme_path: str):
    if not os.path.isfile(readme_path):
        return None
    lines = []
    in_block = False
    with open(readme_path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            if "<!---" in line:
                in_block = True
                continue
            if "--->" in line and in_block:
                in_block = False
                break
            if in_block:
                lines.append(line)
    if not lines:
        return None
    raw = "".join(lines).strip()
    if not raw:
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None

# Graph als Adjazenzliste: id -> Liste von depends_on‑IDs
graph = {}
# Optional: Metadaten für spätere Verwendung (z.B. teaches, keywords)
meta_by_id = {}

# Alle Unterordner in BASE_DIR durchgehen und README.md auswerten
for entry in os.listdir(BASE_DIR):
    repo_dir = os.path.join(BASE_DIR, entry)
    if not os.path.isdir(repo_dir):
        continue
    readme_path = os.path.join(repo_dir, "README.md")
    meta = extract_meta_json(readme_path)
    if not meta:
        continue

    cid = meta.get("id", entry)
    depends = meta.get("depends_on", []) or []
    if not isinstance(depends, list):
        depends = []

    # Knoten im Graphen anlegen
    graph.setdefault(cid, [])
    # Kanten aus depends_on eintragen
    for dep in depends:
        if isinstance(dep, str) and dep:
            graph[cid].append(dep)

    # Metadaten merken (für spätere Ausgaben, falls gewünscht)
    meta_by_id[cid] = {
        "teaches": meta.get("teaches", ""),
        "keywords": meta.get("keywords", []),
    }

# Prüfen, ob Start/Ziel überhaupt im Graph vorkommen
if start_id not in graph and all(start_id not in deps for deps in graph.values()):
    print(f"FEHLER: Start‑ID '{start_id}' kommt in den lokalen Challenges nicht vor.")
    sys.exit(1)

if target_id not in graph and all(target_id not in deps for deps in graph.values()):
    print(f"FEHLER: Ziel‑ID '{target_id}' kommt in den lokalen Challenges nicht vor.")
    sys.exit(1)

# BFS für einen Pfad von start_id nach target_id
from collections import deque

queue = deque()
visited = set()
prev = {}  # Vorgänger‑Map: node -> Vorgänger im Pfad

queue.append(start_id)
visited.add(start_id)

found = False

while queue:
    current = queue.popleft()
    if current == target_id:
        found = True
        break

    # Nachbarn: alle Kanten current -> dep
    neighbors = graph.get(current, [])
    for dep in neighbors:
        if dep not in visited:
            visited.add(dep)
            prev[dep] = current
            queue.append(dep)

if not found:
    print(f"Kein Pfad von '{start_id}' nach '{target_id}' gefunden.")
    sys.exit(0)

# Pfad rekonstrieren
path = []
node = target_id
while True:
    path.append(node)
    if node == start_id:
        break
    node = prev.get(node)
    if node is None:
        # Sollte eigentlich nicht passieren, wenn found == True
        print("Interner Fehler bei der Pfadreonstruktion.")
        sys.exit(1)

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
