#!/bin/bash
# Deletes all currently registered connectors

CONNECT_URL="http://localhost:8083"

echo "Deleting all connectors..."
connectors=$(curl -s "$CONNECT_URL/connectors" | tr -d '[]"' | tr ',' '\n')

for name in $connectors; do
  [ -z "$name" ] && continue
  echo "→ Deleting: $name"
  curl -s -X DELETE "$CONNECT_URL/connectors/$name"
  echo ""
done

echo "Done."
