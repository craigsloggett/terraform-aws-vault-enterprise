#!/bin/sh
# install-vault.sh
#
# Downloads, GPG-verifies, SHA256-verifies, and installs the Vault Enterprise
# binary at /usr/local/bin/vault. Runs on every node before the cluster
# bootstrap.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

TMPDIR_SESSION="$(mktemp -d)"
readonly TMPDIR_SESSION
trap 'rm -rf "${TMPDIR_SESSION}"' EXIT INT TERM HUP

detect_system_architecture() (
  machine="$(uname -m)"
  case "${machine}" in
    x86_64) printf 'amd64' ;;
    aarch64) printf 'arm64' ;;
    *)
      log_error "Unsupported architecture: ${machine}"
      return 1
      ;;
  esac
)

download_and_verify_vault() (
  version="${1}"
  arch="${2}"

  base_url="https://releases.hashicorp.com/vault/${version}"
  zip_file="vault_${version}_linux_${arch}.zip"
  sums_file="vault_${version}_SHA256SUMS"
  sig_file="vault_${version}_SHA256SUMS.sig"

  log_info "Downloading Vault Enterprise binary, sums, and signature"
  curl -fsSL -o "${TMPDIR_SESSION}/${zip_file}" "${base_url}/${zip_file}"
  curl -fsSL -o "${TMPDIR_SESSION}/${sums_file}" "${base_url}/${sums_file}"
  curl -fsSL -o "${TMPDIR_SESSION}/${sig_file}" "${base_url}/${sig_file}"

  # GPG signature verification (isolated keyring to avoid polluting the system)
  export GNUPGHOME="${TMPDIR_SESSION}/.gnupg"
  mkdir -p "${GNUPGHOME}"
  chmod 0700 "${GNUPGHOME}"

  log_info "Trusting HashiCorp PGP key"
  curl -fsSL -o "${TMPDIR_SESSION}/hashicorp.asc" \
    https://www.hashicorp.com/.well-known/pgp-key.txt
  gpg --quiet --import "${TMPDIR_SESSION}/hashicorp.asc"
  printf '%s\n' "C874011F0AB405110D02105534365D9472D7468F:6:" | gpg --quiet --import-ownertrust

  log_info "Verifying downloaded checksums"
  gpg --quiet --verify "${TMPDIR_SESSION}/${sig_file}" "${TMPDIR_SESSION}/${sums_file}"

  log_info "Verifying downloaded artifacts checksums"
  cd "${TMPDIR_SESSION}"
  sha256sum -c --ignore-missing "${sums_file}"
  cd -

  printf '%s' "${TMPDIR_SESSION}/${zip_file}"
)

main() {
  log_info "Installing Vault Enterprise ${VAULT_VERSION}"

  vault_zip_file_path="$(download_and_verify_vault "${VAULT_VERSION}" "$(detect_system_architecture)")"
  unzip -o -q "${vault_zip_file_path}" -d "${TMPDIR_SESSION}"
  install -o root -g root -m 0755 "${TMPDIR_SESSION}/vault" /usr/local/bin/vault

  log_info "Vault Enterprise ${VAULT_VERSION} installed"
}

main "${@}"
