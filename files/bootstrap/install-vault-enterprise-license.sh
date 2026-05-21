#!/bin/sh
# install-vault-enterprise-license.sh
#
# Fetches the Vault Enterprise license from Secrets Manager and writes it
# to /opt/vault/vault.hclic. Runs on every node before vault.service starts.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

readonly VAULT_HOME_DIR="/opt/vault"

TMPDIR_SESSION="$(mktemp -d)"
readonly TMPDIR_SESSION
trap 'rm -rf "${TMPDIR_SESSION}"' EXIT INT TERM HUP

install_vault_enterprise_license() (
  log_info "Installing the Vault Enterprise license"

  tmp_vault_enterprise_license_file="${TMPDIR_SESSION}/vault.hclic"
  printf '%s' "$(fetch_secret "${LICENSE_SECRET_ARN}")" >"${tmp_vault_enterprise_license_file}"

  install -o vault -g vault -m 0640 "${tmp_vault_enterprise_license_file}" "${VAULT_HOME_DIR}/vault.hclic"
)

main() {
  install_vault_enterprise_license
}

main "$@"
