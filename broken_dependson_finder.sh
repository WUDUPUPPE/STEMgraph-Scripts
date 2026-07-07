for d in ./challenges/*/; do
  id=$(basename "$d")
  readme="$d/README.md"
  if [[ ! -f "$readme" ]]; then
    echo "FEHLT KOMPLETT: $id (kein README.md)"
    continue
  fi
  block=$(awk '/<!---/{flag=1;next} /--->/{flag=0} flag' "$readme")
  if [[ -z "$block" ]]; then
    echo "KEIN JSON-BLOCK: $id"
    continue
  fi
  echo "$block" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null \
    || echo "UNGÜLTIGES JSON: $id"
done