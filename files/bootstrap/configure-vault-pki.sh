#!/bin/sh
# configure-vault-pki.sh
#
# Cnfigure the Vault PKI secrets engine with an externally signed intermediate
# CA, creates the vault-server PKI role, writes the vault-server policy,
# publishes the PKI managed TLS CA bundle to SSM, and marks pki_state=Ready.
# Follower nodes wait for pki_state=Ready before returning.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_POLICY_DIR="/etc/vault.d/policies"

TMPDIR_SESSION="$(mktemp -d)"
readonly TMPDIR_SESSION
trap 'rm -rf "${TMPDIR_SESSION}"' EXIT INT TERM HUP

enable_vault_pki_secrets_engine() (
  log_info "Enabling the Vault PKI secrets engine at: ${VAULT_PKI_MOUNT_PATH}/"

  if ! vault secrets list -format=json | jq -e --arg path "${VAULT_PKI_MOUNT_PATH}/" '.[$path]' >/dev/null 2>&1; then
    vault secrets enable -path="${VAULT_PKI_MOUNT_PATH}" -description="issues TLS leaf certificates for Vault cluster nodes" pki
  fi

  vault secrets tune -max-lease-ttl="${VAULT_PKI_VAULT_MOUNT_MAX_TTL}" "${VAULT_PKI_MOUNT_PATH}" >/dev/null
)

configure_vault_pki_urls() (
  log_info "Configuring Vault PKI URLs"

  config_urls_payload="$(
    jq -nc \
      --arg vault_fqdn "${VAULT_FQDN}" \
      --arg vault_pki_mount_path "${VAULT_PKI_MOUNT_PATH}" \
      '{
        issuing_certificates: "https://\($vault_fqdn):8200/v1/\($vault_pki_mount_path)/ca",
        crl_distribution_points: "https://\($vault_fqdn):8200/v1/\($vault_pki_mount_path)/crl",
        ocsp_servers: "https://\($vault_fqdn):8200/v1/\($vault_pki_mount_path)/ocsp"
      }'
  )"

  vault write "${VAULT_PKI_MOUNT_PATH}/config/urls" - >/dev/null <<EOF
"${config_urls_payload}"
EOF
)

generate_vault_pki_intermediate_ca() (
  intermediate_generate_internal_response_file="$1"

  log_info "Generating the Vault PKI intermediate CA"

  intermediate_generate_internal_payload="$(
    jq -nc \
      --arg common_name "${VAULT_PKI_INTERMEDIATE_CA_COMMON_NAME}" \
      --arg country "${VAULT_PKI_INTERMEDIATE_CA_COUNTRY}" \
      --arg organization "${VAULT_PKI_INTERMEDIATE_CA_ORGANIZATION}" \
      --arg key_type "${VAULT_PKI_INTERMEDIATE_CA_KEY_TYPE}" \
      --argjson key_bits "${VAULT_PKI_INTERMEDIATE_CA_KEY_BITS}" \
      '{
        common_name: $common_name,
        country: $country,
        organization: $organization,
        key_type: $key_type,
        key_bits: $key_bits
      }'
  )"

  vault write -format=json "${VAULT_PKI_MOUNT_PATH}/intermediate/generate/internal" - \
    >"${intermediate_generate_internal_response_file}" <<EOF
${intermediate_generate_internal_payload}
EOF
)

extract_vault_pki_intermediate_ca_csr() (
  intermediate_generate_internal_response_file="$1"

  jq -r '.data.csr' <"${intermediate_generate_internal_response_file}"
)

publish_vault_pki_intermediate_ca_csr() (
  vault_pki_intermediate_ca_csr="$1"

  log_info "Publishing the Vault PKI intermediate CA CSR to SSM parameter: ${VAULT_PKI_INTERMEDIATE_CA_CSR_SSM_PARAMETER_NAME}"

  put_parameter "${VAULT_PKI_INTERMEDIATE_CA_CSR_SSM_PARAMETER_NAME}" "${vault_pki_intermediate_ca_csr}"
)

signed_vault_pki_intermediate_ca_available() (
  signed_vault_pki_intermediate_ca="$(
    fetch_secret_no_retry "${VAULT_PKI_SIGNED_INTERMEDIATE_CA_SECRET_ARN}"
  )" ||
    return 1

  [ -n "${signed_vault_pki_intermediate_ca}" ] ||
    return 1

  return 0
)

await_signed_vault_pki_intermediate_ca() (
  log_info "Waiting for the signed Vault PKI intermediate CA"

  timeout_seconds="${VAULT_PKI_SIGNED_INTERMEDIATE_WAIT_TIMEOUT_SECONDS}"
  retry_for "${timeout_seconds}" signed_vault_pki_intermediate_ca_available ||
    {
      log_error "Signed intermediate CA not available after ${timeout_seconds}s"
      return 1
    }
)

write_signed_vault_pki_intermediate_ca_file() (
  signed_vault_pki_intermediate_ca_file="$1"

  fetch_secret "${VAULT_PKI_SIGNED_INTERMEDIATE_CA_SECRET_ARN}" \
    >"${signed_vault_pki_intermediate_ca_file}"
)

validate_signed_vault_pki_intermediate_ca() (
  signed_vault_pki_intermediate_ca_file="$1"

  log_info "Validating the signed Vault PKI intermediate CA"

  if jq -e 'has("private_key")' <"${signed_vault_pki_intermediate_ca_file}" >/dev/null 2>&1; then
    log_error "Signed Vault PKI intermediate CA contains a private_key field, aborting"
    return 1
  fi

  for field in signed_intermediate_ca_pem ca_chain_pem; do
    value="$(
      jq -r --arg field "${field}" '.[$field] // empty' \
        <"${signed_vault_pki_intermediate_ca_file}"
    )"
    if [ -z "${value}" ]; then
      log_error "${field} field is missing or empty in: ${VAULT_PKI_SIGNED_INTERMEDIATE_CA_SECRET_ARN}"
      return 1
    fi
  done
)

import_signed_vault_pki_intermediate_ca() (
  signed_vault_pki_intermediate_ca_file="$1"

  log_info "Importing the signed Vault PKI intermediate CA"

  intermediate_ca_set_signed_payload="$(
    jq -c '{certificate: (.signed_intermediate_ca_pem + "\n" + .ca_chain_pem)}' \
      <"${signed_vault_pki_intermediate_ca_file}"
  )"

  intermediate_set_signed_response_file="${TMPDIR_SESSION}/intermediate_set_signed_response.json"

  vault write -format=json "${VAULT_PKI_MOUNT_PATH}/intermediate/set-signed" - \
    >"${intermediate_set_signed_response_file}" <<EOF
${intermediate_ca_set_signed_payload}
EOF

  signed_vault_pki_intermediate_ca_issuer="$(
    jq -r '.data.mapping | to_entries[] | select(.value != "") | .key' \
      <"${intermediate_set_signed_response_file}"
  )"

  vault write "${VAULT_PKI_MOUNT_PATH}/config/issuers" \
    default="${signed_vault_pki_intermediate_ca_issuer}" >/dev/null
)

configure_vault_pki_role() (
  log_info "Configuring the Vault PKI role: vault-server"

  roles_vault_server_payload="$(
    jq -nc \
      --arg allowed_domains "${VAULT_FQDN}" \
      --arg country "${VAULT_PKI_INTERMEDIATE_CA_COUNTRY}" \
      --arg organization "${VAULT_PKI_INTERMEDIATE_CA_ORGANIZATION}" \
      --arg max_ttl "${VAULT_PKI_VAULT_SERVER_ROLE_MAX_TTL}" \
      '{
        allowed_domains: $allowed_domains,
        allow_bare_domains: true,
        allow_subdomains: false,
        allow_localhost: false,
        allow_ip_sans: false,
        country: [$country],
        organization: [$organization],
        ext_key_usage: ["serverAuth"],
        key_type: "ec",
        key_bits: 384,
        max_ttl: $max_ttl,
        not_before_duration: "0s"
      }'
  )"

  vault write "${VAULT_PKI_MOUNT_PATH}/roles/vault-server" - >/dev/null <<EOF
"${roles_vault_server_payload}"
EOF

  vault policy write vault-server "${VAULT_POLICY_DIR}/vault-server.hcl"
)

publish_vault_pki_ca_chain() (
  log_info "Publishing the Vault PKI CA chain to SSM parameter: ${VAULT_PKI_CA_CHAIN_SSM_PARAMETER_NAME}"

  vault_pki_ca_chain="$(
    vault read -format=json "${VAULT_PKI_MOUNT_PATH}/issuer/default/json" |
      jq -r '[.data.ca_chain[] | rtrimstr("\n")] | join("\n")'
  )"

  put_parameter "${VAULT_PKI_CA_CHAIN_SSM_PARAMETER_NAME}" "${vault_pki_ca_chain}"
)

publish_vault_pki_state() (
  log_info "Publishing Vault PKI state to SSM parameter: ${BOOTSTRAP_VAULT_PKI_STATE_SSM_PARAMETER_NAME}"

  put_parameter "${BOOTSTRAP_VAULT_PKI_STATE_SSM_PARAMETER_NAME}" "Ready"
)

vault_pki_ready() (
  vault_pki_state="$(fetch_parameter "${BOOTSTRAP_VAULT_PKI_STATE_SSM_PARAMETER_NAME}")" ||
    return 1

  [ "${vault_pki_state}" = "Ready" ] ||
    return 1

  return 0
)

await_vault_pki_ready() (
  log_info "Waiting for the bootstrap node to finish Vault PKI setup"

  timeout_seconds=1200
  retry_for "${timeout_seconds}" vault_pki_ready ||
    {
      log_error "Vault PKI not ready after ${timeout_seconds}s"
      return 1
    }
)

main() {
  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"

  bootstrap_instance_id="$(fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER_NAME}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_instance_id}" ]; then
    await_vault_pki_ready
    return 0
  fi

  VAULT_TOKEN="$(fetch_secret "${ROOT_TOKEN_SECRET_ARN}")"
  export VAULT_TOKEN

  enable_vault_pki_secrets_engine
  configure_vault_pki_urls

  intermediate_generate_internal_response_file="${TMPDIR_SESSION}/intermediate_generate_internal_response.json"
  generate_vault_pki_intermediate_ca "${intermediate_generate_internal_response_file}"
  publish_vault_pki_intermediate_ca_csr "$(
    extract_vault_pki_intermediate_ca_csr "${intermediate_generate_internal_response_file}"
  )"

  await_signed_vault_pki_intermediate_ca

  signed_vault_pki_intermediate_ca_file="${TMPDIR_SESSION}/signed_vault_pki_intermediate_ca.json"
  write_signed_vault_pki_intermediate_ca_file "${signed_vault_pki_intermediate_ca_file}"
  validate_signed_vault_pki_intermediate_ca "${signed_vault_pki_intermediate_ca_file}"
  import_signed_vault_pki_intermediate_ca "${signed_vault_pki_intermediate_ca_file}"

  configure_vault_pki_role
  publish_vault_pki_ca_chain
  publish_vault_pki_state

  # TODO: vault token revoke -self >/dev/null 2>&1 || log_error "Failed to revoke root token"
}

main "$@"
