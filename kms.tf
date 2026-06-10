data "aws_iam_role" "kms_additional_usage" {
  count = var.kms_key.additional_usage_role_name != null ? 1 : 0

  name = var.kms_key.additional_usage_role_name
}

data "aws_iam_policy_document" "auto_unseal_key_policy" {
  statement {
    sid    = "KeyAdministration"
    effect = "Allow"

    # Administrative actions only, no cryptographic operations. Keeping
    # kms:Put* delegated to IAM lets the deployer correct this policy,
    # preventing lockout, while usage stays pinned to the principals below.
    actions = [
      "kms:CancelKeyDeletion",
      "kms:Create*",
      "kms:Delete*",
      "kms:Describe*",
      "kms:Disable*",
      "kms:Enable*",
      "kms:Get*",
      "kms:List*",
      "kms:Put*",
      "kms:Revoke*",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:Update*",
    ]

    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AutoUnsealUsage"
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = ["*"]

    principals {
      type = "AWS"
      identifiers = concat(
        [aws_iam_role.vault_enterprise.arn],
        data.aws_iam_role.kms_additional_usage[*].arn
      )
    }
  }
}

resource "aws_kms_key" "auto_unseal" {
  description             = "Vault Enterprise Auto-unseal Key"
  deletion_window_in_days = var.kms_key.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.auto_unseal_key_policy.json

  tags = {
    Name = var.kms_key.name
  }
}

resource "aws_kms_alias" "auto_unseal" {
  name          = "alias/${var.kms_key.alias}"
  target_key_id = aws_kms_key.auto_unseal.key_id
}
