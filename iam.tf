locals {
  iam_project_name = replace(title(replace(var.project_name, "-", " ")), " ", "")
}

moved {
  from = aws_iam_role.vault
  to   = aws_iam_role.vault_server_instance
}

moved {
  from = aws_iam_instance_profile.vault
  to   = aws_iam_instance_profile.vault_server_instance
}

moved {
  from = aws_iam_role_policy.vault_kms
  to   = aws_iam_role_policy.vault_server_kms_read_write
}

moved {
  from = aws_iam_role_policy.vault_s3
  to   = aws_iam_role_policy.vault_server_s3_read_write
}

moved {
  from = aws_iam_role_policy.vault_ec2_describe
  to   = aws_iam_role_policy.vault_server_ec2_read
}

moved {
  from = aws_iam_role_policy.vault_ssm
  to   = aws_iam_role_policy.vault_server_ssm_read_write
}

moved {
  from = aws_iam_role_policy.vault_iam_read
  to   = aws_iam_role_policy.vault_server_iam_read
}

data "aws_iam_policy_document" "vault_server_instance_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "vault_server_instance" {
  name               = "VaultServer${local.iam_project_name}InstanceRole"
  assume_role_policy = data.aws_iam_policy_document.vault_server_instance_assume_role.json

  tags = merge(var.common_tags, { Name = "VaultServer${local.iam_project_name}InstanceRole" })
}

resource "aws_iam_instance_profile" "vault_server_instance" {
  name = "VaultServer${local.iam_project_name}InstanceProfile"
  role = aws_iam_role.vault_server_instance.name

  tags = merge(var.common_tags, { Name = "VaultServer${local.iam_project_name}InstanceProfile" })
}

# KMS (auto-unseal)

data "aws_iam_policy_document" "vault_server_kms_read_write" {
  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [aws_kms_key.vault.arn]
  }
}

resource "aws_iam_role_policy" "vault_server_kms_read_write" {
  name   = "VaultServer${local.iam_project_name}KMSReadWritePolicy"
  role   = aws_iam_role.vault_server_instance.id
  policy = data.aws_iam_policy_document.vault_server_kms_read_write.json
}

# Secrets Manager (license, TLS materials, signed intermediate CSR)

data "aws_iam_policy_document" "vault_server_secrets_manager_read" {
  statement {
    effect  = "Allow"
    actions = ["secretsmanager:GetSecretValue"]
    resources = [
      aws_secretsmanager_secret.vault_enterprise_license.arn,
      aws_secretsmanager_secret.vault_bootstrap_tls_ca.arn,
      aws_secretsmanager_secret.vault_bootstrap_tls_cert.arn,
      aws_secretsmanager_secret.vault_bootstrap_tls_private_key.arn,
      aws_secretsmanager_secret.vault_pki_intermediate_ca_signed_csr.arn,
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:DescribeSecret"]
    resources = [aws_secretsmanager_secret.vault_pki_intermediate_ca_signed_csr.arn]
  }
}

resource "aws_iam_role_policy" "vault_server_secrets_manager_read" {
  name   = "VaultServer${local.iam_project_name}SecretsManagerReadPolicy"
  role   = aws_iam_role.vault_server_instance.id
  policy = data.aws_iam_policy_document.vault_server_secrets_manager_read.json
}

# Secrets Manager (bootstrap root token, recovery keys — read/write during initialization)

data "aws_iam_policy_document" "vault_server_secrets_manager_read_write" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:PutSecretValue",
    ]
    resources = [
      aws_secretsmanager_secret.vault_bootstrap_root_token.arn,
      aws_secretsmanager_secret.vault_recovery_keys.arn,
    ]
  }
}

resource "aws_iam_role_policy" "vault_server_secrets_manager_read_write" {
  name   = "VaultServer${local.iam_project_name}SecretsManagerReadWritePolicy"
  role   = aws_iam_role.vault_server_instance.id
  policy = data.aws_iam_policy_document.vault_server_secrets_manager_read_write.json
}

# S3 (snapshots)

data "aws_iam_policy_document" "vault_server_s3_read_write" {
  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:DeleteObject",
    ]
    resources = [
      aws_s3_bucket.vault_snapshots.arn,
      "${aws_s3_bucket.vault_snapshots.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "vault_server_s3_read_write" {
  name   = "VaultServer${local.iam_project_name}S3ReadWritePolicy"
  role   = aws_iam_role.vault_server_instance.id
  policy = data.aws_iam_policy_document.vault_server_s3_read_write.json
}

# EC2 (auto-join)

data "aws_iam_policy_document" "vault_server_ec2_read" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:DescribeInstances"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "vault_server_ec2_read" {
  name   = "VaultServer${local.iam_project_name}EC2ReadPolicy"
  role   = aws_iam_role.vault_server_instance.id
  policy = data.aws_iam_policy_document.vault_server_ec2_read.json
}

# SSM Parameter Store (cluster, PKI, TLS state)

data "aws_iam_policy_document" "vault_server_ssm_read_write" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter",
    ]
    resources = [
      aws_ssm_parameter.vault_cluster_state.arn,
      aws_ssm_parameter.vault_pki_state.arn,
      aws_ssm_parameter.vault_tls_ca_bundle.arn,
      aws_ssm_parameter.vault_pki_intermediate_ca_csr.arn,
    ]
  }
}

resource "aws_iam_role_policy" "vault_server_ssm_read_write" {
  name   = "VaultServer${local.iam_project_name}SSMReadWritePolicy"
  role   = aws_iam_role.vault_server_instance.id
  policy = data.aws_iam_policy_document.vault_server_ssm_read_write.json
}

# IAM (resolve own role ARN at runtime)

data "aws_iam_policy_document" "vault_server_iam_read" {
  statement {
    effect    = "Allow"
    actions   = ["iam:GetRole"]
    resources = [aws_iam_role.vault_server_instance.arn]
  }
}

resource "aws_iam_role_policy" "vault_server_iam_read" {
  name   = "VaultServer${local.iam_project_name}IAMReadPolicy"
  role   = aws_iam_role.vault_server_instance.id
  policy = data.aws_iam_policy_document.vault_server_iam_read.json
}
