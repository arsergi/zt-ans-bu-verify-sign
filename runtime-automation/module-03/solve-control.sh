#!/bin/bash
echo "Solving module-03: Sign project and create AAP credential/project" >> /tmp/progress.log

AAP_URL="https://localhost"
AAP_USER="admin"
AAP_PASS="ansible123!"

# --- Step 1: Create MANIFEST.in ---
sudo -u rhel bash <<'STEP1'
cat << EOF > /home/rhel/ansible-sign-demo/MANIFEST.in
recursive-exclude .git *
include README.md
EOF
STEP1

# --- Step 2: Sign the project ---
sudo -u rhel bash <<'STEP2'
cd /home/rhel
ansible-sign project gpg-sign ansible-sign-demo
STEP2

# --- Step 3: Git add, commit, push ---
sudo -u rhel bash <<'STEP3'
cd /home/rhel/ansible-sign-demo
git add .ansible-sign/ MANIFEST.in
git commit -m "Adding signatures for empty project"
git push
STEP3

# --- Step 4: Create GPG Public Key credential in AAP ---

GPG_KEY=$(cat /home/rhel/signing_demo.asc)

CRED_TYPE_ID=$(curl -sk -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/credential_types/?name=GPG+Public+Key" \
  | jq -r '.results[0].id')

echo "  GPG Public Key credential type ID: ${CRED_TYPE_ID}" >> /tmp/progress.log

CRED_PAYLOAD=$(jq -n \
  --arg name "ansible-sign" \
  --argjson cred_type "$CRED_TYPE_ID" \
  --arg gpg_key "$GPG_KEY" \
  '{
    name: $name,
    credential_type: $cred_type,
    inputs: { gpg_public_key: $gpg_key }
  }')

CRED_RESPONSE=$(curl -sk -u ${AAP_USER}:${AAP_PASS} \
  -H "Content-Type: application/json" \
  -X POST "${AAP_URL}/api/controller/v2/credentials/" \
  -d "$CRED_PAYLOAD")

CRED_ID=$(echo "$CRED_RESPONSE" | jq -r '.id')
echo "  Created credential ID: ${CRED_ID}" >> /tmp/progress.log

# --- Step 5: Create project with signature validation credential ---

ORG_ID=$(curl -sk -u ${AAP_USER}:${AAP_PASS} \
  "${AAP_URL}/api/controller/v2/organizations/?name=Default" \
  | jq -r '.results[0].id')

PROJECT_PAYLOAD=$(jq -n \
  --arg name "Signed Project" \
  --arg scm_url "http://gitea:3000/student/ansible-sign-demo.git" \
  --argjson org_id "$ORG_ID" \
  --argjson cred_id "$CRED_ID" \
  '{
    name: $name,
    scm_type: "git",
    scm_url: $scm_url,
    organization: $org_id,
    signature_validation_credential: $cred_id
  }')

curl -sk -u ${AAP_USER}:${AAP_PASS} \
  -H "Content-Type: application/json" \
  -X POST "${AAP_URL}/api/controller/v2/projects/" \
  -d "$PROJECT_PAYLOAD"

echo "Module 03 solve complete" >> /tmp/progress.log
