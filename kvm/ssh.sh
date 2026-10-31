#!/bin/sh
# ssh.sh <vm> [command...]: runs a command on a Cloud Fusion VM as user "civic",
# using the address recorded by provision.sh and the lab key.
CF="${CF_HOME:-$HOME/cloudfusion}"
VM=$1; shift
exec ssh -i "$CF/keys/id_ed25519" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
  -o LogLevel=ERROR -o ConnectTimeout=5 "civic@$(cat "$CF/seed/$VM/ip")" "$@"
