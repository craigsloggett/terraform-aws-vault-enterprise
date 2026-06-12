#!/bin/sh
# write-vault-bootstrap-tls-materials.sh
#
# Generates ephemeral TLS materials with openssl so Vault can start with a
# valid listener certificate before Vault PKI issues the permanent one. Every
# node signs its own server certificate with a throwaway local CA whose
# private key is destroyed immediately after signing. The elected bootstrap
# node publishes its CA certificate (public material) to SSM so followers can
# validate the leader's listener during raft join. A replacement node joining
# a cluster whose listeners already serve PKI-signed certificates appends the
# Vault PKI CA chain published to SSM by the bootstrap node instead.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_TLS_DIR="/opt/vault/tls"
readonly VAULT_TLS_CA_FILE="${VAULT_TLS_DIR}/ca.crt"
readonly VAULT_TLS_CERT_FILE="${VAULT_TLS_DIR}/server.crt"
readonly VAULT_TLS_KEY_FILE="${VAULT_TLS_DIR}/server.key"
readonly TLS_VALIDITY_DAYS=2

generate_bootstrap_ca() (
  log_info "Generating an ephemeral bootstrap CA"

  openssl req -x509 \
    -newkey ec -pkeyopt ec_paramgen_curve:P-384 -nodes \
    -keyout "${TLS_WORKSPACE}/ca.key" \
    -out "${TLS_WORKSPACE}/ca.crt" \
    -days "${TLS_VALIDITY_DAYS}" -sha384 \
    -subj "/CN=Vault Bootstrap CA/O=HashiCorp Vault" \
    -addext "basicConstraints=critical,CA:true" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
)

generate_server_certificate() (
  log_info "Generating the bootstrap server certificate"

  openssl genpkey -algorithm EC \
    -pkeyopt ec_paramgen_curve:P-384 \
    -out "${TLS_WORKSPACE}/server.key"

  openssl req -new \
    -key "${TLS_WORKSPACE}/server.key" \
    -subj "/CN=${VAULT_FQDN}/O=HashiCorp Vault" \
    -out "${TLS_WORKSPACE}/server.csr"

  # The FQDN SAN lets local clients keep validating 127.0.0.1 with
  # tls_server_name set to the FQDN, exactly as they do against the
  # PKI-issued certificate that replaces this one.
  {
    printf '%s\n' 'basicConstraints = CA:FALSE'
    printf '%s\n' 'keyUsage = critical, digitalSignature'
    printf '%s\n' 'extendedKeyUsage = serverAuth'
    printf 'subjectAltName = DNS:%s, DNS:localhost, IP:127.0.0.1, IP:%s\n' \
      "${VAULT_FQDN}" "${LOCAL_IPV4}"
  } >"${TLS_WORKSPACE}/server.ext"

  openssl x509 -req \
    -in "${TLS_WORKSPACE}/server.csr" \
    -CA "${TLS_WORKSPACE}/ca.crt" \
    -CAkey "${TLS_WORKSPACE}/ca.key" \
    -CAcreateserial \
    -days "${TLS_VALIDITY_DAYS}" -sha384 \
    -extfile "${TLS_WORKSPACE}/server.ext" \
    -out "${TLS_WORKSPACE}/server.crt"
)

destroy_bootstrap_ca_key() (
  log_info "Destroying the ephemeral bootstrap CA private key"

  if command -v shred >/dev/null 2>&1; then
    shred -u "${TLS_WORKSPACE}/ca.key"
  else
    rm -f "${TLS_WORKSPACE}/ca.key"
  fi
)

install_tls_material() (
  source_file="${1:?source file is required}"
  target_file="${2:?target file is required}"
  mode="${3:?mode is required}"

  staged_file="$(mktemp "${VAULT_TLS_DIR}/.XXXXXXXX")"
  install -o vault -g vault -m "${mode}" -T "${source_file}" "${staged_file}"
  mv "${staged_file}" "${target_file}"
)

install_tls_materials() (
  log_info "Installing TLS materials to: ${VAULT_TLS_DIR}"

  install_tls_material "${TLS_WORKSPACE}/ca.crt" "${VAULT_TLS_CA_FILE}" 0644
  install_tls_material "${TLS_WORKSPACE}/server.crt" "${VAULT_TLS_CERT_FILE}" 0640
  install_tls_material "${TLS_WORKSPACE}/server.key" "${VAULT_TLS_KEY_FILE}" 0640
)

publish_bootstrap_ca_certificate() (
  log_info "Publishing the bootstrap CA certificate to SSM parameter: ${BOOTSTRAP_TLS_CA_CERTIFICATE_SSM_PARAMETER_NAME}"

  put_parameter "${BOOTSTRAP_TLS_CA_CERTIFICATE_SSM_PARAMETER_NAME}" \
    "$(cat "${TLS_WORKSPACE}/ca.crt")"
)

bootstrap_ca_certificate_published() (
  bootstrap_ca_certificate="$(
    fetch_parameter "${BOOTSTRAP_TLS_CA_CERTIFICATE_SSM_PARAMETER_NAME}" 2>/dev/null
  )" ||
    return 1

  [ -n "${bootstrap_ca_certificate}" ] ||
    return 1

  [ "${bootstrap_ca_certificate}" != "Uninitialized" ] ||
    return 1

  return 0
)

await_bootstrap_ca_certificate() (
  log_info "Waiting for the bootstrap CA certificate to be published to SSM"

  timeout_seconds=1200
  retry_for "${timeout_seconds}" bootstrap_ca_certificate_published ||
    {
      log_error "Bootstrap CA certificate not published after ${timeout_seconds}s"
      return 1
    }
)

append_bootstrap_ca_certificate() (
  log_info "Appending the bootstrap node CA certificate to: ${VAULT_TLS_CA_FILE}"

  fetch_parameter "${BOOTSTRAP_TLS_CA_CERTIFICATE_SSM_PARAMETER_NAME}" >>"${VAULT_TLS_CA_FILE}"
)

append_vault_pki_ca_chain() (
  log_info "Appending the Vault PKI CA chain to: ${VAULT_TLS_CA_FILE}"

  fetch_parameter "${VAULT_PKI_CA_CHAIN_SSM_PARAMETER_NAME}" >>"${VAULT_TLS_CA_FILE}"
)

main() {
  command -v openssl >/dev/null 2>&1 ||
    {
      log_error "openssl is required but not installed"
      return 1
    }

  TLS_WORKSPACE="$(mktemp -d)"
  readonly TLS_WORKSPACE
  trap 'rm -rf "${TLS_WORKSPACE}"' EXIT INT TERM HUP

  generate_bootstrap_ca
  generate_server_certificate
  destroy_bootstrap_ca_key
  install_tls_materials

  vault_cluster_state="$(
    fetch_parameter "${BOOTSTRAP_VAULT_CLUSTER_STATE_SSM_PARAMETER_NAME}" 2>/dev/null
  )" ||
    vault_cluster_state=""

  vault_pki_state="$(
    fetch_parameter "${BOOTSTRAP_VAULT_PKI_STATE_SSM_PARAMETER_NAME}" 2>/dev/null
  )" ||
    vault_pki_state=""

  case "${vault_cluster_state}:${vault_pki_state}" in
    Ready:Ready)
      append_vault_pki_ca_chain
      ;;
    Ready:*)
      # The cluster initialized, so the bootstrap node already published its
      # CA certificate; until PKI-issued certificates replace the bootstrap
      # materials, the bootstrap node's listener is the only one a raft join
      # can validate, and it is also the raft leader.
      await_bootstrap_ca_certificate
      append_bootstrap_ca_certificate
      ;;
    *:Ready)
      log_error "Corrupt SSM state: pki/state=Ready but cluster/state='${vault_cluster_state}'"
      return 1
      ;;
    *)
      bootstrap_instance_id="$(fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER_NAME}")"

      if [ "${INSTANCE_ID}" = "${bootstrap_instance_id}" ]; then
        publish_bootstrap_ca_certificate
      else
        await_bootstrap_ca_certificate
        append_bootstrap_ca_certificate
      fi
      ;;
  esac
}

main "$@"
