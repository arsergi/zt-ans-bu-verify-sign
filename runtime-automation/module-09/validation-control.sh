#!/bin/bash
echo "Validated module called module-09" >> /tmp/progress.log

AAP_URL="https://localhost"
AAP_USER="admin"
AAP_PASS="ansible123!"
CURL_OPTS="-sk --connect-timeout 10 --max-time 30"

# Check 1: Galaxy credential is associated with Default organization
ORG_ID=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/organizations/?name=Default" \
  | jq -r '.results[0].id')

GALAXY_CRED_COUNT=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/organizations/${ORG_ID}/galaxy_credentials/" \
  | jq -r '.count')

if [ "$GALAXY_CRED_COUNT" = "0" ] || [ -z "$GALAXY_CRED_COUNT" ]; then
  fail-message "No Galaxy/Automation Hub credential is associated with the Default organization. Create a Galaxy credential and add it to the Default organization's Galaxy Credentials."
fi

# Check 2: Job template exists for the signed collection playbook
JT_EXISTS=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/job_templates/" \
  | jq -r '[.results[] | select(.playbook == "playbooks/use_signed_collection.yml")] | length')

if [ "$JT_EXISTS" = "0" ] || [ -z "$JT_EXISTS" ]; then
  fail-message "No Job Template using the playbook 'playbooks/use_signed_collection.yml' was found. Create a Job Template that uses the Signed Project and this playbook."
fi

# Check 3: A successful job run exists for the playbook
SUCCESSFUL_JOBS=$(curl $CURL_OPTS -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/jobs/?status=successful" \
  | jq -r '[.results[] | select(.playbook == "playbooks/use_signed_collection.yml")] | length')

if [ "$SUCCESSFUL_JOBS" = "0" ] || [ -z "$SUCCESSFUL_JOBS" ]; then
  fail-message "No successful job run was found for the signed collection playbook. Launch the job template and ensure it completes successfully."
fi
