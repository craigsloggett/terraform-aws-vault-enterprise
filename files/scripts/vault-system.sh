# shellcheck shell=sh disable=SC2154
# vault-system.sh — Vault OS user and directory tree setup.
#
# Requires globals: vault_home_dir, vault_data_dir, vault_config_dir,
#   vault_log_dir, vault_libexec_dir, vault_tls_dir, vault_raft_dir,
#   vault_agent_template_dir

create_vault_user() {
  log_info "Creating vault system user"

  groupadd --system vault
  useradd --system -g vault -d "${vault_home_dir}" -s /bin/false vault
}

configure_vault_directories() {
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
