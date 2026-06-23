#!/bin/bash

SETUP_LOG="/home/rhel/setup-provision.log"
echo "=== Setup started: $(date) ===" > $SETUP_LOG

systemctl stop systemd-tmpfiles-setup.service
systemctl disable systemd-tmpfiles-setup.service

# # Install collection(s)
# ansible-galaxy collection install ansible.eda
# ansible-galaxy collection install community.general
# ansible-galaxy collection install ansible.windows
# ansible-galaxy collection install microsoft.ad

echo "[1/6] Making ansible-sign available..." >> $SETUP_LOG
# ansible-sign is pre-installed inside the AAP 2.5 container image.
# Find it and symlink to /usr/bin so the rhel user can run it directly.
if ! command -v ansible-sign &>/dev/null; then
  SIGN_BIN=$(find /home/rhel/aap/containers/storage -name ansible-sign -type f -executable 2>/dev/null | head -1)
  if [ -z "$SIGN_BIN" ]; then
    SIGN_BIN=$(find / -name ansible-sign -type f -executable 2>/dev/null | head -1)
  fi
  echo "  ansible-sign found at: ${SIGN_BIN:-NOT FOUND}" >> $SETUP_LOG
  if [ -n "$SIGN_BIN" ]; then
    ln -sf "$SIGN_BIN" /usr/bin/ansible-sign
    echo "  symlinked to /usr/bin/ansible-sign" >> $SETUP_LOG
  else
    echo "  ERROR: ansible-sign not found in container overlay or anywhere on disk" >> $SETUP_LOG
  fi
else
  echo "  ansible-sign already on PATH: $(which ansible-sign)" >> $SETUP_LOG
fi

# Verify it works as rhel user
RHEL_CHECK=$(su - rhel -c "ansible-sign --version 2>&1")
echo "  rhel user ansible-sign: $RHEL_CHECK" >> $SETUP_LOG

echo "[3/6] Setting up rhel user sudo and SSH..." >> $SETUP_LOG
# # ## setup rhel user
touch /etc/sudoers.d/rhel_sudoers
echo "%rhel ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/rhel_sudoers
cp -a /root/.ssh/* /home/$USER/.ssh/.
chown -R rhel:rhel /home/$USER/.ssh
echo "  sudoers and SSH: done" >> $SETUP_LOG

echo "[4/6] Configuring git credentials..." >> $SETUP_LOG
git config credential.helper store
touch /home/rhel/.git-credentials
su - rhel -c "echo 'https://gitea:gitea' >> /home/rhel/.git-credentials"
git push -u origin master
su - rhel -c "git config --global user.name gitea"
su - rhel -c "git config --global user.email student@localhost"
echo "  git credentials: done" >> $SETUP_LOG

echo "[5/6] Creating ansible-sign-demo directory..." >> $SETUP_LOG
sudo mkdir -p /home/rhel/ansible-sign-demo
sudo chown rhel:rhel /home/rhel/ansible-sign-demo
echo "  ansible-sign-demo: done" >> $SETUP_LOG

echo "[6/6] Final checks..." >> $SETUP_LOG
echo "  ansible-sign path: $(which ansible-sign 2>&1)" >> $SETUP_LOG
echo "  ansible-sign version: $(ansible-sign --version 2>&1)" >> $SETUP_LOG
echo "  python3 version: $(python3 --version 2>&1)" >> $SETUP_LOG

chown rhel:rhel $SETUP_LOG
echo "=== Setup finished: $(date) ===" >> $SETUP_LOG
