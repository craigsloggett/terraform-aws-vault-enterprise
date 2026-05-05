resource "aws_kms_key" "auto_unseal" {
  description             = "Vault Enterprise Auto-unseal Key"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = var.kms_key.name
  }
}

resource "aws_kms_alias" "auto_unseal" {
  name          = "alias/${var.kms_key.alias}"
  target_key_id = aws_kms_key.auto_unseal.key_id
}
