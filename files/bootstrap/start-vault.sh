#!/bin/sh
# start-vault.sh
#
# Starts the local Vault systemd unit and waits for the local API to begin
# responding. Runs on every node after the Vault binary, license, TLS
# materials, and configuration files are in place.

set -euf

# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_TLS_CA_FILE="/opt/vault/tls/ca.crt"

start_vault() (
  log_info "Starting vault.service"

  systemctl daemon-reload
  systemctl enable --now vault
)

vault_api_ready() (
  curl_exit=0
  status="$(
    curl --silent --cacert "${VAULT_TLS_CA_FILE}" \
      --output /dev/null --write-out '%{http_code}' \
      "https://127.0.0.1:8200/v1/sys/health" 2>/dev/null
  )" || curl_exit="$?"

  if [ "${curl_exit}" -ne 0 ]; then
    # The node's own bootstrap CA in ca.crt should validate the local
    # listener, but a verification failure (curl exit 60) still proves the
    # API is responding, so tolerate it rather than stall the boot.
    [ "${curl_exit}" -eq 60 ]
    return
  fi

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
