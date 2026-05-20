#!/bin/sh
# await-vault-cluster.sh
#
# Waits for the Vault cluster to be initialized (cluster_state=Ready in SSM)
# and for the local vault.service to be unsealed by KMS auto-unseal. Runs
# on every node after initialize-vault-cluster.sh. The bootstrap node passes
# through quickly since it just published Ready and KMS auto-unseal completes
# during operator init.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

vault_cluster_ready() (
  vault_cluster_state="$(fetch_parameter "${BOOTSTRAP_VAULT_CLUSTER_STATE_SSM_PARAMETER_NAME}")" || return 1

  [ "${vault_cluster_state}" = "Ready" ]
)

await_vault_cluster() (
  log_info "Waiting for the Vault cluster to be initialized"

  timeout_seconds=1200
  retry_for "${timeout_seconds}" vault_cluster_ready ||
    {
      log_error "Unable to join the Vault cluster after ${timeout_seconds}s"
      return 1
    }
)

vault_unsealed() (
  vault_status_exit_code=0
  vault_status_err="$(vault status -format=json 2>&1 >/dev/null)" || vault_status_exit_code="$?"

  case "${vault_status_exit_code}" in
    0)
      return 0
      ;;
    2)
      return 1 # Sealed, keep waiting
      ;;
    *)
      log_warn "vault status errored (exit ${vault_status_exit_code}): ${vault_status_err}"
      return 1
      ;;
  esac
)

await_vault_unseal() (
  log_info "Waiting for this Vault node to be unsealed"

  timeout_seconds=1200
  retry_for "${timeout_seconds}" vault_unsealed ||
    {
      log_error "Vault node did not unseal after ${timeout_seconds}s"
      return 1
    }
)

raft_replication_ready() (
  vault_leader_response="$(vault read -format=json sys/leader 2>/dev/null)" || return 1

  [ -n "${vault_leader_response}" ] || return 1

  raft_committed_index="$(printf '%s' "${vault_leader_response}" | jq -r '.data.raft_committed_index // empty')"
  [ -n "${raft_committed_index}" ] || return 1

  raft_applied_index="$(printf '%s' "${vault_leader_response}" | jq -r '.data.raft_applied_index // empty')"
  [ -n "${raft_applied_index}" ] || return 1

  [ "${raft_committed_index}" -gt 0 ] || return 1
  [ "${raft_applied_index}" -ge "${raft_committed_index}" ] || return 1

  return 0
)

await_raft_replication() (
  log_info "Waiting for Vault Raft replication to be ready"

  timeout_seconds=1200
  retry_for "${timeout_seconds}" raft_replication_ready ||
    {
      log_error "Vault Raft replication did not catch up after ${timeout_seconds}s"
      return 1
    }
)

main() {
  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"

  await_vault_cluster
  await_vault_unseal
  await_raft_replication
}

main "$@"
