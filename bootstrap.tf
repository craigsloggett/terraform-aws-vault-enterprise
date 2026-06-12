# Resources used only during the initial Vault cluster bootstrap process.

# Initialization Coordination SSM Parameters

resource "aws_ssm_parameter" "bootstrap_vault_cluster_state" {
  name        = var.bootstrap.ssm_parameter.vault_cluster_state_name
  type        = "String"
  value       = "Uninitialized"
  description = "Bootstrap Initialization State Flag"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "bootstrap_vault_pki_state" {
  name        = var.bootstrap.ssm_parameter.vault_pki_state_name
  type        = "String"
  value       = "Uninitialized"
  description = "Bootstrap PKI State Flag"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "bootstrap_instance_id" {
  name        = var.bootstrap.ssm_parameter.instance_id_name
  type        = "String"
  value       = "Uninitialized"
  description = "EC2 instance ID of the elected bootstrap node"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "bootstrap_tls_ca_certificate" {
  name        = var.bootstrap.ssm_parameter.tls_ca_certificate_name
  type        = "String"
  value       = "Uninitialized"
  description = "Bootstrap node ephemeral TLS CA certificate PEM"

  lifecycle {
    ignore_changes = [value]
  }
}
