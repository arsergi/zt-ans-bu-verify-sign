#!/bin/bash
LOG="/tmp/solve-module-02.log"
echo "=== Module 02 solve started: $(date) ===" > $LOG

sudo -u rhel bash -c : && RUNAS="sudo -u rhel"

echo "[1/2] Generating GPG keypair..." >> $LOG
$RUNAS bash <<'SOLVE'
gpg --batch --gen-key ~/gpg.txt 2>&1
SOLVE
echo "  exit code: $?" >> $LOG
echo "  completed: $(date)" >> $LOG

echo "[2/2] Exporting public key..." >> $LOG
$RUNAS bash <<'SOLVE'
gpg --output ~/signing_demo.asc --armor --export 2>&1
SOLVE
echo "  exit code: $?" >> $LOG

echo "=== Module 02 solve finished: $(date) ===" >> $LOG
