# shellcheck shell=sh
# configure-linux.sh — Vault OS user, directory tree, and CLI environment setup.

create_vault_user() {
  vault_home_dir="${1}"

  log_info "Creating vault system user"

  groupadd --system vault
  useradd --system -g vault -d "${vault_home_dir}" -s /bin/false vault
}

configure_vault_directories() {
  vault_home_dir="${1}"
  vault_data_dir="${2}"
  vault_config_dir="${3}"
  vault_log_dir="${4}"
  vault_libexec_dir="${5}"
  vault_tls_dir="${6}"
  vault_raft_dir="${7}"
  vault_agent_template_dir="${8}"

  log_info "Configuring Vault directory tree"

  mkdir -p "${vault_home_dir}"
  chown vault:vault "${vault_home_dir}"
  chmod 755 "${vault_home_dir}"

  mkdir -p "${vault_data_dir}"
  chown vault:vault "${vault_data_dir}"
  chmod 755 "${vault_data_dir}"

  mkdir -p "${vault_config_dir}"
  chown root:vault "${vault_config_dir}"
  chmod 755 "${vault_config_dir}"

  mkdir -p "${vault_log_dir}"
  chown vault:vault "${vault_log_dir}"
  chmod 755 "${vault_log_dir}"

  mkdir -p "${vault_libexec_dir}"
  chown root:root "${vault_libexec_dir}"
  chmod 755 "${vault_libexec_dir}"

  mkdir -p "${vault_tls_dir}"
  chown vault:vault "${vault_tls_dir}"
  chmod 755 "${vault_tls_dir}"

  mkdir -p "${vault_raft_dir}"
  chown vault:vault "${vault_raft_dir}"
  chmod 700 "${vault_raft_dir}"

  mkdir -p "${vault_agent_template_dir}"
  chown vault:vault "${vault_agent_template_dir}"
  chmod 755 "${vault_agent_template_dir}"
}

write_vault_cli_config() {
  vault_fqdn="${1}"
  vault_tls_ca_file="${2}"

  log_info "Writing Vault CLI environment to /etc/profile.d/99-vault-cli-config.sh"

  cat >/etc/profile.d/99-vault-cli-config.sh <<EOF
export VAULT_ADDR="https://127.0.0.1:8200"
export VAULT_TLS_SERVER_NAME="${vault_fqdn}"
export VAULT_CACERT="${vault_tls_ca_file}"
EOF
}
