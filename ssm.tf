resource "aws_ssm_parameter" "vault_pki_ca_cert" {
  name        = "/${var.project_name}/vault/pki/ca-cert"
  type        = "String"
  value       = "uninitialized"
  description = "Vault PKI CA certificate PEM (public)"

  lifecycle {
    ignore_changes = [value]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-pki-ca-cert" })
}
