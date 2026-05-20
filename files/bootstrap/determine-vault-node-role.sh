#!/bin/sh
# determine-vault-node-role.sh
#
# Elects the bootstrap node by lowest EC2 instance ID and publishes the
# winner's instance ID to SSM.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

bootstrap_cluster_ready() (
  bootstrap_cluster_state="$(
    fetch_parameter "${BOOTSTRAP_VAULT_CLUSTER_STATE_SSM_PARAMETER_NAME}" 2>/dev/null
  )" || bootstrap_cluster_state=""

  [ "${bootstrap_cluster_state}" = "Ready" ]
)

is_bootstrap_node() (
  cluster_instance_ids="$1"

  lowest_instance_id="$(
    printf '%s' "${cluster_instance_ids}" |
      tr '\t' '\n' | sort | head -1
  )"

  [ "${INSTANCE_ID}" = "${lowest_instance_id}" ]
)

bootstrap_instance_id_published() (
  bootstrap_instance_id="$(
    fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER_NAME}" 2>/dev/null
  )" || return 1

  [ -n "${bootstrap_instance_id}" ] || return 1
  [ "${bootstrap_instance_id}" != "Uninitialized" ] || return 1

  return 0
)

claim_bootstrap_role() (
  log_info "================================================================"
  log_info ""
  log_info "             This Vault node won bootstrap election             "
  log_info ""
  log_info "================================================================"
  log_info "Publishing EC2 instance ID (${INSTANCE_ID}) to SSM parameter: ${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER_NAME}"

  put_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER_NAME}" "${INSTANCE_ID}"
)

await_bootstrap_election() (
  log_info "Waiting for bootstrap election to be published to SSM"

  timeout_seconds=20
  retry_for "${timeout_seconds}" bootstrap_instance_id_published ||
    {
      log_error "Bootstrap election not published after ${timeout_seconds}s"
      return 1
    }
)

main() {
  if bootstrap_cluster_ready; then
    log_info "Cluster already initialized, skipping bootstrap election"
    return 0
  fi

  cluster_instance_ids="$(fetch_instance_ids_with_tag "${AUTO_JOIN_TAG_KEY}" "${AUTO_JOIN_TAG_VALUE}")"

  if is_bootstrap_node "${cluster_instance_ids}"; then
    claim_bootstrap_role
  else
    await_bootstrap_election
  fi
}

main "$@"
