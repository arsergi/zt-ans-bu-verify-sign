#!/bin/sh
echo "Solving module called module-08" >> /tmp/progress.log
sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

$RUNAS bash <<'_'
cd /home/rhel

# Import the hub's public key into a keyring
gpg --import --no-default-keyring --keyring ~/keyring.kbx ~/galaxy_signing_service.asc

# Install without verification
ansible-galaxy collection install ansible.test_collection -c -p ~/.ansible/collections/

# Install with verification
ansible-galaxy collection install community.lab_collection --keyring ~/keyring.kbx -c -p ~/.ansible/collections/ -vvvv

# Tamper with the collection
touch ~/.ansible/collections/ansible_collections/community/lab_collection/docs/README.md

# Verify (will show the tampering)
ansible-galaxy collection verify community.lab_collection --keyring ~/keyring.kbx -c || true
_
