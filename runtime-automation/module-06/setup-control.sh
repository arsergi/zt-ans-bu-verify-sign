#!/bin/sh
echo "Starting module called module-06" >> /tmp/progress.log
sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

PAH_URL="https://localhost"
PAH_USER="admin"
PAH_PASS="ansible123!"

# --- Wait for PAH gateway to be ready ---

echo "Waiting for PAH API to become available..." >> /tmp/progress.log
for i in $(seq 1 30); do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -u ${PAH_USER}:${PAH_PASS} \
    ${PAH_URL}/api/galaxy/v3/namespaces/)
  if [ "$HTTP_CODE" = "200" ]; then
    echo "PAH API ready after ${i} attempts" >> /tmp/progress.log
    break
  fi
  echo "Attempt $i: PAH returned HTTP $HTTP_CODE, retrying in 10s..." >> /tmp/progress.log
  sleep 10
done

# --- Check if signing service already exists, configure if not ---

SIGNING_SVC=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/ | jq -r '.results[0].name // empty')

if [ -z "$SIGNING_SVC" ]; then
  echo "No signing service found, configuring one..." >> /tmp/progress.log

  # Generate a GPG key for the PAH signing service
  cat > /tmp/pah_gpg.txt <<GPGEOF
%echo Generating PAH Signing Service key
Key-Type: RSA
Key-Length: 4096
Subkey-Type: RSA
Subkey-Length: 4096
Name-Real: PAH Signing Service
Name-Comment: collection signing
Name-Email: pah-signing@localhost
Expire-Date: 0
%no-ask-passphrase
%no-protection
%commit
%echo done
GPGEOF

  gpg --batch --gen-key /tmp/pah_gpg.txt

  # Get the key fingerprint
  KEY_FP=$(gpg --list-keys --with-colons "PAH Signing Service" | awk -F: '/^fpr:/{print $10; exit}')

  # Create the signing script
  cat > /usr/local/bin/collection_sign.sh <<'SIGNEOF'
#!/usr/bin/env bash
FILE_PATH=$1
SIGNATURE_PATH="${FILE_PATH}.asc"
gpg --batch --yes --armor --detach-sign --output "${SIGNATURE_PATH}" "${FILE_PATH}"
echo "{\"file\": \"${FILE_PATH}\", \"signature\": \"${SIGNATURE_PATH}\"}"
SIGNEOF
  chmod +x /usr/local/bin/collection_sign.sh

  # Register the signing service with pulp
  curl -sk -u ${PAH_USER}:${PAH_PASS} \
    -H "Content-Type: application/json" \
    -X POST ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/ \
    -d "{\"name\":\"ansible-default\",\"script\":\"/usr/local/bin/collection_sign.sh\",\"pubkey_fingerprint\":\"${KEY_FP}\"}"

  echo "Signing service configured with fingerprint ${KEY_FP}" >> /tmp/progress.log
else
  echo "Signing service '${SIGNING_SVC}' already exists" >> /tmp/progress.log
fi

# --- Export the signing service public key ---

# Determine which key to export based on whether we created one or it already existed
if gpg --list-keys "PAH Signing Service" > /dev/null 2>&1; then
  gpg --output /home/rhel/galaxy_signing_service.asc --armor --export "PAH Signing Service"
else
  # If the key is in the system keyring (pre-configured image), try exporting the first available key
  EXISTING_FP=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
    ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/ | jq -r '.results[0].pubkey_fingerprint // empty')
  if [ -n "$EXISTING_FP" ]; then
    gpg --output /home/rhel/galaxy_signing_service.asc --armor --export "${EXISTING_FP}"
  fi
fi

# --- Create namespaces ---

curl -sk -u ${PAH_USER}:${PAH_PASS} \
  -H "Content-Type: application/json" \
  -X POST ${PAH_URL}/api/galaxy/v3/namespaces/ \
  -d '{"name":"ansible","groups":[]}'

curl -sk -u ${PAH_USER}:${PAH_PASS} \
  -H "Content-Type: application/json" \
  -X POST ${PAH_URL}/api/galaxy/v3/namespaces/ \
  -d '{"name":"community","groups":[]}'

echo "Namespaces created" >> /tmp/progress.log

# --- Generate API token ---

TOKEN=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
  -X POST ${PAH_URL}/api/galaxy/v3/auth/token/ | jq -r '.token // empty')

if [ -z "$TOKEN" ]; then
  TOKEN=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
    ${PAH_URL}/api/galaxy/v3/auth/token/ | jq -r '.token // empty')
fi

echo "API token generated" >> /tmp/progress.log

# --- Write ansible.cfg ---

cat > /home/rhel/ansible.cfg <<CFGEOF
[galaxy]
server_list = published_repo

[galaxy_server.published_repo]
url=${PAH_URL}/api/galaxy/content/published/
token=${TOKEN}
validate_certs=false
CFGEOF

# --- Build test collections ---

COLLECTIONS_DIR=$(mktemp -d)

ansible-galaxy collection init ansible.test_collection --init-path ${COLLECTIONS_DIR}
cat > ${COLLECTIONS_DIR}/ansible/test_collection/galaxy.yml <<GALEOF
namespace: ansible
name: test_collection
version: 1.0.0
readme: README.md
authors:
  - Lab Student <student@localhost>
description: A test collection for signing demonstration
tags:
  - tools
GALEOF

ansible-galaxy collection init community.lab_collection --init-path ${COLLECTIONS_DIR}
cat > ${COLLECTIONS_DIR}/community/lab_collection/galaxy.yml <<GALEOF
namespace: community
name: lab_collection
version: 1.0.0
readme: README.md
authors:
  - Lab Student <student@localhost>
description: A lab collection for signing demonstration
tags:
  - tools
GALEOF

ansible-galaxy collection build ${COLLECTIONS_DIR}/ansible/test_collection --output-path /home/rhel/
ansible-galaxy collection build ${COLLECTIONS_DIR}/community/lab_collection --output-path /home/rhel/

rm -rf ${COLLECTIONS_DIR}

echo "Test collections built" >> /tmp/progress.log

# --- Fix ownership ---

chown rhel:rhel /home/rhel/ansible-test_collection-1.0.0.tar.gz
chown rhel:rhel /home/rhel/community-lab_collection-1.0.0.tar.gz
chown rhel:rhel /home/rhel/ansible.cfg
chown rhel:rhel /home/rhel/galaxy_signing_service.asc 2>/dev/null

echo "Module 06 setup complete" >> /tmp/progress.log
