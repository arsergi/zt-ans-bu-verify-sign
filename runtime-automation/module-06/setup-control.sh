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

CONTAINER_GNUPGHOME="/var/lib/pulp/.gnupg"

if [ -z "$SIGNING_SVC" ]; then
  echo "No signing service found, configuring one inside hub containers..." >> /tmp/progress.log

  # GPG batch config for key generation
  cat > /tmp/pah_gpg.txt <<'GPGEOF'
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

  # Generate GPG key inside hub worker container using a shared GNUPGHOME
  # on the /var/lib/pulp volume so all workers can access it
  su - rhel -c "podman cp /tmp/pah_gpg.txt automation-hub-worker-1:/tmp/pah_gpg.txt"
  su - rhel -c "podman exec automation-hub-worker-1 bash -c 'mkdir -p ${CONTAINER_GNUPGHOME} && chmod 700 ${CONTAINER_GNUPGHOME} && GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --batch --gen-key /tmp/pah_gpg.txt'"

  KEY_FP=$(su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --list-keys --with-colons \"PAH Signing Service\"'" | awk -F: '/^fpr:/{print $10; exit}')
  echo "GPG key generated inside container with fingerprint ${KEY_FP}" >> /tmp/progress.log

  # Replicate GPG key to worker-2 in case /var/lib/pulp is not a shared volume
  su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --batch --yes --armor --export-secret-keys \"PAH Signing Service\"'" > /tmp/pah_signing_private.key
  su - rhel -c "podman exec automation-hub-worker-2 bash -c 'mkdir -p ${CONTAINER_GNUPGHOME} && chmod 700 ${CONTAINER_GNUPGHOME}'"
  su - rhel -c "podman cp /tmp/pah_signing_private.key automation-hub-worker-2:/tmp/pah_signing_private.key"
  su - rhel -c "podman exec automation-hub-worker-2 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --batch --yes --import /tmp/pah_signing_private.key && rm -f /tmp/pah_signing_private.key'"
  rm -f /tmp/pah_signing_private.key

  # Create the signing script with explicit GNUPGHOME so the worker
  # process finds the key regardless of which user it runs as
  cat > /tmp/collection_sign.sh <<'SIGNEOF'
#!/usr/bin/env bash
export GNUPGHOME=/var/lib/pulp/.gnupg
FILE_PATH=$1
SIGNATURE_PATH="${FILE_PATH}.asc"
gpg --batch --yes --armor --detach-sign --output "${SIGNATURE_PATH}" "${FILE_PATH}"
echo "{\"file\": \"${FILE_PATH}\", \"signature\": \"${SIGNATURE_PATH}\"}"
SIGNEOF
  chmod +x /tmp/collection_sign.sh

  # Install script into both workers (defensive — in case /var/lib/pulp is not shared)
  for WORKER in automation-hub-worker-1 automation-hub-worker-2; do
    su - rhel -c "podman exec ${WORKER} mkdir -p /var/lib/pulp/scripts"
    su - rhel -c "podman cp /tmp/collection_sign.sh ${WORKER}:/var/lib/pulp/scripts/collection_sign.sh"
    su - rhel -c "podman exec ${WORKER} chmod +x /var/lib/pulp/scripts/collection_sign.sh"
  done

  # Register the signing service with Pulp (container-internal path)
  curl -sk -u ${PAH_USER}:${PAH_PASS} \
    -H "Content-Type: application/json" \
    -X POST ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/ \
    -d "{\"name\":\"ansible-default\",\"script\":\"/var/lib/pulp/scripts/collection_sign.sh\",\"pubkey_fingerprint\":\"${KEY_FP}\"}"

  echo "Signing service registered" >> /tmp/progress.log
else
  echo "Signing service '${SIGNING_SVC}' already exists" >> /tmp/progress.log
fi

# --- Configure Galaxy NG to auto-sign collections on approval ---

cat > /tmp/galaxy_signing_settings.py <<'SETTINGSEOF'
GALAXY_COLLECTION_SIGNING_SERVICE = "ansible-default"
GALAXY_AUTO_SIGN_COLLECTIONS = True
GALAXY_REQUIRE_CONTENT_APPROVAL = True
SETTINGSEOF

SETTINGS_CHANGED=false
for CONTAINER in automation-hub-api automation-hub-worker-1 automation-hub-worker-2; do
  if su - rhel -c "podman exec ${CONTAINER} grep -q GALAXY_COLLECTION_SIGNING_SERVICE /etc/pulp/settings.py 2>/dev/null"; then
    continue
  fi
  su - rhel -c "podman cp /tmp/galaxy_signing_settings.py ${CONTAINER}:/tmp/galaxy_signing_settings.py"
  su - rhel -c "podman exec ${CONTAINER} bash -c 'cat /tmp/galaxy_signing_settings.py >> /etc/pulp/settings.py'"
  SETTINGS_CHANGED=true
done

if [ "$SETTINGS_CHANGED" = "true" ]; then
  echo "Galaxy NG signing settings configured, restarting hub containers..." >> /tmp/progress.log
  for CONTAINER in automation-hub-api automation-hub-content automation-hub-web automation-hub-worker-1 automation-hub-worker-2; do
    su - rhel -c "podman restart ${CONTAINER}"
  done

  # Wait for PAH API to come back up after restart
  for i in $(seq 1 30); do
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -u ${PAH_USER}:${PAH_PASS} \
      ${PAH_URL}/api/galaxy/v3/namespaces/)
    if [ "$HTTP_CODE" = "200" ]; then
      echo "PAH API ready after restart (attempt ${i})" >> /tmp/progress.log
      break
    fi
    sleep 10
  done
else
  echo "Galaxy NG signing settings already present" >> /tmp/progress.log
fi

# --- Export the signing service public key ---

su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --armor --export \"PAH Signing Service\"'" > /home/rhel/galaxy_signing_service.asc
if [ ! -s /home/rhel/galaxy_signing_service.asc ]; then
  EXISTING_FP=$(curl -sk -u ${PAH_USER}:${PAH_PASS} \
    ${PAH_URL}/api/galaxy/pulp/api/v3/signing-services/ | jq -r '.results[0].pubkey_fingerprint // empty')
  if [ -n "$EXISTING_FP" ]; then
    su - rhel -c "podman exec automation-hub-worker-1 bash -c 'GNUPGHOME=${CONTAINER_GNUPGHOME} gpg --armor --export \"${EXISTING_FP}\"'" > /home/rhel/galaxy_signing_service.asc
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
license:
  - GPL-3.0-or-later
repository: https://git.example.com/ansible/test_collection
tags:
  - tools
GALEOF
echo "Initial release" > ${COLLECTIONS_DIR}/ansible/test_collection/CHANGELOG.md
mkdir -p ${COLLECTIONS_DIR}/ansible/test_collection/meta
cat > ${COLLECTIONS_DIR}/ansible/test_collection/meta/runtime.yml <<RTEOF
---
requires_ansible: ">=2.15.0"
RTEOF

ansible-galaxy collection init community.lab_collection --init-path ${COLLECTIONS_DIR}
cat > ${COLLECTIONS_DIR}/community/lab_collection/galaxy.yml <<GALEOF
namespace: community
name: lab_collection
version: 1.0.0
readme: README.md
authors:
  - Lab Student <student@localhost>
description: A lab collection for signing demonstration
license:
  - GPL-3.0-or-later
repository: https://git.example.com/community/lab_collection
tags:
  - tools
GALEOF
echo "Initial release" > ${COLLECTIONS_DIR}/community/lab_collection/CHANGELOG.md
mkdir -p ${COLLECTIONS_DIR}/community/lab_collection/meta
cat > ${COLLECTIONS_DIR}/community/lab_collection/meta/runtime.yml <<RTEOF
---
requires_ansible: ">=2.15.0"
RTEOF

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
