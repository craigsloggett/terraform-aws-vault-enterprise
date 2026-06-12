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
readonly VAULT_BOOTSTRAP_TLS_VALIDITY_DAYS=2

generate_bootstrap_ca() (
  log_info "Generating an ephemeral bootstrap CA"

  openssl req -x509 \
    -newkey ec -pkeyopt ec_paramgen_curve:P-384 -nodes \
    -keyout "${TMPDIR_SESSION}/ca.key" \
    -out "${TMPDIR_SESSION}/ca.crt" \
    -days "${VAULT_BOOTSTRAP_TLS_VALIDITY_DAYS}" -sha384 \
    -subj "/CN=Vault Bootstrap CA ${INSTANCE_ID}/O=HashiCorp Vault" \
    -addext "basicConstraints=critical,CA:true" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
)

generate_bootstrap_server_certificate() (
  log_info "Generating the bootstrap server certificate"

  openssl genpkey -algorithm EC \
    -pkeyopt ec_paramgen_curve:P-384 \
    -out "${TMPDIR_SESSION}/server.key"

  openssl req -new \
    -key "${TMPDIR_SESSION}/server.key" \
    -subj "/CN=${VAULT_FQDN}/O=HashiCorp Vault" \
    -out "${TMPDIR_SESSION}/server.csr"

  # The FQDN SAN lets local clients keep validating 127.0.0.1 with
  # tls_server_name set to the FQDN, exactly as they do against the
  # PKI-issued certificate that replaces this one.
  {
    printf '%s\n' 'basicConstraints = CA:FALSE'
    printf '%s\n' 'keyUsage = critical, digitalSignature'
    printf '%s\n' 'extendedKeyUsage = serverAuth'
    printf 'subjectAltName = DNS:%s, DNS:localhost, IP:127.0.0.1, IP:%s\n' \
      "${VAULT_FQDN}" "${LOCAL_IPV4}"
  } >"${TMPDIR_SESSION}/server.ext"

  openssl x509 -req \
    -in "${TMPDIR_SESSION}/server.csr" \
    -CA "${TMPDIR_SESSION}/ca.crt" \
    -CAkey "${TMPDIR_SESSION}/ca.key" \
    -CAcreateserial \
    -days "${VAULT_BOOTSTRAP_TLS_VALIDITY_DAYS}" -sha384 \
    -extfile "${TMPDIR_SESSION}/server.ext" \
    -out "${TMPDIR_SESSION}/server.crt"
)

destroy_bootstrap_ca_key() (
  log_info "Destroying the ephemeral bootstrap CA private key"

  if command -v shred >/dev/null 2>&1; then
    shred -u "${TMPDIR_SESSION}/ca.key"
  else
    rm -f "${TMPDIR_SESSION}/ca.key"
  fi
)

install_bootstrap_tls_materials() (
  log_info "Installing TLS materials to: ${VAULT_TLS_DIR}"

  # Each stage lives in VAULT_TLS_DIR so the final mv is an atomic
  # same-filesystem rename, which puts it outside the session tempdir the
  # top-level trap clears; this subshell's own trap removes a leaked stage.
  staged_file=""
  trap 'rm -f "${staged_file}"' EXIT INT TERM HUP

  staged_file="$(mktemp "${VAULT_TLS_DIR}/.XXXXXXXX")"
  install -o vault -g vault -m 0644 -T "${TMPDIR_SESSION}/ca.crt" "${staged_file}"
  mv "${staged_file}" "${VAULT_TLS_CA_FILE}"

  staged_file="$(mktemp "${VAULT_TLS_DIR}/.XXXXXXXX")"
  install -o vault -g vault -m 0640 -T "${TMPDIR_SESSION}/server.crt" "${staged_file}"
  mv "${staged_file}" "${VAULT_TLS_CERT_FILE}"

  staged_file="$(mktemp "${VAULT_TLS_DIR}/.XXXXXXXX")"
  install -o vault -g vault -m 0640 -T "${TMPDIR_SESSION}/server.key" "${staged_file}"
  mv "${staged_file}" "${VAULT_TLS_KEY_FILE}"
)

publish_bootstrap_ca_certificate() (
  log_info "Publishing the bootstrap CA certificate to SSM parameter: ${BOOTSTRAP_TLS_CA_CERTIFICATE_SSM_PARAMETER_NAME}"

  put_parameter "${BOOTSTRAP_TLS_CA_CERTIFICATE_SSM_PARAMETER_NAME}" \
    "$(cat "${TMPDIR_SESSION}/ca.crt")"
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
  # A node with TLS materials already in place has been provisioned; do not
  # regenerate. A forced cloud-init re-run after Vault PKI issued the
  # long-term certificate would otherwise clobber it with an ephemeral one.
  if [ -e "${VAULT_TLS_CERT_FILE}" ]; then
    log_info "TLS materials already present in ${VAULT_TLS_DIR}, skipping bootstrap generation"
    return 0
  fi

  command -v openssl >/dev/null 2>&1 ||
    {
      log_error "openssl is required but not installed"
      return 1
    }

  TMPDIR_SESSION="$(mktemp -d)"
  readonly TMPDIR_SESSION
  trap 'rm -rf "${TMPDIR_SESSION}"' EXIT INT TERM HUP

  generate_bootstrap_ca
  generate_bootstrap_server_certificate
  destroy_bootstrap_ca_key
  install_bootstrap_tls_materials

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
