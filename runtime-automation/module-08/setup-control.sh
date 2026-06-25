#!/bin/sh
echo "Starting module called module-08" >> /tmp/progress.log

su - rhel <<'_'
rm -rf ~/.ansible/collections/ansible_collections/
rm -f ~/keyring.kbx ~/keyring.kbx~
_
