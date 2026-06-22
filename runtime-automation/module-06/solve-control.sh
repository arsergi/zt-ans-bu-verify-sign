#!/bin/sh
echo "Solving module called module-06" >> /tmp/progress.log
sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

$RUNAS bash <<'_'
cd /home/rhel
ansible-galaxy collection publish ansible-test_collection-1.0.0.tar.gz -c
ansible-galaxy collection publish community-lab_collection-1.0.0.tar.gz -c
_
