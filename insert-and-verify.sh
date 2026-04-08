#!/bin/bash

echo "=== Inserting rows into Oracle EMPLOYEES ==="

docker exec kafka-connector-oracle-1 bash -c "sqlplus -s appuser/appuser@//localhost:1521/XEPDB1 <<'EOF'
INSERT INTO EMPLOYEES (NAME, DEPT, SALARY) VALUES ('Dave',  'Finance',     80000);
INSERT INTO EMPLOYEES (NAME, DEPT, SALARY) VALUES ('Eve',   'HR',          70000);
INSERT INTO EMPLOYEES (NAME, DEPT, SALARY) VALUES ('Frank', 'Engineering', 92000);
COMMIT;
EXIT;
EOF"

echo ""
echo "=== Rows inserted. Waiting 10s for Kafka sync... ==="
sleep 10

echo ""
echo "=== MongoDB poc.employees ==="
docker exec kafka-connector-mongodb-1 mongosh -u root -p root --quiet \
  --eval "db.getSiblingDB('poc').employees.find({}, {_id:0}).toArray()" 2>/dev/null
