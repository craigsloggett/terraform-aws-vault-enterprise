#!/bin/sh
# start-vault.sh
#
# Starts the local Vault systemd unit and waits for the local API to begin
# responding. Runs on every node after the Vault binary, license, TLS
# materials, and configuration files are in place.

set -euf

# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

start_vault() (
  log_info "Starting vault.service"

  systemctl daemon-reload
  systemctl enable --now vault
)

vault_api_ready() (
  status="$(
    curl --silent --insecure --output /dev/null --write-out '%{http_code}' \
      "https://127.0.0.1:8200/v1/sys/health" 2>/dev/null
  )" || return 1

  [ "${status}" != "000" ]
)

await_vault_api() (
  log_info "Waiting for the Vault API to be ready"

  timeout_seconds=1200
  retry_for "${timeout_seconds}" vault_api_ready ||
    {
      log_error "Vault API did not respond after ${timeout_seconds}s"
      return 1
    }
)

main() {
  start_vault
  await_vault_api
}

main "$@"
