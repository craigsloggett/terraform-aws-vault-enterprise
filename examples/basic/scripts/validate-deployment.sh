#!/bin/sh
# Usage: ./validate-deployment.sh us-east-1

log() {
  printf '%b%s %b%s%b %s\n' \
    "${c1}" "${3:-->}" "${c3}${2:+$c2}" "$1" "${c3}" "$2" >&2
}

read_terraform_outputs() {
  log "Reading Terraform outputs."

  bastion_ip=$(terraform output -raw bastion_public_ip)
  vault_url=$(terraform output -raw vault_url)
  vault_ips=$(terraform output -json vault_private_ips | jq -r '.[]')
  tg_arn=$(terraform output -raw vault_target_group_arn)

  log "  Bastion IP:" "${bastion_ip}"
  log "  Vault URL:" "${vault_url}"
  # shellcheck disable=SC2086
  log "  Vault nodes:" "$(printf '%s ' ${vault_ips})"
}

check_target_health() {
  log "Checking NLB target group health."

  aws elbv2 describe-target-health \
    --region "${region}" \
    --target-group-arn "${tg_arn}" \
    --query 'TargetHealthDescriptions[].{Target:Target.Id,Health:TargetHealth.State,Reason:TargetHealth.Reason}' \
    --output table
}

validate_node() {
  log "Checking vault node:" "$1"

  # shellcheck disable=SC2086
  ssh ${ssh_opts} \
    -o "ProxyCommand ssh ${ssh_opts} -W %h:%p ubuntu@${bastion_ip}" \
    "ubuntu@$1" sh -s <<'REMOTE'
    printf 'Cloud-init status: %s\n' "$(cloud-init status 2>/dev/null || echo 'unknown')"

    printf 'EBS volume mounted: '
    if mountpoint -q /opt/vault/data; then echo "yes"; else echo "NO"; fi

    printf 'Vault binary: '
    if command -v vault >/dev/null 2>&1; then vault version; else echo "NOT FOUND"; fi

    printf 'TLS CA cert: '
    if sudo test -f /opt/vault/tls/ca.crt; then echo "present"; else echo "MISSING"; fi

    printf 'TLS server cert: '
    if sudo test -f /opt/vault/tls/server.crt; then echo "present"; else echo "MISSING"; fi

    printf 'TLS server key: '
    if sudo test -f /opt/vault/tls/server.key; then echo "present"; else echo "MISSING"; fi

    printf 'Vault config: '
    if [ -f /etc/vault.d/vault.hcl ]; then echo "present"; else echo "MISSING"; fi

    printf 'Vault license: '
    if [ -f /opt/vault/vault.hclic ]; then echo "present"; else echo "MISSING"; fi

    printf 'Vault service enabled: '
    if systemctl is-enabled vault >/dev/null 2>&1; then echo "yes"; else echo "NO"; fi

    printf 'Vault service running: '
    if systemctl is-active vault >/dev/null 2>&1; then echo "yes"; else echo "no"; fi
REMOTE
}

main() {
  set -ef

  region="${1:?Usage: $0 <region>}"
  ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o BatchMode=yes -o LogLevel=ERROR"

  # Colors are automatically disabled if output is not a terminal.
  ! [ -t 2 ] || {
    c1='\033[1;33m'
    c2='\033[1;34m'
    c3='\033[m'
  }

  read_terraform_outputs
  check_target_health

  for ip in ${vault_ips}; do
    validate_node "${ip}"
  done

  log "Validation complete."
}

main "$@"
