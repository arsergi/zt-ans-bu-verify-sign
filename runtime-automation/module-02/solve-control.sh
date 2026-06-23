#!/bin/bash
echo "Solving module-02: Create GPG keypair" >> /tmp/progress.log

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

$RUNAS bash <<'SOLVE'
gpg --batch --gen-key ~/gpg.txt
gpg --output ~/signing_demo.asc --armor --export
SOLVE
