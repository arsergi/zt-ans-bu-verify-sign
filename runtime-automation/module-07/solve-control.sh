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

# Explicitly sign all content in the published repository via Pulp API
SS_HREF=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/?name=ansible-default | jq -r '.results[0].pulp_href')

REPO_HREF=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/pulp/api/v3/repositories/ansible/ansible/?name=published | jq -r '.results[0].pulp_href')

if [ -n "$SS_HREF" ] && [ "$SS_HREF" != "null" ] && [ -n "$REPO_HREF" ] && [ "$REPO_HREF" != "null" ]; then
  TASK_HREF=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
    -H "Content-Type: application/json" \
    -X POST ${PAH_URL}${REPO_HREF}sign/ \
    -d "{\"signing_service\": \"${SS_HREF}\", \"content_units\": [\"*\"]}" | jq -r '.task')

  if [ -n "$TASK_HREF" ] && [ "$TASK_HREF" != "null" ]; then
    for i in $(seq 1 30); do
      STATE=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
        ${PAH_URL}${TASK_HREF} | jq -r '.state')
      if [ "$STATE" = "completed" ]; then
        echo "Signing task completed" >> /tmp/progress.log
        break
      elif [ "$STATE" = "failed" ]; then
        echo "Signing task failed" >> /tmp/progress.log
        break
      fi
      sleep 2
    done
  fi
fi

echo "Module 07 solve complete" >> /tmp/progress.log
