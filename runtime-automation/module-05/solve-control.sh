#!/bin/bash
LOG="/tmp/solve-module-05.log"
echo "=== Module 05 solve started: $(date) ===" > $LOG

echo "[1/3] Updating MANIFEST.in..." >> $LOG
sudo -iu rhel bash <<'SOLVE' >> $LOG 2>&1
echo -e "recursive-include playbooks *.yml\ninclude inventory" >> ~/ansible-sign-demo/MANIFEST.in
SOLVE
echo "  exit code: $?" >> $LOG

echo "[2/3] Re-signing project..." >> $LOG
sudo -iu rhel bash <<'SOLVE' >> $LOG 2>&1
ansible-sign project gpg-sign ~/ansible-sign-demo
SOLVE
echo "  exit code: $?" >> $LOG
echo "  completed: $(date)" >> $LOG

echo "[3/3] Git commit and push..." >> $LOG
sudo -iu rhel bash <<'SOLVE' >> $LOG 2>&1
export GIT_TERMINAL_PROMPT=0
git config --global credential.helper store
cd ~/ansible-sign-demo
git add MANIFEST.in .ansible-sign/
git commit -m "Adding signatures for new files in the project"
git push
SOLVE
echo "  exit code: $?" >> $LOG
echo "=== Module 05 solve finished: $(date) ===" >> $LOG
