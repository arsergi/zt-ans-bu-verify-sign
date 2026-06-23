#!/bin/bash
LOG="/tmp/solve-module-04.log"
echo "=== Module 04 solve started: $(date) ===" > $LOG

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

echo "[1/2] Creating playbook and inventory files..." >> $LOG
$RUNAS bash <<'SOLVE'
cd /home/rhel/ansible-sign-demo

mkdir -p playbooks

cat << EOF > playbooks/hello_world.yml
---
# This playbook prints a simple debug message
- name: Hello world
  hosts: all
  tasks:
  - name: Print debug message
    debug:
      msg: Hello, world!
EOF

cat << EOF > inventory
# This is an empty inventory file that will be signed using ansible-sign
EOF
SOLVE
echo "  exit code: $?" >> $LOG

echo "[2/2] Git commit and push..." >> $LOG
$RUNAS bash <<'SOLVE' 2>&1 | tee -a /tmp/solve-module-04.log
export GIT_TERMINAL_PROMPT=0
cd /home/rhel/ansible-sign-demo
git add playbooks/ inventory
git commit -m "Adding new files in the project"
git push
SOLVE
echo "  exit code: ${PIPESTATUS[0]}" >> $LOG
echo "=== Module 04 solve finished: $(date) ===" >> $LOG
