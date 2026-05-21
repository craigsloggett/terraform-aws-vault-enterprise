#!/bin/sh
# configure-vault-aws-auth.sh
#
# Enables the Vault AWS IAM auth method and binds the vault-server role to
# the cluster IAM role on the bootstrap node. Followers later use this role
# to authenticate during PKI cert issuance. The vault-server policy is
# written later by configure-vault-pki.sh. Vault resolves policy names
# lazily at token issuance, so binding before policy creation is safe.

set -euf

# shellcheck source=bootstrap.env.tftpl
. /var/lib/cloud/scripts/bootstrap.env
# shellcheck source=SCRIPTDIR/common-functions.sh
. /var/lib/cloud/scripts/common-functions.sh

enable_aws_auth_method() (
  log_info "Enabling the Vault AWS auth method at: aws/"

  if ! vault auth list -format=json | jq -e '."aws/"' >/dev/null 2>&1; then
    vault auth enable -description="authenticates AWS resources via IAM identity" aws
  fi
)

configure_vault_aws_role() (
  log_info "Configuring the Vault AWS auth role: vault-server"

  role_vault_server_payload="$(
    jq -nc \
      --arg bound_iam_principal_arn "${VAULT_IAM_ROLE_ARN}" \
      --arg iam_server_id_header_value "${VAULT_FQDN}" \
      --arg max_ttl "${VAULT_AWS_AUTH_ROLE_MAX_TTL}" \
      --arg ttl "${VAULT_AWS_AUTH_ROLE_TTL}" \
      '{
        auth_type: "iam",
        bound_iam_principal_arn: $bound_iam_principal_arn,
        iam_server_id_header_value: $iam_server_id_header_value,
        policies: "vault-server",
        max_ttl: $max_ttl,
        ttl: $ttl
      }'
  )"
  vault write auth/aws/role/vault-server - >/dev/null <<EOF
"${role_vault_server_payload}"
EOF
)

main() {
  bootstrap_instance_id="$(fetch_parameter "${BOOTSTRAP_INSTANCE_ID_SSM_PARAMETER_NAME}")"

  if [ "${INSTANCE_ID}" != "${bootstrap_instance_id}" ]; then
    return 0
  fi

  export VAULT_ADDR="https://127.0.0.1:8200"
  export VAULT_TLS_SERVER_NAME="${VAULT_FQDN}"
  export VAULT_CACERT="/opt/vault/tls/ca.crt"
  VAULT_TOKEN="$(fetch_secret "${ROOT_TOKEN_SECRET_ARN}")"
  export VAULT_TOKEN

  enable_aws_auth_method
  configure_vault_aws_role
}

main "$@"
