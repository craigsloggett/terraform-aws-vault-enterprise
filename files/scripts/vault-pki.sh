# shellcheck shell=sh disable=SC2154
# vault-pki.sh — PKI secrets engine and AWS auth method configuration.
#
# These functions run only on the bootstrap node after cluster init.
#
# Requires globals: region, vault_fqdn, vault_iam_role_arn,
#   vault_pki_mount_max_ttl, vault_pki_root_ca_ttl,
#   vault_pki_vault_server_role_max_ttl, vault_aws_auth_role_max_ttl,
#   vault_aws_auth_role_ttl, vault_pki_organization, vault_pki_country,
#   cluster_name, ssm_pki_ca_cert_name, ssm_pki_state_name,
#   vault_audit_log_file

configure_pki_engine() {
  log_info "Configuring Vault PKI secrets engine"

  # Enable the PKI secrets engine if not already enabled.
  if ! vault secrets list -format=json | jq -e '."pki/"' >/dev/null 2>&1; then
    vault secrets enable pki
  fi

  vault secrets tune -max-lease-ttl="${vault_pki_mount_max_ttl}" pki

  # Generate root CA with ECDSA P-384 keys, consistent with the bootstrap
  # CA and server certs in tls.tf.
  vault write -format=json pki/root/generate/internal \
    common_name="${cluster_name} Vault Root CA" \
    organization="${vault_pki_organization}" \
    country="${vault_pki_country}" \
    ttl="${vault_pki_root_ca_ttl}" \
    key_type=ec \
    key_bits=384 |
    jq -r '.data.certificate' >/dev/null

  # Configure issuing certificate, CRL, and OCSP URLs.
  # Vault's built-in OCSP responder handles /v1/pki/ocsp natively.
  vault write pki/config/urls \
    issuing_certificates="https://${vault_fqdn}:8200/v1/pki/ca" \
    crl_distribution_points="https://${vault_fqdn}:8200/v1/pki/crl" \
    ocsp_servers="https://${vault_fqdn}:8200/v1/pki/ocsp"

  # Create the vault-server role used by nodes to issue their own TLS certs.
  vault write pki/roles/vault-server \
    allowed_domains="${vault_fqdn}" \
    allow_bare_domains=true \
    allow_subdomains=false \
    allow_localhost=false \
    allow_ip_sans=false \
    max_ttl="${vault_pki_vault_server_role_max_ttl}" \
    key_type=ec \
    key_bits=384 \
    ext_key_usage=serverAuth

  # Publish the new CA cert PEM to SSM so follower nodes can fetch it and
  # trust the new CA before attempting AWS auth. The CA cert is public
  # material, it is the trust anchor, not the signing key.
  log_info "Publishing PKI CA cert to SSM"
  ca_cert_pem="$(vault read -field=certificate pki/cert/ca)"
  aws ssm put-parameter \
    --region "${region}" \
    --name "${ssm_pki_ca_cert_name}" \
    --value "${ca_cert_pem}" \
    --overwrite

  log_info "PKI secrets engine configured"
}

configure_aws_auth() {
  log_info "Configuring Vault AWS auth method"

  # Enable the AWS auth method if not already enabled.
  if ! vault auth list -format=json | jq -e '."aws/"' >/dev/null 2>&1; then
    vault auth enable aws
  fi

  # Write a policy granting nodes the ability to issue certs from the
  # vault-server PKI role. No broader permissions are needed.
  vault policy write vault-server - <<EOF
path "pki/issue/vault-server" {
  capabilities = ["create", "update"]
}
EOF

  # Bind the Vault instance IAM role to the vault-server policy.
  # Nodes authenticate by signing a GetCallerIdentity request with their
  # instance profile credentials, no shared secrets.
  vault write auth/aws/role/vault-server \
    auth_type=iam \
    bound_iam_principal_arn="${vault_iam_role_arn}" \
    policies=vault-server \
    max_ttl="${vault_aws_auth_role_max_ttl}" \
    ttl="${vault_aws_auth_role_ttl}"

  # Enable the file audit device. /var/log/vault is on a dedicated EBS volume
  # (see prepare_disk in main) to isolate audit log IO and growth from the
  # root filesystem.
  if ! vault audit list -format=json | jq -e '."file/"' >/dev/null 2>&1; then
    vault audit enable file file_path="${vault_audit_log_file}"
  fi

  log_info "Writing PKI state: ready"
  aws ssm put-parameter \
    --region "${region}" \
    --name "${ssm_pki_state_name}" \
    --value "ready" \
    --overwrite

  log_info "AWS auth method configured"
}
