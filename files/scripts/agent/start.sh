# shellcheck shell=sh
# start.sh — Start the Vault Agent systemd service.

start_vault_agent() {
  log_info "Starting Vault Agent"

  systemctl daemon-reload
  systemctl enable --now vault-agent

  log_info "Vault Agent started"
}
