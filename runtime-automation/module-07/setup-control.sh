#!/bin/sh
echo "Starting module called module-07" >> /tmp/progress.log

su - rhel -c "rm -rf ~/.ansible/collections/ansible_collections/"
