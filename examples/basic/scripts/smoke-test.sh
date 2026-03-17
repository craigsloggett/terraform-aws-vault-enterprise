#!/bin/sh
# Usage: VAULT_TOKEN=$(jq -r '.root_token' vault-init.json) ./smoke-test.sh

log() {
  printf '%b%s %b%s%b %s\n' \
    "${c1}" "${3:-->}" "${c3}${2:+$c2}" "$1" "${c3}" "$2" >&2
}

read_terraform_outputs() {
  log "Reading Terraform outputs."

  bastion_ip=$(terraform output -raw bastion_public_ip)
  vault_ip=$(terraform output -json vault_private_ips | jq -r '.[0]')
  vault_ca_cert=$(terraform output -raw vault_ca_cert)

  log "  Bastion IP:" "${bastion_ip}"
  log "  Vault node:" "${vault_ip}"
}

setup_tunnel() {
  log "Opening SSH tunnel to ${vault_ip}:8200."

  ca_cert_file=$(mktemp)
  ssh_socket=$(mktemp -u)
  printf '%s\n' "${vault_ca_cert}" >"${ca_cert_file}"

  # shellcheck disable=SC2086
  ssh ${ssh_opts} -f -N -M -S "${ssh_socket}" \
    -L 8200:"${vault_ip}":8200 "ubuntu@${bastion_ip}"

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_CACERT="${ca_cert_file}"
}

cleanup() {
  rm -f "${ca_cert_file}"
  ssh -S "${ssh_socket}" -O exit x 2>/dev/null
}

wait_for_vault() {
  log "Waiting for Vault to be reachable."

  attempts=0
  max_attempts=30
  while ! curl -sf --cacert "${ca_cert_file}" \
    "${VAULT_ADDR}/v1/sys/health?standbyok=true" >/dev/null 2>&1; do
    attempts=$((attempts + 1))
    if [ "${attempts}" -ge "${max_attempts}" ]; then
      log "ERROR: Vault not reachable after ${max_attempts} attempts."
      exit 1
    fi
    sleep 2
  done

  log "Vault is reachable."
}

test_cluster_health() {
  log "Checking cluster health."
  vault status
  vault operator raft list-peers
}

test_secrets_engine() {
  log "Testing secrets engine (KV v2)."
  vault secrets enable -path=kv-smoke -version=2 kv
  vault kv put kv-smoke/test message="smoke test"
  vault kv get kv-smoke/test
  vault secrets disable kv-smoke
  log "  KV smoke test passed."
}

test_auth_method() {
  log "Testing auth method (AppRole)."
  vault auth enable -path=approle-smoke approle
  vault auth disable approle-smoke
  log "  AppRole smoke test passed."
}

test_license() {
  log "Checking license status."
  license_json=$(vault read -format=json sys/license/status)
  printf '%s\n' "${license_json}" |
    jq '{license_id: .data.autoloaded.license_id, expiration: .data.autoloaded.expiration_time}'
}

main() {
  set -ef
  : "${VAULT_TOKEN:?Set VAULT_TOKEN before running this script.}"
  export VAULT_TOKEN

  ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

  # Colors are automatically disabled if output is not a terminal.
  ! [ -t 2 ] || {
    c1='\033[1;33m'
    c2='\033[1;34m'
    c3='\033[m'
  }

  read_terraform_outputs
  trap cleanup EXIT
  setup_tunnel
  wait_for_vault
  test_cluster_health
  test_secrets_engine
  test_auth_method
  test_license

  log "All smoke tests passed."
}

main "$@"
