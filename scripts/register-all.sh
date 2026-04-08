#!/bin/bash
# ─────────────────────────────────────────────────────────────
# register-all.sh
# Registers all source and sink connectors from the connectors/
# directory. Safe to re-run — deletes existing before re-creating.
#
# Usage:
#   sh scripts/register-all.sh
#   sh scripts/register-all.sh --sinks-only
#   sh scripts/register-all.sh --sources-only
# ─────────────────────────────────────────────────────────────

CONNECT_URL="http://localhost:8083"
CONNECTORS_DIR="$(dirname "$0")/../connectors"

# ── Wait for Kafka Connect ────────────────────────────────────
echo "Waiting for Kafka Connect at $CONNECT_URL ..."
until curl -sf "$CONNECT_URL/connectors" > /dev/null; do sleep 5; done
echo "Kafka Connect is up."
echo ""

register_file() {
  local file=$1
  local name
  name=$(python3 -c "import sys,json; print(json.load(open('$file'))['name'])" 2>/dev/null \
      || node -e "console.log(require('$file').name)" 2>/dev/null \
      || grep -o '"name"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -1 | sed 's/.*: *"\(.*\)"/\1/')

  echo "→ Registering: $name ($file)"

  # Delete if exists
  curl -s -X DELETE "$CONNECT_URL/connectors/$name" > /dev/null 2>&1
  sleep 1

  # Register
  result=$(curl -s -o /tmp/connect_response.json -w "%{http_code}" \
    -X POST "$CONNECT_URL/connectors" \
    -H "Content-Type: application/json" \
    --data-binary "@$file")

  if [ "$result" = "201" ] || [ "$result" = "200" ]; then
    echo "  ✓ Registered successfully"
  else
    echo "  ✗ Failed (HTTP $result)"
    cat /tmp/connect_response.json
  fi
  echo ""
}

MODE=${1:-"--all"}

# ── Sources ───────────────────────────────────────────────────
if [ "$MODE" = "--all" ] || [ "$MODE" = "--sources-only" ]; then
  echo "=== Registering SOURCE connectors ==="
  for f in "$CONNECTORS_DIR"/sources/*.json; do
    [ -f "$f" ] && register_file "$f"
  done
fi

# ── Sinks ─────────────────────────────────────────────────────
if [ "$MODE" = "--all" ] || [ "$MODE" = "--sinks-only" ]; then
  echo "=== Registering DIRECT SINK connectors ==="
  for f in "$CONNECTORS_DIR"/sinks/direct/*.json; do
    [ -f "$f" ] && register_file "$f"
  done

  echo "=== Registering ENRICHED SINK connectors ==="
  for f in "$CONNECTORS_DIR"/sinks/enriched/*.json; do
    [ -f "$f" ] && register_file "$f"
  done
fi

echo "=== Done. Current connectors: ==="
curl -s "$CONNECT_URL/connectors" | tr ',' '\n' | tr -d '[]"'
