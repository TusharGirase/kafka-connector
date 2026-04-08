#!/bin/bash
echo "=== Inserting rows into Oracle ==="
docker exec kafka-connector-oracle-1 bash -c "sqlplus -s appuser/appuser@//localhost:1521/XEPDB1 <<'EOF'
INSERT INTO EMPLOYEES (NAME, DEPT, SALARY) VALUES ('Dave',  'Finance',     80000);
INSERT INTO EMPLOYEES (NAME, DEPT, SALARY) VALUES ('Eve',   'HR',          70000);
COMMIT;
EXIT;
EOF"

echo ""
echo "=== Updating Alice salary to 99000 ==="
docker exec kafka-connector-oracle-1 bash -c "sqlplus -s appuser/appuser@//localhost:1521/XEPDB1 <<'EOF'
UPDATE EMPLOYEES SET SALARY=99000 WHERE NAME='Alice';
COMMIT;
EXIT;
EOF"

echo ""
echo "=== Deleting Bob ==="
docker exec kafka-connector-oracle-1 bash -c "sqlplus -s appuser/appuser@//localhost:1521/XEPDB1 <<'EOF'
DELETE FROM EMPLOYEES WHERE NAME='Bob';
COMMIT;
EXIT;
EOF"

echo ""
echo "=== Waiting 15s for CDC sync... ==="
sleep 15

echo ""
echo "=== MongoDB poc.employees (should show Dave+Eve inserted, Alice updated, Bob deleted) ==="
docker exec kafka-connector-mongodb-1 mongosh -u root -p root --quiet \
  --eval "db.getSiblingDB('poc').employees.find({},{_id:0}).toArray()" 2>/dev/null
