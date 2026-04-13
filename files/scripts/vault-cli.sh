# shellcheck shell=sh disable=SC2154
# vault-cli.sh — Vault CLI environment configuration.
#
# Requires globals: vault_fqdn, vault_tls_ca_file

write_vault_cli_config() {
  log_info "Writing Vault CLI environment to /etc/profile.d/99-vault-cli-config.sh"

  cat >/etc/profile.d/99-vault-cli-config.sh <<EOF
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TLS_SERVER_NAME="${vault_fqdn}"
export VAULT_CACERT="${vault_tls_ca_file}"
EOF
}
