resource "aws_ssm_parameter" "vault_pki_root_ca_cert" {
  name        = "/${var.project_name}/vault/pki-root/ca-cert"
  type        = "String"
  value       = "uninitialized"
  description = "Vault PKI root CA certificate PEM"

  lifecycle {
    ignore_changes = [value]
  }

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-pki-root-ca-cert" })
}
