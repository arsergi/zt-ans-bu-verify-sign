#!/bin/bash
echo "Solving module-04: Add unsigned project content" >> /tmp/progress.log

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

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

git add playbooks/ inventory
git commit -m "Adding new files in the project"
git push
SOLVE
