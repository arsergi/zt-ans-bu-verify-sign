#!/bin/bash
echo "Solving module-05: Re-sign new content" >> /tmp/progress.log

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

$RUNAS bash <<'SOLVE'
cd /home/rhel

echo -e "recursive-include playbooks *.yml\ninclude inventory" >> ansible-sign-demo/MANIFEST.in

ansible-sign project gpg-sign ansible-sign-demo

cd ansible-sign-demo
git add MANIFEST.in .ansible-sign/
git commit -m "Adding signatures for new files in the project"
git push
SOLVE
