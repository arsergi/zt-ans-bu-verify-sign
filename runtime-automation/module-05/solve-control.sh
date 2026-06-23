#!/bin/bash
LOG="/tmp/solve-module-05.log"
echo "=== Module 05 solve started: $(date) ===" > $LOG

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

echo "[1/3] Updating MANIFEST.in..." >> $LOG
$RUNAS bash <<'SOLVE'
echo -e "recursive-include playbooks *.yml\ninclude inventory" >> /home/rhel/ansible-sign-demo/MANIFEST.in
SOLVE
echo "  exit code: $?" >> $LOG

echo "[2/3] Re-signing project..." >> $LOG
$RUNAS bash <<'SOLVE' 2>&1 | tee -a /tmp/solve-module-05.log
cd /home/rhel
ansible-sign project gpg-sign ansible-sign-demo
SOLVE
echo "  exit code: ${PIPESTATUS[0]}" >> $LOG
echo "  completed: $(date)" >> $LOG

echo "[3/3] Git commit and push..." >> $LOG
$RUNAS bash <<'SOLVE' 2>&1 | tee -a /tmp/solve-module-05.log
export GIT_TERMINAL_PROMPT=0
cd /home/rhel/ansible-sign-demo
git add MANIFEST.in .ansible-sign/
git commit -m "Adding signatures for new files in the project"
git push
SOLVE
echo "  exit code: ${PIPESTATUS[0]}" >> $LOG
echo "=== Module 05 solve finished: $(date) ===" >> $LOG
