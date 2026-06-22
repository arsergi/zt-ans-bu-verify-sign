#!/bin/sh
echo "Solving module called module-07" >> /tmp/progress.log

PAH_URL="https://localhost"
PAH_USER="admin"
PAH_PASS="ansible123!"

curl -sk -u ${PAH_USER}:${PAH_PASS} \
  -H "Content-Type: application/json" \
  -X POST ${PAH_URL}/api/galaxy/v3/collections/ansible/test_collection/versions/1.0.0/move/staging/published/

curl -sk -u ${PAH_USER}:${PAH_PASS} \
  -H "Content-Type: application/json" \
  -X POST ${PAH_URL}/api/galaxy/v3/collections/community/lab_collection/versions/1.0.0/move/staging/published/
