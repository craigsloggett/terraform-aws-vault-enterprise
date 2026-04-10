# Bootstrap TLS for the Vault listener.
#
# This file generates the self-signed CA and server cert that Vault uses
# during initial bootstrap, before the Vault PKI secrets engine is mounted.
# Once PKI is set up, the Vault listener cert is rotated to one issued by
# Vault itself via Vault Agent, and this file's resources become the
# trust anchor only, the CA stays, the server cert becomes irrelevant.

# CA

resource "tls_private_key" "bootstrap_ca" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_self_signed_cert" "bootstrap_ca" {
  private_key_pem = tls_private_key.bootstrap_ca.private_key_pem

  subject {
    common_name  = "${var.project_name} CA"
    organization = var.project_name
  }

  validity_period_hours = 24
  is_ca_certificate     = true

  allowed_uses = [
    "cert_signing",
    "crl_signing",
  ]
}

# Server

resource "tls_private_key" "bootstrap_server" {
  algorithm   = "ECDSA"
  ecdsa_curve = "P384"
}

resource "tls_cert_request" "bootstrap_server" {
  private_key_pem = tls_private_key.bootstrap_server.private_key_pem

  subject {
    common_name  = local.vault_fqdn
    organization = var.project_name
  }

  dns_names = [
    local.vault_fqdn,
    "localhost"
  ]

  ip_addresses = ["127.0.0.1"]
}

resource "tls_locally_signed_cert" "bootstrap_server" {
  cert_request_pem   = tls_cert_request.bootstrap_server.cert_request_pem
  ca_private_key_pem = tls_private_key.bootstrap_ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.bootstrap_ca.cert_pem

  validity_period_hours = 24

  allowed_uses = [
    "digital_signature",
    "key_encipherment",
    "server_auth"
  ]
}

# Secrets Manager

resource "aws_secretsmanager_secret" "vault_bootstrap_ca_cert" {
  name_prefix = "${var.project_name}-vault-bootstrap-tls-ca-cert-"
  description = "Bootstrap TLS CA certificate for Vault"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-bootstrap-tls-ca-cert" })
}

resource "aws_secretsmanager_secret_version" "vault_bootstrap_ca_cert" {
  secret_id     = aws_secretsmanager_secret.vault_bootstrap_ca_cert.id
  secret_string = tls_self_signed_cert.bootstrap_ca.cert_pem
}

resource "aws_secretsmanager_secret" "vault_bootstrap_server_cert" {
  name_prefix = "${var.project_name}-vault-bootstrap-tls-server-cert-"
  description = "Bootstrap TLS server certificate for Vault"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-bootstrap-tls-server-cert" })
}

resource "aws_secretsmanager_secret_version" "vault_bootstrap_server_cert" {
  secret_id     = aws_secretsmanager_secret.vault_bootstrap_server_cert.id
  secret_string = tls_locally_signed_cert.bootstrap_server.cert_pem
}

resource "aws_secretsmanager_secret" "vault_bootstrap_server_key" {
  name_prefix = "${var.project_name}-vault-bootstrap-tls-server-key-"
  description = "Bootstrap TLS server private key for Vault"

  tags = merge(var.common_tags, { Name = "${var.project_name}-vault-bootstrap-tls-server-key" })
}

resource "aws_secretsmanager_secret_version" "vault_bootstrap_server_key" {
  secret_id     = aws_secretsmanager_secret.vault_bootstrap_server_key.id
  secret_string = tls_private_key.bootstrap_server.private_key_pem
}

resource "aws_secretsmanager_secret_policy" "vault_bootstrap_server_key" {
  secret_arn = aws_secretsmanager_secret.vault_bootstrap_server_key.arn
  policy     = data.aws_iam_policy_document.vault_bootstrap_server_key.json
}

data "aws_iam_policy_document" "vault_bootstrap_server_key" {
  statement {
    sid    = "AllowVaultInstanceRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.vault.arn]
    }

    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.vault_bootstrap_server_key.arn]
  }
}
