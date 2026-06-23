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
# ansible-sign is pre-installed inside the AAP 2.5 container image but its
# shebang references python3.11 which doesn't exist on the host (has 3.9).
# Copy the binary out, fix the shebang to use the system python3.
SIGN_BIN=$(find /home/rhel/aap/containers/storage -name ansible-sign -type f 2>/dev/null | head -1)
if [ -z "$SIGN_BIN" ]; then
  SIGN_BIN=$(find / -path "*/containers/storage/*" -name ansible-sign -type f 2>/dev/null | head -1)
fi
echo "  ansible-sign found at: ${SIGN_BIN:-NOT FOUND}" >> $SETUP_LOG

if [ -n "$SIGN_BIN" ]; then
  cp "$SIGN_BIN" /usr/bin/ansible-sign
  # Fix shebang to use the system python3
  sed -i '1s|^#!.*python.*|#!/usr/bin/python3|' /usr/bin/ansible-sign
  chmod +x /usr/bin/ansible-sign
  echo "  copied to /usr/bin/ansible-sign, shebang fixed to $(head -1 /usr/bin/ansible-sign)" >> $SETUP_LOG

  # Also need the ansible_sign python package — find it in the container overlay
  SIGN_PKG=$(find /home/rhel/aap/containers/storage -type d -name "ansible_sign" 2>/dev/null | grep "site-packages/ansible_sign$" | head -1)
  if [ -n "$SIGN_PKG" ]; then
    SITE_PACKAGES=$(python3 -c "import site; print(site.getsitepackages()[0])")
    cp -r "$SIGN_PKG" "$SITE_PACKAGES/"
    echo "  ansible_sign package copied from $SIGN_PKG to $SITE_PACKAGES/" >> $SETUP_LOG
  else
    echo "  WARN: ansible_sign python package not found in container overlay" >> $SETUP_LOG
  fi
else
  echo "  ERROR: ansible-sign not found in container overlay" >> $SETUP_LOG
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
