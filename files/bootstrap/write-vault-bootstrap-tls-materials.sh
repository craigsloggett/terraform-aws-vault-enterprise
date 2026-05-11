#!/bin/sh
# write-vault-bootstrap-tls-materials.sh
#
# Writes the bootstrap CA, server certificate, and private key from Secrets
# Manager to /opt/vault/tls so vault.service can start. Runs on every node
# before vault.service starts. When the cluster is already Ready and PKI is
# managed, appends the PKI CA bundle so outbound calls to existing nodes
# trust their PKI-signed listener certs while local CLI calls keep trusting
# the bootstrap cert until reload_vault_listener swaps it.

set -euf

# shellcheck source=/dev/null
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=/dev/null
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_TLS_CA_FILE="/opt/vault/tls/ca.crt"
readonly VAULT_TLS_CERT_FILE="/opt/vault/tls/server.crt"
readonly VAULT_TLS_KEY_FILE="/opt/vault/tls/server.key"

write_ca_file() (
  cluster_state="${1}"
  pki_state="${2}"

  case "${cluster_state}" in
    "" | Uninitialized)
      if [ "${pki_state}" = "Ready" ]; then
        log_error "Corrupt SSM state: pki/state=Ready but cluster/state=Uninitialized"
        return 1
      fi
      log_info "Writing bootstrap TLS CA file"
      fetch_secret "${BOOTSTRAP_TLS_CA_SECRET_ARN}" >"${VAULT_TLS_CA_FILE}"
      ;;
    Ready)
      if [ "${pki_state}" = "Ready" ]; then
        log_info "PKI state is Ready: Writing combined PKI and bootstrap TLS CA bundle"
        # PKI CA for outbound connections to existing nodes, bootstrap CA for
        # local vault CLI calls until reload_vault_listener replaces the
        # bootstrap cert with a PKI-signed one.
        {
          fetch_parameter "${VAULT_PKI_INTERMEDIATE_CA_SSM_PARAMETER_NAME}"
          fetch_secret "${BOOTSTRAP_TLS_CA_SECRET_ARN}"
        } >"${VAULT_TLS_CA_FILE}"
      else
        log_info "Writing bootstrap TLS CA file"
        fetch_secret "${BOOTSTRAP_TLS_CA_SECRET_ARN}" >"${VAULT_TLS_CA_FILE}"
      fi
      ;;
    *)
      log_error "Unsupported cluster state: '${cluster_state}'"
      return 1
      ;;
  esac
)

main() {
  cluster_state="$(fetch_parameter "${BOOTSTRAP_CLUSTER_STATE_NAME}" 2>/dev/null)" || cluster_state=""
  pki_state="$(fetch_parameter "${BOOTSTRAP_PKI_STATE_NAME}" 2>/dev/null)" || pki_state=""

  write_ca_file "${cluster_state}" "${pki_state}"

  log_info "Writing bootstrap TLS certificate and private key"
  fetch_secret "${BOOTSTRAP_TLS_CERT_SECRET_ARN}" >"${VAULT_TLS_CERT_FILE}"
  fetch_secret "${BOOTSTRAP_TLS_PRIVATE_KEY_SECRET_ARN}" >"${VAULT_TLS_KEY_FILE}"

  chown vault:vault "${VAULT_TLS_CA_FILE}" "${VAULT_TLS_CERT_FILE}" "${VAULT_TLS_KEY_FILE}"
  chmod 0644 "${VAULT_TLS_CA_FILE}"
  chmod 0640 "${VAULT_TLS_CERT_FILE}" "${VAULT_TLS_KEY_FILE}"
}

main "${@}"
