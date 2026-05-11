#!/bin/sh
# start-vault-agent.sh
#
# Starts the local Vault Agent systemd unit. Runs on every node after Vault
# is unsealed, joined to the cluster, and serving a PKI-signed listener cert
# so the agent's Consul Template renderer can immediately request a leaf
# certificate.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

main() {
  log_info "Starting Vault Agent"

  systemctl daemon-reload
  systemctl enable --now vault-agent
}

main "${@}"
