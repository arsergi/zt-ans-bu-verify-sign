#!/bin/sh
echo "Starting module called module-07" >> /tmp/progress.log
sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

$RUNAS bash <<'_'
rm -rf ~/.ansible/collections/ansible_collections/
_
