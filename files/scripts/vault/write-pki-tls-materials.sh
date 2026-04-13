# shellcheck shell=sh
# write-pki-tls-materials.sh — Replace bootstrap TLS with PKI-issued certificates.

write_pki_ca_cert() {
  vault_tls_ca_file="${1}"
  vault_tls_dir="${2}"
  ssm_pki_ca_cert_name="${3}"

  log_info "Replacing bootstrap CA cert with PKI CA cert on disk"

  # Fetch the PKI CA cert from SSM. This was written by configure_pki_engine()
  # on the bootstrap node and is available to all nodes without a Vault token.
  pki_ca_cert="$(aws ssm get-parameter \
    --name "${ssm_pki_ca_cert_name}" \
    --query "Parameter.Value" \
    --output text)"

  # Overwrite the bootstrap CA cert at vault_tls_ca_file. vault.hcl references this
  # path for leader_ca_cert_file in the retry_join block, it must now trust
  # the PKI CA, not the bootstrap CA.
  printf '%s\n' "${pki_ca_cert}" >"${vault_tls_ca_file}"
  chown vault:vault "${vault_tls_ca_file}"
  chmod 0644 "${vault_tls_ca_file}"

  log_info "Bootstrap CA cert replaced with PKI CA cert at ${vault_tls_ca_file}"

  # Remove the temporary PKI CA cert file written by the follower path in
  # issue_node_cert(), if present.
  pki_ca_tmp="${vault_tls_dir}/pki-ca.crt"
  if [ -f "${pki_ca_tmp}" ]; then
    rm -f "${pki_ca_tmp}"
    log_info "Removed temporary PKI CA cert file ${pki_ca_tmp}"
  fi
}
