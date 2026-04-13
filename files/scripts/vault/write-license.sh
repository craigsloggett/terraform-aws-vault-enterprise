# shellcheck shell=sh
# write-license.sh — Write the Vault Enterprise license to disk.

write_vault_license() {
  vault_license_file="${1}"

  vault_license="$(get_license)"

  log_info "Writing the Vault license"
  printf '%s\n' "${vault_license}" >"${vault_license_file}"
  chown vault:vault "${vault_license_file}"
  chmod 0640 "${vault_license_file}"
}
