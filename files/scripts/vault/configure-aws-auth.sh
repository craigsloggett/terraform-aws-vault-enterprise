# shellcheck shell=sh
# configure-aws-auth.sh — AWS auth method configuration.
#
# These functions run only on the bootstrap node after cluster init.

enable_aws_auth() {
  log_info "Enabling Vault AWS auth method"

  if ! vault auth list -format=json | jq -e '."aws/"' >/dev/null 2>&1; then
    vault auth enable aws
  fi

  log_info "AWS auth method enabled"
}

configure_vault_server_role_policy() {
  log_info "Writing vault-server policy"

  vault policy write vault-server - <<EOF
path "pki/issue/vault-server" {
  capabilities = ["create", "update"]
}
EOF

  log_info "vault-server policy written"
}

write_pki_state_ready() {
  ssm_pki_state_name="${1}"

  log_info "Writing PKI state: ready"

  aws ssm put-parameter \
    --name "${ssm_pki_state_name}" \
    --value "ready" \
    --overwrite
}
