# shellcheck shell=sh
# configure-bootstrap-tls.sh — Per-node TLS certificate issuance and rotation.

wait_for_pki_ready() {
  ssm_pki_state_name="${1}"

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    state="$(aws ssm get-parameter \
      --name "${ssm_pki_state_name}" \
      --query "Parameter.Value" \
      --output text 2>/dev/null)" || true

    if [ "${state}" = "ready" ]; then
      return 0
    fi
    sleep 5
  done

  log_error "Vault PKI was not ready after ${attempt} attempts, failing bootstrap"
  return 1
}

issue_node_cert() {
  vault_fqdn="${1}"
  vault_tls_dir="${2}"
  vault_tls_cert_file="${3}"
  vault_tls_key_file="${4}"
  vault_pki_server_cert_ttl="${5}"
  ssm_pki_ca_cert_name="${6}"

  log_info "Issuing PKI-signed TLS certificate for this node"

  # Follower nodes need to fetch the new CA cert from SSM and authenticate
  # via the AWS IAM auth method. The bootstrap node already has VAULT_TOKEN
  # set from main().
  if [ -z "${VAULT_TOKEN:-}" ]; then
    new_ca_cert="$(aws ssm get-parameter \
      --name "${ssm_pki_ca_cert_name}" \
      --query "Parameter.Value" \
      --output text)"

    # Write the new PKI CA cert to disk for use by clients connecting
    # to this node after the TLS swap in reload_vault_tls(). It is not
    # used for Vault API calls here, this node's listener is still
    # presenting the bootstrap cert until the SIGHUP, so VAULT_CACERT
    # must continue to point at the bootstrap CA.
    new_ca_cert_file="${vault_tls_dir}/pki-ca.crt"
    printf '%s\n' "${new_ca_cert}" >"${new_ca_cert_file}"
    chown vault:vault "${new_ca_cert_file}"
    chmod 0644 "${new_ca_cert_file}"

    log_info "Authenticating via AWS IAM auth method"
    vault_token="$(vault login \
      -format=json \
      -method=aws \
      role=vault-server |
      jq -r '.auth.client_token')"
    export VAULT_TOKEN="${vault_token}"
  fi

  log_info "Requesting certificate from PKI engine"
  cert_json="$(vault write -format=json pki/issue/vault-server \
    common_name="${vault_fqdn}" \
    ttl="${vault_pki_server_cert_ttl}")"

  tmp_cert="${vault_tls_dir}/server.crt.tmp"
  tmp_key="${vault_tls_dir}/server.key.tmp"

  printf '%s\n' "$(printf '%s' "${cert_json}" | jq -r '.data.certificate')" \
    >"${tmp_cert}"
  printf '%s\n' "$(printf '%s' "${cert_json}" | jq -r '.data.private_key')" \
    >"${tmp_key}"

  chown vault:vault "${tmp_cert}" "${tmp_key}"
  chmod 0640 "${tmp_cert}" "${tmp_key}"

  # Atomic move to final paths (vault.hcl already references these).
  mv "${tmp_cert}" "${vault_tls_cert_file}"
  mv "${tmp_key}" "${vault_tls_key_file}"

  log_info "PKI-signed certificate written to ${vault_tls_cert_file}"
}

reload_vault_tls() {
  log_info "Reloading Vault TLS listener with PKI-signed certificate"

  systemctl kill -s HUP vault

  log_info "Vault TLS listener reloaded"
}
