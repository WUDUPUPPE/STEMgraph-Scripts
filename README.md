# STEMgraph-Scripts

Bash-Scripts zur Datenbeschaffung und Verarbeitung für das **STEMgraph**-Projekt.  
Sie holen Challenge-Repos aus GitHub, lesen deren Metadaten aus und bauen daraus eine `graph-data.json` für das Frontend.

---

## Übersicht

| Script | Aufgabe |
|---|---|
| `get_all_challenges.sh` | Klont alle Challenge-Repos in `./challenges/` |
| `get_rekursiv_challenges.sh` | Holt Challenges rekursiv anhand von `depends_on`-Ketten |
| `get_subgraph_challenges.sh` | Holt einen Teilgraphen (Subgraph) ab einem Startknoten |
| `graph-data_subgraph.sh` | Baut anhand des `graph-data.json` einen bestimmten Subgraphen |
| `export_graph_data.sh` | Baut die vollständige `graph-data.json` aus allen lokalen Challenges |

---

## Voraussetzungen

- **Bash** (≥ 4.x)
- **Python 3** (für `export_graph_data.sh` und `graph-data_subgraph.sh`)
- **Git** (zum Klonen der Challenge-Repos)
- **curl** / **jq** (für GitHub-API-Abfragen, je nach Script)

---

## Schnellstart

```bash
# 1. Alle Challenge-Repos lokal klonen
bash get_all_challenges.sh

# 2. graph-data.json für das Frontend bauen
bash export_graph_data.sh
```

Die fertige `graph-data.json` liegt danach unter `./graph-data.json` und kann direkt vom STEMgraph-Frontend genutzt werden.

---

## Wie funktioniert das Metadaten-Format?

Jedes Challenge-Repo enthält eine `README.md` mit einem versteckten JSON-Block:

```markdown
<!---
{
  "id": "challenge-id",
  "teaches": "Was diese Challenge lehrt",
  "keywords": ["Stichwort1", "Stichwort2"],
  "depends_on": ["andere-challenge-id"]
}
--->
```

`export_graph_data.sh` liest diesen Block aus allen geklonten Repos und baut daraus Nodes und Edges für den Graphen.

---

## graph-data.json – Struktur

```json
{
  "nodes": [
    { "id": "challenge-id", "teaches": "...", "keywords": ["..."], "depends_on": ["..."] }
  ],
  "edges": [
    { "source": "voraussetzung-id", "target": "challenge-id" }
  ]
}
```

---

## Scripts im Detail

### `get_all_challenges.sh`
Klont alle Challenge-Repos aus der GitHub-Organisation in den lokalen `./challenges/`-Ordner.

### `get_rekursiv_challenges.sh`
Startet bei einer Challenge und folgt rekursiv allen `depends_on`-Abhängigkeiten – nützlich, um den kompletten Lernpfad einer Challenge zu laden.

### `get_subgraph_challenges.sh`
Holt einen Teilgraphen ab einem definierten Startknoten, ohne den gesamten Graphen zu laden.

### `graph-data_subgraph.sh`
Wie `export_graph_data.sh`, aber beschränkt auf einen Subgraphen – erzeugt eine kleinere `graph-data.json` für das Frontend.

### `export_graph_data.sh`
Liest alle lokalen Challenge-Repos unter `./challenges/`, extrahiert die JSON-Metadaten aus den READMEs und schreibt die vollständige `graph-data.json`.

---

## Projektkontext

Diese Scripts sind Teil des **STEMgraph**-Praktikumsprojekts.  
STEMgraph visualisiert Lernpfade für STEM-Challenges als interaktiven Graphen.  
Das Frontend liest die `graph-data.json` und stellt Nodes (Challenges) und Edges (Abhängigkeiten) als Graphen dar.

---

## Lizenz

Dieses Repository ist Teil eines Ausbildungsprojekts (Fachinformatiker Anwendungsentwicklung).