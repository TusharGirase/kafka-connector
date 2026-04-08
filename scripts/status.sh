#!/bin/bash
# Shows status of all registered connectors

CONNECT_URL="http://localhost:8083"

connectors=$(curl -s "$CONNECT_URL/connectors" | tr -d '[]"' | tr ',' '\n')

echo "╔══════════════════════════════════════════════════════════╗"
echo "║              CONNECTOR STATUS                           ║"
echo "╚══════════════════════════════════════════════════════════╝"

for name in $connectors; do
  [ -z "$name" ] && continue
  status=$(curl -s "$CONNECT_URL/connectors/$name/status")
  connector_state=$(echo "$status" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
  task_state=$(echo "$status" | grep -o '"state":"[^"]*"' | tail -1 | cut -d'"' -f4)

  if [ "$task_state" = "RUNNING" ]; then
    icon="✓"
  else
    icon="✗"
  fi

  printf "  %s  %-40s connector=%-10s task=%s\n" \
    "$icon" "$name" "$connector_state" "$task_state"
done

echo ""
