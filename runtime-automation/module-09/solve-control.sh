#!/bin/bash
LOG="/tmp/solve-module-09.log"
echo "=== Module 09 solve started: $(date) ===" > $LOG

AAP_URL="https://localhost"
AAP_USER="admin"
AAP_PASS="ansible123!"
CURL_OPTS="-sk --connect-timeout 10 --max-time 30"

# --- Step 1: Look up Default org ---
echo "[1/8] Looking up Default organization..." >> $LOG
ORG_ID=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/organizations/?name=Default" \
  | jq -r '.results[0].id')
echo "  org ID: ${ORG_ID}" >> $LOG

if [ "$ORG_ID" = "null" ] || [ -z "$ORG_ID" ]; then
  echo "  ERROR: Could not find Default organization" >> $LOG
  echo "=== Module 09 solve FAILED: $(date) ===" >> $LOG
  exit 1
fi

# --- Step 2: Look up Galaxy credential type and create credential ---
echo "[2/8] Creating Galaxy credential..." >> $LOG

echo "  Looking up Galaxy credential type (kind=galaxy)..." >> $LOG
GALAXY_CRED_TYPE_ID=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/credential_types/?kind=galaxy" \
  | jq -r '.results[0].id')
echo "  Galaxy credential type ID: ${GALAXY_CRED_TYPE_ID}" >> $LOG

if [ "$GALAXY_CRED_TYPE_ID" = "null" ] || [ -z "$GALAXY_CRED_TYPE_ID" ]; then
  echo "  ERROR: Could not find Galaxy credential type" >> $LOG
  echo "=== Module 09 solve FAILED: $(date) ===" >> $LOG
  exit 1
fi

EXISTING_CRED_ID=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/credentials/?name=Automation+Hub" \
  | jq -r '.results[0].id // empty')

if [ -n "$EXISTING_CRED_ID" ] && [ "$EXISTING_CRED_ID" != "null" ]; then
  echo "  Galaxy credential already exists (ID: ${EXISTING_CRED_ID}), skipping creation" >> $LOG
  CRED_ID=$EXISTING_CRED_ID
else
  TOKEN=$(grep '^token=' /home/rhel/ansible.cfg | head -1 | cut -d= -f2)
  if [ -z "$TOKEN" ]; then
    echo "  Token not found in ansible.cfg, generating new one..." >> $LOG
    TOKEN=$(curl -sk -u ${AAP_USER}:${AAP_PASS} \
      -X POST ${AAP_URL}/api/galaxy/v3/auth/token/ | jq -r '.token // empty')
  fi
  echo "  API token: ${TOKEN:0:8}..." >> $LOG

  CRED_PAYLOAD=$(jq -n \
    --arg name "Automation Hub" \
    --argjson cred_type "$GALAXY_CRED_TYPE_ID" \
    --argjson org "$ORG_ID" \
    --arg url "https://host.containers.internal/api/galaxy/content/published/" \
    --arg token "$TOKEN" \
    '{
      name: $name,
      credential_type: $cred_type,
      organization: $org,
      inputs: { url: $url, token: $token }
    }')

  echo "  POSTing Galaxy credential..." >> $LOG
  CRED_RESPONSE=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
    -H "Content-Type: application/json" \
    -X POST "${AAP_URL}/api/controller/v2/credentials/" \
    -d "$CRED_PAYLOAD")
  echo "  credential response: $CRED_RESPONSE" >> $LOG

  CRED_ID=$(echo "$CRED_RESPONSE" | jq -r '.id')
  echo "  credential ID: ${CRED_ID}" >> $LOG

  if [ "$CRED_ID" = "null" ] || [ -z "$CRED_ID" ]; then
    echo "  ERROR: Failed to create Galaxy credential" >> $LOG
    echo "=== Module 09 solve FAILED: $(date) ===" >> $LOG
    exit 1
  fi
fi

# --- Step 3: Associate Galaxy credential with Default org ---
echo "[3/8] Associating credential with Default organization..." >> $LOG
ASSOC_RESPONSE=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  -H "Content-Type: application/json" \
  -X POST "${AAP_URL}/api/controller/v2/organizations/${ORG_ID}/galaxy_credentials/" \
  -d "{\"id\": ${CRED_ID}}")
echo "  association response: $ASSOC_RESPONSE" >> $LOG
echo "  completed: $(date)" >> $LOG

# --- Step 4: Sync the Signed Project ---
echo "[4/8] Syncing Signed Project..." >> $LOG

PROJECT_ID=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/projects/?name=Signed+Project" \
  | jq -r '.results[0].id')
echo "  project ID: ${PROJECT_ID}" >> $LOG

if [ "$PROJECT_ID" = "null" ] || [ -z "$PROJECT_ID" ]; then
  echo "  ERROR: Could not find 'Signed Project'" >> $LOG
  echo "=== Module 09 solve FAILED: $(date) ===" >> $LOG
  exit 1
fi

curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  -X POST "${AAP_URL}/api/controller/v2/projects/${PROJECT_ID}/update/" >> $LOG 2>&1

# Brief pause so Controller registers the new sync job before we poll
sleep 5

echo "  Waiting for project sync..." >> $LOG
for i in $(seq 1 60); do
  STATUS=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
    "${AAP_URL}/api/controller/v2/projects/${PROJECT_ID}/" \
    | jq -r '.status')
  if [ "$STATUS" = "successful" ]; then
    echo "  project sync successful (attempt $i)" >> $LOG
    break
  fi
  if [ "$STATUS" = "failed" ] || [ "$STATUS" = "error" ]; then
    echo "  ERROR: Project sync failed (status: $STATUS)" >> $LOG
    break
  fi
  sleep 5
done
echo "  completed: $(date)" >> $LOG

# --- Step 5: Create inventory ---
echo "[5/8] Creating inventory..." >> $LOG

EXISTING_INV_ID=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/inventories/?name=Module+09+Inventory" \
  | jq -r '.results[0].id // empty')

if [ -n "$EXISTING_INV_ID" ] && [ "$EXISTING_INV_ID" != "null" ]; then
  echo "  Inventory already exists (ID: ${EXISTING_INV_ID}), skipping creation" >> $LOG
  INVENTORY_ID=$EXISTING_INV_ID
else
  INV_PAYLOAD=$(jq -n \
    --arg name "Module 09 Inventory" \
    --argjson org "$ORG_ID" \
    '{
      name: $name,
      organization: $org
    }')

  INV_RESPONSE=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
    -H "Content-Type: application/json" \
    -X POST "${AAP_URL}/api/controller/v2/inventories/" \
    -d "$INV_PAYLOAD")
  echo "  inventory response: $INV_RESPONSE" >> $LOG

  INVENTORY_ID=$(echo "$INV_RESPONSE" | jq -r '.id')
  echo "  inventory ID: ${INVENTORY_ID}" >> $LOG

  # --- Step 6: Add localhost to inventory ---
  echo "[6/8] Adding localhost to inventory..." >> $LOG

  HOST_RESPONSE=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
    -H "Content-Type: application/json" \
    -X POST "${AAP_URL}/api/controller/v2/hosts/" \
    -d "{\"name\": \"localhost\", \"inventory\": ${INVENTORY_ID}}")
  echo "  host response: $HOST_RESPONSE" >> $LOG
  echo "  completed: $(date)" >> $LOG
fi

# --- Step 7: Create job template ---
echo "[7/8] Creating job template..." >> $LOG

EXISTING_JT_ID=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/job_templates/?name=Signed+Collection+Demo" \
  | jq -r '.results[0].id // empty')

if [ -n "$EXISTING_JT_ID" ] && [ "$EXISTING_JT_ID" != "null" ]; then
  echo "  Job template already exists (ID: ${EXISTING_JT_ID}), skipping creation" >> $LOG
  JT_ID=$EXISTING_JT_ID
else
  JT_PAYLOAD=$(jq -n \
    --arg name "Signed Collection Demo" \
    --argjson project "$PROJECT_ID" \
    --argjson inventory "$INVENTORY_ID" \
    --arg playbook "playbooks/use_signed_collection.yml" \
    '{
      name: $name,
      project: $project,
      inventory: $inventory,
      playbook: $playbook
    }')

  JT_RESPONSE=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
    -H "Content-Type: application/json" \
    -X POST "${AAP_URL}/api/controller/v2/job_templates/" \
    -d "$JT_PAYLOAD")
  echo "  job template response: $JT_RESPONSE" >> $LOG

  JT_ID=$(echo "$JT_RESPONSE" | jq -r '.id')
  echo "  job template ID: ${JT_ID}" >> $LOG

  if [ "$JT_ID" = "null" ] || [ -z "$JT_ID" ]; then
    echo "  ERROR: Failed to create job template" >> $LOG
    echo "=== Module 09 solve FAILED: $(date) ===" >> $LOG
    exit 1
  fi
fi

# --- Step 8: Launch the job ---
echo "[8/8] Launching job..." >> $LOG

LAUNCH_RESPONSE=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  -X POST "${AAP_URL}/api/controller/v2/job_templates/${JT_ID}/launch/")
echo "  launch response: $LAUNCH_RESPONSE" >> $LOG

JOB_ID=$(echo "$LAUNCH_RESPONSE" | jq -r '.id // .job')
echo "  job ID: ${JOB_ID}" >> $LOG

if [ "$JOB_ID" = "null" ] || [ -z "$JOB_ID" ]; then
  echo "  ERROR: Failed to launch job" >> $LOG
  echo "=== Module 09 solve FAILED: $(date) ===" >> $LOG
  exit 1
fi

echo "  Waiting for job to complete..." >> $LOG
for i in $(seq 1 60); do
  JOB_STATUS=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
    "${AAP_URL}/api/controller/v2/jobs/${JOB_ID}/" \
    | jq -r '.status')
  if [ "$JOB_STATUS" = "successful" ]; then
    echo "  job completed successfully (attempt $i)" >> $LOG
    break
  fi
  if [ "$JOB_STATUS" = "failed" ] || [ "$JOB_STATUS" = "error" ] || [ "$JOB_STATUS" = "canceled" ]; then
    echo "  ERROR: Job finished with status: $JOB_STATUS" >> $LOG
    break
  fi
  sleep 5
done

echo "  final job status: ${JOB_STATUS}" >> $LOG
echo "=== Module 09 solve finished: $(date) ===" >> $LOG
