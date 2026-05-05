resource "aws_secretsmanager_secret" "vault_enterprise_license" {
  name_prefix = var.secretsmanager_secret.vault_enterprise_license_name_prefix
  description = "Vault Enterprise License"
}

resource "aws_secretsmanager_secret_version" "vault_enterprise_license" {
  secret_id     = aws_secretsmanager_secret.vault_enterprise_license.id
  secret_string = var.vault_enterprise_license
}

resource "aws_secretsmanager_secret" "intermediate_ca_signed_csr" {
  name_prefix = var.secretsmanager_secret.intermediate_ca_signed_csr_name_prefix
  description = "Vault Enterprise Intermediate CA and Signed CSR"
}

resource "aws_secretsmanager_secret" "recovery_keys" {
  name_prefix = var.secretsmanager_secret.recovery_keys_name_prefix
  description = "Vault Enterprise Recovery Keys"
}
