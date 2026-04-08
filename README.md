# Oracle → Kafka → MongoDB CDC Pipeline

## Architecture

```
Oracle DB (monolith)
    │
    │  1 Debezium connector (all tables via LogMiner)
    ▼
Kafka  ── Raw CDC topics ──────────────────────────────────────────────────────
    oracle.APPUSER.EMPLOYEES       (raw, no join needed)
    oracle.APPUSER.PRODUCTS        (raw, no join needed)
    oracle.APPUSER.ORDERS          (needs enrichment)
    oracle.APPUSER.DEPARTMENTS     (lookup table for streams)
    oracle.APPUSER.CUSTOMERS       (lookup table for streams)
    │
    │  Kafka Streams apps (one per domain, only for tables needing joins)
    ▼
Kafka  ── Enriched topics ─────────────────────────────────────────────────────
    enriched.orders                (ORDERS + CUSTOMERS + PRODUCTS joined)
    enriched.employee-profiles     (EMPLOYEES + DEPARTMENTS joined)
    │
    │  MongoDB Sink connectors (one per collection)
    ▼
MongoDB
    poc.employees                  (from raw topic)
    poc.products                   (from raw topic)
    poc.orders                     (from enriched topic)
    poc.employeeProfiles           (from enriched topic)
```

## Topic Naming Convention

```
Raw CDC:      oracle.{SCHEMA}.{TABLE}        e.g. oracle.APPUSER.EMPLOYEES
Enriched:     enriched.{domain}              e.g. enriched.orders
```

## Repository Structure

```
connectors/
├── sources/
│   └── oracle-cdc-source.json      ← ONE file, add all tables here
└── sinks/
    ├── direct/                     ← tables that need NO join
    │   ├── sink-employees.json
    │   └── sink-products.json
    └── enriched/                   ← tables that go through a Streams app
        ├── sink-orders.json
        └── sink-hr-profiles.json

streams/
├── hr-domain/                      ← joins EMPLOYEES + DEPARTMENTS
└── orders-domain/                  ← joins ORDERS + CUSTOMERS + PRODUCTS

scripts/
├── register-all.sh                 ← registers everything
├── delete-all.sh                   ← deletes all connectors
└── status.sh                       ← shows connector health
```

---

## How to Add a New Table

### Case A — Table needs NO join (direct sync)

**Example:** adding `INVOICES` table

**Step 1** — Add table to source connector
```
connectors/sources/oracle-cdc-source.json
```
```json
"table.include.list": "APPUSER.EMPLOYEES, APPUSER.PRODUCTS, APPUSER.INVOICES"
```

**Step 2** — Create sink config
```
connectors/sinks/direct/sink-invoices.json
```
```json
{
  "name": "sink-invoices",
  "config": {
    "connector.class": "com.mongodb.kafka.connect.MongoSinkConnector",
    "topics": "oracle.APPUSER.INVOICES",
    "connection.uri": "mongodb://root:root@mongodb:27017",
    "database": "poc",
    "collection": "invoices",
    "key.converter": "org.apache.kafka.connect.json.JsonConverter",
    "key.converter.schemas.enable": "true",
    "value.converter": "org.apache.kafka.connect.json.JsonConverter",
    "value.converter.schemas.enable": "true",
    "change.data.capture.handler": "com.mongodb.kafka.connect.sink.cdc.debezium.rdbms.RdbmsHandler",
    "document.id.strategy": "com.mongodb.kafka.connect.sink.processor.id.strategy.PartialKeyStrategy",
    "document.id.strategy.partial.key.projection.list": "ID",
    "document.id.strategy.partial.key.projection.type": "AllowList"
  }
}
```

**Step 3** — Re-register connectors
```bash
sh scripts/register-all.sh
```

**That's it. 2 file changes.**

---

### Case B — Table needs a JOIN (enriched sync)

**Example:** adding `SHIPMENTS` that needs to be joined with `ADDRESSES`

**Step 1** — Add both tables to source connector
```json
"table.include.list": "..., APPUSER.SHIPMENTS, APPUSER.ADDRESSES"
```

**Step 2** — Create a new Kafka Streams domain app
```
streams/shipments-domain/
```
The app reads `oracle.APPUSER.SHIPMENTS` + `oracle.APPUSER.ADDRESSES`,
joins them, and writes to `enriched.shipments`.

Copy `streams/hr-domain/` as a template and modify the join logic.

**Step 3** — Add the streams app to docker-compose.yml
```yaml
shipments-domain:
  build: ./streams/shipments-domain
  depends_on: [kafka]
  environment:
    KAFKA_BOOTSTRAP: kafka:29092
```

**Step 4** — Create sink config
```
connectors/sinks/enriched/sink-shipments.json
```
```json
{
  "name": "sink-shipments",
  "config": {
    "topics": "enriched.shipments",
    "collection": "shipments",
    ...
  }
}
```

**Step 5** — Re-register connectors
```bash
sh scripts/register-all.sh
```

---

## Running Locally

```bash
# 1. Start all services
docker-compose up -d --build

# 2. Wait ~2 min for Oracle to initialize, then run CDC setup
docker cp oracle-init/02_cdc_setup.sh kafka-connector-oracle-1:/tmp/
docker exec -u oracle kafka-connector-oracle-1 bash /tmp/02_cdc_setup.sh

# 3. Register all connectors
sh scripts/register-all.sh

# 4. Check status
sh scripts/status.sh

# 5. Verify MongoDB
docker exec kafka-connector-mongodb-1 mongosh -u root -p root \
  --eval "db.getSiblingDB('poc').employees.find().pretty()"
```

## Useful Commands

```bash
# Register only sinks (after adding a new table)
sh scripts/register-all.sh --sinks-only

# Register only source (after adding a table to table.include.list)
sh scripts/register-all.sh --sources-only

# Delete all connectors
sh scripts/delete-all.sh

# Check connector health
sh scripts/status.sh

# Tail CDC events for a table
docker exec kafka-connector-kafka-1 kafka-console-consumer \
  --bootstrap-server localhost:9092 \
  --topic oracle.APPUSER.EMPLOYEES \
  --from-beginning
```

## Connector Config Reference

| Field | Description |
|---|---|
| `table.include.list` | Comma-separated `SCHEMA.TABLE` list in source connector |
| `topics` | Exact topic name for sink (raw or enriched) |
| `topics.regex` | Regex to match multiple topics in one sink |
| `change.data.capture.handler` | Use `RdbmsHandler` for raw Debezium topics |
| `document.id.strategy` | How MongoDB `_id` is set — use `PartialKeyStrategy` |
| `writemodel.strategy` | Use `ReplaceOneBusinessKeyStrategy` for upserts |

## Decision Guide: Direct vs Enriched

```
New table to sync?
       │
       ▼
Does it need data from other tables?
       │
   NO  │  YES
       │
       ▼    ▼
  direct/  enriched/
  sink     streams app + enriched sink
```
