# shellcheck shell=sh
# write-tls-materials.sh — Write bootstrap TLS certificates to disk.

write_tls_materials() {
  vault_tls_ca_file="${1}"
  vault_tls_cert_file="${2}"
  vault_tls_key_file="${3}"

  ca_cert="$(get_bootstrap_root_ca)"
  server_cert="$(get_bootstrap_tls_cert)"
  server_key="$(get_bootstrap_tls_key)"

  log_info "Writing bootstrap TLS certificates"
  printf '%s\n' "${ca_cert}" >"${vault_tls_ca_file}"
  printf '%s\n' "${server_cert}" >"${vault_tls_cert_file}"
  printf '%s\n' "${server_key}" >"${vault_tls_key_file}"

  chown vault:vault "${vault_tls_ca_file}" "${vault_tls_cert_file}" "${vault_tls_key_file}"
  chmod 0640 "${vault_tls_cert_file}" "${vault_tls_key_file}"
  chmod 0644 "${vault_tls_ca_file}"
}
