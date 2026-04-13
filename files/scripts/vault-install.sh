# shellcheck shell=sh
# vault-install.sh — Vault binary installation and service lifecycle.

install_vault() {
  version="${1}"

  log_info "Installing Vault Enterprise ${version}"

  apt-get -yq install gnupg >/dev/null

  # Detect architecture
  machine="$(uname -m)"
  case "${machine}" in
    x86_64) arch="amd64" ;;
    aarch64) arch="arm64" ;;
    *)
      log_error "Unsupported architecture: ${machine}"
      return 1
      ;;
  esac
  log_info "Detected architecture: ${arch}" >&2

  base_url="https://releases.hashicorp.com/vault/${version}"
  zip_file="vault_${version}_linux_${arch}.zip"
  sums_file="vault_${version}_SHA256SUMS"
  sig_file="vault_${version}_SHA256SUMS.sig"

  # Download release artifacts into an isolated temp directory
  tmp_dir="$(mktemp -d)"
  trap 'rm -rf "${tmp_dir}"' EXIT

  curl -fsSL -o "${tmp_dir}/${zip_file}" "${base_url}/${zip_file}"
  curl -fsSL -o "${tmp_dir}/${sums_file}" "${base_url}/${sums_file}"
  curl -fsSL -o "${tmp_dir}/${sig_file}" "${base_url}/${sig_file}"

  # GPG signature verification (isolated keyring to avoid polluting the system)
  export GNUPGHOME="${tmp_dir}/.gnupg"
  mkdir -p "${GNUPGHOME}"
  chmod 0700 "${GNUPGHOME}"

  curl -fsSL -o "${tmp_dir}/hashicorp.asc" \
    https://www.hashicorp.com/.well-known/pgp-key.txt
  gpg --quiet --import "${tmp_dir}/hashicorp.asc"
  printf '%s\n' "C874011F0AB405110D02105534365D9472D7468F:6:" | gpg --quiet --import-ownertrust

  log_info "Verifying GPG signature"
  gpg --quiet --verify "${tmp_dir}/${sig_file}" "${tmp_dir}/${sums_file}"

  # SHA256 checksum verification
  log_info "Verifying SHA256 checksum"
  cd "${tmp_dir}" || return 1
  sha256sum -c --ignore-missing "${sums_file}"
  cd / || return 1

  # Install the binary
  unzip -o "${tmp_dir}/${zip_file}" -d "${tmp_dir}"
  mv "${tmp_dir}/vault" /usr/bin/vault
  chown root:root /usr/bin/vault
  chmod 0755 /usr/bin/vault
  ln -sf /usr/bin/vault /usr/local/bin/vault

  log_info "Vault Enterprise ${version} installed"
}

start_services() {
  log_info "Enabling the Vault service"

  systemctl daemon-reload

  # Vault starts sealed; no health-check loop here because /v1/sys/health
  # returns non-2xx until init/unseal is performed by an operator.
  systemctl enable --now vault

  log_info "All services started"
}

wait_for_vault_api() {
  log_info "Waiting for Vault API to become available"

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    status="$(curl -sk -o /dev/null -w '%{http_code}' \
      "https://127.0.0.1:8200/v1/sys/health" 2>/dev/null)" || true

    if [ "${status}" != "000" ]; then
      log_info "Vault API responding (HTTP ${status})"
      return 0
    fi

    log_info "Vault API not yet available, retrying in 5 seconds (${attempt}/10)"
    sleep 5
  done

  log_error "Vault API did not respond after ${attempt} attempts, failing bootstrap"
  return 1
}
