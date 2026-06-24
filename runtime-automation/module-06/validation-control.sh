#!/bin/sh
echo "Validated module called module-06" >> /tmp/progress.log

PAH_URL="https://localhost"
PAH_USER="admin"
PAH_PASS="ansible123!"

RESPONSE=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/_ui/v1/collection-versions/)
COLLECTIONS=$(echo "$RESPONSE" | jq -r '.data[].namespace // empty')
if [ -z "$COLLECTIONS" ]; then
    COLLECTIONS=$(echo "$RESPONSE" | jq -r '.results[].namespace // empty')
fi

if ! echo "$COLLECTIONS" | grep -q "ansible"; then
    fail-message "ansible.test_collection was not published to Private Automation Hub"
fi

if ! echo "$COLLECTIONS" | grep -q "community"; then
    fail-message "community.lab_collection was not published to Private Automation Hub"
fi
